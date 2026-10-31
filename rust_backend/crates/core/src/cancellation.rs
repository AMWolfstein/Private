//! Request cancellation with Go-compatible sentinels and reference counting.
//!
//! Work polls `check_active` at its checkpoints; cancellation is never pushed.
//! Leases release their reference on drop. Shutdown closes the instance, so
//! every later check fails, including for untracked requests with an empty ID.

use std::collections::BTreeMap;
use std::collections::VecDeque;
use std::fmt;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Mutex};

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

/// Cancelled ids that no lease holds yet. A pre-cancel is kept so a later
/// acquire of the same id starts cancelled; only the newest are kept, so a
/// stream of cancels for ids that never run cannot grow the registry.
const MAX_TOMBSTONES: usize = 256;

#[derive(Default)]
struct State {
    closed: bool,
    entries: BTreeMap<String, Entry>,
    tombstones: VecDeque<String>,
}

impl State {
    fn remember_tombstone(&mut self, id: &str) {
        self.tombstones.push_back(id.to_owned());
        while self.tombstones.len() > MAX_TOMBSTONES {
            let Some(oldest) = self.tombstones.pop_front() else {
                break;
            };
            // Only drop it while no lease holds it; a live lease owns its entry.
            if self
                .entries
                .get(&oldest)
                .is_some_and(|entry| entry.references == 0)
            {
                self.entries.remove(&oldest);
            }
        }
    }
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

/// Cancellation is cooperative: work observes it through `check_active` and
/// `is_cancelled` at its checkpoints, so there is no wake-up to deliver.
#[derive(Default)]
struct Shared {
    state: Mutex<State>,
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
        for id in ids.into_iter().filter(|id| !id.is_empty()) {
            if !state.entries.contains_key(id) {
                state.remember_tombstone(id);
            }
            state
                .entries
                .entry(id.to_owned())
                .or_default()
                .cancelled
                .store(true, Ordering::Release);
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
    }
}

impl Default for CancellationRegistry {
    fn default() -> Self {
        Self::new()
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
    fn pre_cancels_for_ids_that_never_run_are_bounded() {
        let registry = CancellationRegistry::new();
        let ids: Vec<String> = (0..MAX_TOMBSTONES * 3)
            .map(|i| format!("never-{i}"))
            .collect();
        registry
            .cancel_many(ids.iter().map(String::as_str))
            .unwrap();
        let entries = registry.shared.state.lock().unwrap().entries.len();
        assert!(entries <= MAX_TOMBSTONES, "kept {entries} pre-cancels");
        // The newest pre-cancel still applies to a later acquire.
        let newest = ids.last().unwrap();
        assert!(registry.acquire(newest).unwrap().is_cancelled().unwrap());
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
