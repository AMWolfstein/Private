//! One explicitly started, cancellable update worker per mobile Backend owner.
use mornye_core::app_version::AppVersion;
use mornye_network::{HttpRequest, NetworkService, policy::NetworkPermissions};
use mornye_providers::configuration::{
    ConfigCache, ConfigError, MAX_ENVELOPE_BYTES, ProviderConfig,
};
use serde::Serialize;
use std::collections::BTreeMap;
use std::io::{Read, Write};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex};
use std::thread::JoinHandle;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

const ENDPOINT: &str = "https://raw.githubusercontent.com/AMWolfstein/Private/extension-system/extensions/config/providers.signed.json";
const POLL: Duration = Duration::from_secs(24 * 60 * 60);
const RETRY: Duration = Duration::from_secs(15 * 60);
type Check<'a> = dyn Fn() -> Result<(), String> + Sync + 'a;
type Fetch = dyn Fn(&Check<'_>) -> Result<Vec<u8>, FetchError> + Send + Sync;

struct FetchError {
    message: String,
    completed_http: bool,
}

#[derive(Clone, Debug, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
enum State {
    NotStarted,
    Disabled,
    Checking,
    Throttled,
    UpToDate,
    PendingRestart,
    Failed,
    Cancelled,
}

#[derive(Clone, Serialize)]
pub(super) struct Status {
    state: State,
    candidate_revision: Option<u64>,
    error: Option<Failure>,
}

#[derive(Clone, Serialize)]
struct Failure {
    kind: &'static str,
    message: String,
}

struct Shared {
    stop: AtomicBool,
    enabled: AtomicBool,
    status: Mutex<Status>,
    wait: Mutex<()>,
    wake: Condvar,
}

impl Shared {
    fn set(&self, state: State, revision: Option<u64>, error: Option<Failure>) {
        *self.status.lock().expect("provider update status") = Status {
            state,
            candidate_revision: revision,
            error,
        };
    }

    fn check(&self) -> Result<(), String> {
        if self.stop.load(Ordering::Acquire) {
            Err("provider update cancelled".into())
        } else {
            Ok(())
        }
    }

    fn pause(&self, duration: Duration) {
        let lock = self.wait.lock().expect("provider update wait");
        if self.check().is_ok() {
            // A spurious wake does not turn this into an unthrottled poll loop.
            drop(
                self.wake
                    .wait_timeout_while(lock, duration, |_| self.check().is_ok())
                    .expect("provider update timer"),
            );
        }
    }
}

pub(super) struct ProviderUpdates {
    shared: Arc<Shared>,
    worker: Mutex<Option<JoinHandle<()>>>,
}

impl Default for ProviderUpdates {
    fn default() -> Self {
        Self {
            shared: Arc::new(Shared {
                stop: AtomicBool::new(false),
                enabled: AtomicBool::new(false),
                status: Mutex::new(Status {
                    state: State::NotStarted,
                    candidate_revision: None,
                    error: None,
                }),
                wait: Mutex::new(()),
                wake: Condvar::new(),
            }),
            worker: Mutex::new(None),
        }
    }
}

impl ProviderUpdates {
    pub fn status(&self) -> Status {
        self.shared
            .status
            .lock()
            .expect("provider update status")
            .clone()
    }
    pub fn enabled(&self) -> bool {
        self.shared.enabled.load(Ordering::Acquire)
    }

    pub fn start(
        &self,
        network: &Arc<NetworkService>,
        version: AppVersion,
        cache: Arc<Mutex<ConfigCache>>,
        active: ProviderConfig,
        directory: &Path,
    ) -> Result<(), ConfigError> {
        let session = network.session(
            NetworkPermissions {
                domains: vec!["raw.githubusercontent.com".into()],
                allow_http: false,
            },
            Duration::from_secs(15),
        );
        let fetch: Arc<Fetch> = Arc::new(move |check| {
            let started = Instant::now();
            let bounded = || {
                check()?;
                if started.elapsed() >= Duration::from_secs(15) {
                    Err("provider update deadline exceeded".into())
                } else {
                    Ok(())
                }
            };
            let mut stream = session
                .open_stream(
                    HttpRequest {
                        url: ENDPOINT.into(),
                        method: "GET".into(),
                        body: String::new(),
                        headers: BTreeMap::new(),
                        default_json: false,
                        user_agent: version.user_agent(),
                    },
                    Duration::from_secs(15),
                    Duration::from_secs(15),
                    bounded,
                )
                .map_err(|message| FetchError {
                    message,
                    completed_http: false,
                })?;
            if stream.response.status != 200 {
                return Err(FetchError {
                    message: format!("update HTTP {}", stream.response.status),
                    completed_http: true,
                });
            }
            stream
                .read_limited(MAX_ENVELOPE_BYTES, &mut [0; 8192], bounded)
                .map_err(|message| FetchError {
                    message,
                    completed_http: false,
                })?
                .ok_or_else(|| FetchError {
                    message: "update envelope exceeds 96 KiB".into(),
                    completed_http: true,
                })
        });
        self.start_with_fetch(cache, active, directory.to_owned(), fetch, POLL, RETRY)
    }

    fn start_with_fetch(
        &self,
        cache: Arc<Mutex<ConfigCache>>,
        active: ProviderConfig,
        directory: PathBuf,
        fetch: Arc<Fetch>,
        poll: Duration,
        retry: Duration,
    ) -> Result<(), ConfigError> {
        let mut worker = self
            .worker
            .lock()
            .map_err(|_| ConfigError::BackendUnavailable("update worker lock poisoned".into()))?;
        self.shared
            .check()
            .map_err(ConfigError::BackendUnavailable)?;
        if worker.is_some() {
            return Ok(());
        }
        if !cache
            .lock()
            .map_err(|_| ConfigError::BackendUnavailable("configuration lock poisoned".into()))?
            .has_trusted_keys()
        {
            self.shared.set(State::Disabled, None, None);
            return Ok(());
        }
        let shared = self.shared.clone();
        let handle = std::thread::Builder::new()
            .name("provider-config-update".into())
            .spawn(move || run(&shared, &cache, &active, &directory, &fetch, poll, retry));
        match handle {
            Ok(handle) => *worker = Some(handle),
            Err(error) => {
                self.shared.set(
                    State::Failed,
                    None,
                    Some(Failure {
                        kind: "persistence",
                        message: error.to_string(),
                    }),
                );
                return Err(ConfigError::Persistence(error));
            }
        }
        self.shared.enabled.store(true, Ordering::Release);
        Ok(())
    }

    pub fn shutdown(&self) {
        {
            let _lock = self.shared.wait.lock().expect("provider update stop");
            self.shared.stop.store(true, Ordering::Release);
            self.shared.wake.notify_all();
        }
        let worker = self.worker.lock().expect("provider update worker").take();
        if let Some(worker) = worker {
            let _ = worker.join();
        }
    }
}

impl Drop for ProviderUpdates {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn timestamp() -> u64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .unwrap_or_default()
        .as_secs()
}

fn last_attempt(directory: &Path) -> Option<u64> {
    let file = std::fs::File::open(directory.join(".provider-config-last-check")).ok()?;
    let mut bytes = Vec::new();
    file.take(65).read_to_end(&mut bytes).ok()?;
    if bytes.len() > 64 {
        return None;
    }
    std::str::from_utf8(&bytes).ok()?.parse().ok()
}

fn remember_attempt(directory: &Path, now: u64) -> std::io::Result<()> {
    let mut file = tempfile::NamedTempFile::new_in(directory)?;
    write!(file, "{now}")?;
    file.persist(directory.join(".provider-config-last-check"))
        .map_err(|e| e.error)?;
    Ok(())
}

fn failure(error: ConfigError) -> Failure {
    let kind = match &error {
        ConfigError::Authentication(_) => "authentication",
        ConfigError::Invalid(_) => "invalid",
        ConfigError::Revision => "revision",
        ConfigError::Persistence(_) => "persistence",
        ConfigError::BackendUnavailable(_) => "persistence",
    };
    Failure {
        kind,
        message: error.to_string(),
    }
}

fn publish(
    cache: &Mutex<ConfigCache>,
    active: &ProviderConfig,
    bytes: &[u8],
    check: &Check<'_>,
) -> Result<(State, u64), ConfigError> {
    let cache = cache
        .lock()
        .map_err(|_| ConfigError::BackendUnavailable("configuration lock poisoned".into()))?;
    let candidate = cache.authenticate(bytes)?;
    if candidate.revision() < active.revision() {
        return Err(ConfigError::Revision);
    }
    let previous = cache.load().config;
    if candidate == previous {
        let state = if candidate.revision() > active.revision() {
            State::PendingRestart
        } else {
            State::UpToDate
        };
        return Ok((state, candidate.revision()));
    }
    if candidate.revision() == active.revision() && candidate != *active {
        return Err(ConfigError::Revision);
    }
    check().map_err(ConfigError::BackendUnavailable)?;
    // Once atomic publication completes, shutdown must not turn it into a
    // reported cancellation or roll it back. It remains pending next startup.
    let installed = cache.install(bytes)?;
    Ok((State::PendingRestart, installed.revision()))
}

fn run(
    shared: &Shared,
    cache: &Mutex<ConfigCache>,
    active: &ProviderConfig,
    directory: &Path,
    fetch: &Arc<Fetch>,
    poll: Duration,
    retry: Duration,
) {
    let now = timestamp();
    if let Some(last) = last_attempt(directory)
        && let Some(age) = now.checked_sub(last)
        && age < poll.as_secs()
    {
        shared.set(State::Throttled, None, None);
        shared.pause(poll.saturating_sub(Duration::from_secs(age)));
    }
    while shared.check().is_ok() {
        shared.set(State::Checking, None, None);
        let result = fetch(&|| shared.check());
        if shared.check().is_err() {
            shared.set(State::Cancelled, None, None);
            break;
        }
        let (delay, completed) = match result {
            Ok(bytes) => {
                match publish(cache, active, &bytes, &|| shared.check()) {
                    Ok((state, revision)) => shared.set(state, Some(revision), None),
                    Err(error) => {
                        if shared.check().is_err() {
                            shared.set(State::Cancelled, None, None);
                            break;
                        }
                        shared.set(State::Failed, None, Some(failure(error)));
                    }
                }
                (poll, true)
            }
            Err(error) => {
                shared.set(
                    State::Failed,
                    None,
                    Some(Failure {
                        kind: "network",
                        message: error.message,
                    }),
                );
                if error.completed_http {
                    (poll, true)
                } else {
                    (retry, false)
                }
            }
        };
        if completed {
            let _ = remember_attempt(directory, timestamp());
        }
        shared.pause(delay);
    }
}

#[cfg(test)]
mod tests;
