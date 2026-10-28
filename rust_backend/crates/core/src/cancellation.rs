//! Request cancellation with Go-compatible sentinels and reference counting.
//!
//! Leases release their reference on drop; an
//! explicit release also wakes a pending wait. Shutdown closes the instance and
//! wakes all leases, including untracked requests with an empty ID.

use std::collections::BTreeMap;
use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, Weak};
use std::thread::Thread;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub enum CancellationError {
    RequestCancelled,
    RegistryClosed,
    LeaseReleased,
}

impl fmt::Display for CancellationError {
    fn fmt(&self, formatter: &mut fmt::Formatter<'_>) -> fmt::Result {
        formatter.write_str(match self {
            Self::RequestCancelled => "request cancelled",
            Self::RegistryClosed => "cancellation registry closed",
            Self::LeaseReleased => "request lease released",
        })
    }
}

impl std::error::Error for CancellationError {}

#[derive(Default)]
struct Entry {
    cancelled: Arc<AtomicBool>,
    references: usize,
}

#[derive(Default)]
struct State {
    closed: bool,
    entries: BTreeMap<String, Entry>,
}

impl State {
    fn check_open(&self) -> Result<(), CancellationError> {
        if self.closed {
            Err(CancellationError::RegistryClosed)
        } else {
            Ok(())
        }
    }
}

#[derive(Default)]
struct Shared {
    state: Mutex<State>,
    changed: Condvar,
    threads: Mutex<Vec<Weak<Thread>>>,
}

impl Shared {
    fn notify(&self) {
        self.changed.notify_all();
        self.threads
            .lock()
            .expect("cancellation thread lock")
            .retain(|thread| {
                if let Some(thread) = thread.upgrade() {
                    thread.unpark();
                    true
                } else {
                    false
                }
            });
    }
}

pub struct CancellationRegistry {
    shared: Arc<Shared>,
}

impl CancellationRegistry {
    pub fn new() -> Self {
        Self {
            shared: Arc::new(Shared::default()),
        }
    }

    pub fn acquire(&self, id: &str) -> Result<RequestLease, CancellationError> {
        let mut state = self.shared.state.lock().expect("cancellation state lock");
        state.check_open()?;
        let cancelled = if id.is_empty() {
            Arc::new(AtomicBool::new(false))
        } else {
            let entry = state.entries.entry(id.to_owned()).or_default();
            entry.references += 1;
            Arc::clone(&entry.cancelled)
        };
        Ok(RequestLease {
            shared: Arc::clone(&self.shared),
            id: id.to_owned(),
            cancelled,
            released: AtomicBool::new(false),
        })
    }

    pub fn cancel(&self, id: &str) -> Result<(), CancellationError> {
        self.cancel_many(std::iter::once(id))
    }

    pub fn cancel_many<'a>(
        &self,
        ids: impl IntoIterator<Item = &'a str>,
    ) -> Result<(), CancellationError> {
        let mut state = self.shared.state.lock().expect("cancellation state lock");
        state.check_open()?;
        let mut changed = false;
        for id in ids.into_iter().filter(|id| !id.is_empty()) {
            state
                .entries
                .entry(id.to_owned())
                .or_default()
                .cancelled
                .store(true, Ordering::Release);
            changed = true;
        }
        drop(state);
        if changed {
            self.shared.notify();
        }
        Ok(())
    }

    pub fn is_cancelled(&self, id: &str) -> Result<bool, CancellationError> {
        let state = self.shared.state.lock().expect("cancellation state lock");
        state.check_open()?;
        Ok(state
            .entries
            .get(id)
            .is_some_and(|entry| entry.cancelled.load(Ordering::Acquire)))
    }

    /// Terminal and idempotent. A new registry is required for subsequent work.
    pub fn shutdown(&self) {
        let mut state = self.shared.state.lock().expect("cancellation state lock");
        state.closed = true;
        state.entries.clear();
        drop(state);
        self.shared.notify();
    }
}

impl Drop for CancellationRegistry {
    fn drop(&mut self) {
        self.shutdown();
    }
}

pub struct RequestLease {
    shared: Arc<Shared>,
    id: String,
    cancelled: Arc<AtomicBool>,
    released: AtomicBool,
}

impl RequestLease {
    fn check_live(&self, state: &State) -> Result<(), CancellationError> {
        state.check_open()?;
        if self.released.load(Ordering::Acquire) {
            return Err(CancellationError::LeaseReleased);
        }
        Ok(())
    }

    pub fn is_cancelled(&self) -> Result<bool, CancellationError> {
        let state = self.shared.state.lock().expect("cancellation state lock");
        self.check_live(&state)?;
        Ok(self.cancelled.load(Ordering::Acquire))
    }

    pub fn check_active(&self) -> Result<(), CancellationError> {
        if self.is_cancelled()? {
            return Err(CancellationError::RequestCancelled);
        }
        Ok(())
    }

    /// Release this acquisition once; other acquisitions for the same ID remain.
    /// Holding or dropping this old lease cannot remove a later retry's entry.
    pub fn release(&self) {
        let mut state = self.shared.state.lock().expect("cancellation state lock");
        if self.released.swap(true, Ordering::AcqRel) {
            return;
        }
        if let Some(entry) = state.entries.get_mut(&self.id) {
            entry.references -= 1;
            if entry.references == 0 {
                state.entries.remove(&self.id);
            }
        }
        drop(state);
        self.shared.notify();
    }
}

impl Drop for RequestLease {
    fn drop(&mut self) {
        self.release();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cancel_many_marks_idle_and_active_ids_without_touching_others() {
        let registry = CancellationRegistry::new();
        let first = registry.acquire("first").unwrap();
        let second = registry.acquire("second").unwrap();
        registry
            .cancel_many(["first", "idle", "idle", "", "音楽"])
            .unwrap();
        assert!(first.is_cancelled().unwrap());
        assert!(!second.is_cancelled().unwrap());
        assert!(registry.acquire("idle").unwrap().is_cancelled().unwrap());
        assert!(registry.is_cancelled("音楽").unwrap());
    }

    #[test]
    fn shutdown_closes_leases_and_rejects_new_work() {
        let registry = CancellationRegistry::new();
        let lease = registry.acquire("job").unwrap();
        lease.release();
        assert_eq!(lease.check_active(), Err(CancellationError::LeaseReleased));
        let anonymous = registry.acquire("").unwrap();
        registry.shutdown();
        assert_eq!(
            anonymous.check_active(),
            Err(CancellationError::RegistryClosed)
        );
        assert_eq!(
            registry.cancel_many(["later"]),
            Err(CancellationError::RegistryClosed)
        );
    }
}
