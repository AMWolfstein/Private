use super::*;
use mornye_providers::configuration::TrustedKeys;
use std::sync::atomic::AtomicUsize;

const KEYS: &[u8] =
    include_bytes!("../../../../../../extensions/config/tests/trusted-test-key.json");
const SIGNED: &[u8] =
    include_bytes!("../../../../../../extensions/config/tests/signed-test-config.json");

fn fixture(root: &Path) -> Arc<Mutex<ConfigCache>> {
    Arc::new(Mutex::new(ConfigCache::new(
        root,
        TrustedKeys::parse(KEYS).unwrap(),
    )))
}

fn wait_for(updater: &ProviderUpdates, state: State) -> Status {
    let deadline = Instant::now() + Duration::from_secs(3);
    loop {
        let status = updater.status();
        if status.state == state {
            return status;
        }
        assert!(
            Instant::now() < deadline,
            "expected {state:?}, got {:?}",
            status.state
        );
        std::thread::park_timeout(Duration::from_millis(1));
    }
}

#[test]
fn construction_and_missing_trust_never_fetch() {
    let root = tempfile::tempdir().unwrap();
    let updater = ProviderUpdates::default();
    assert_eq!(updater.status().state, State::NotStarted);
    assert!(!updater.enabled());
    let cache = Arc::new(Mutex::new(ConfigCache::new(
        root.path(),
        TrustedKeys::default(),
    )));
    updater
        .start_with_fetch(
            cache,
            ProviderConfig::bundled(),
            root.path().to_owned(),
            Arc::new(|_| panic!("disabled updater fetched")),
            POLL,
            RETRY,
        )
        .unwrap();
    assert_eq!(updater.status().state, State::Disabled);
    assert!(!updater.enabled());
    updater.shutdown();
}

#[test]
fn signed_update_is_pending_until_restart_and_daily_timer_is_interruptible() {
    let root = tempfile::tempdir().unwrap();
    let cache = fixture(root.path());
    let updater = ProviderUpdates::default();
    let calls = Arc::new(AtomicUsize::new(0));
    let count = calls.clone();
    let fetch: Arc<Fetch> = Arc::new(move |_| {
        count.fetch_add(1, Ordering::Relaxed);
        Ok(SIGNED.to_vec())
    });
    let active = ProviderConfig::bundled();
    updater
        .start_with_fetch(
            cache.clone(),
            active.clone(),
            root.path().to_owned(),
            fetch.clone(),
            POLL,
            RETRY,
        )
        .unwrap();
    let status = wait_for(&updater, State::PendingRestart);
    assert_eq!(status.candidate_revision, Some(2));
    assert!(status.error.is_none());
    assert_eq!(active.revision(), 1);
    assert!(updater.enabled());
    updater
        .start_with_fetch(
            cache.clone(),
            active,
            root.path().to_owned(),
            fetch,
            POLL,
            RETRY,
        )
        .unwrap();
    let started = Instant::now();
    updater.shutdown();
    assert!(started.elapsed() < Duration::from_secs(1));
    assert_eq!(calls.load(Ordering::Relaxed), 1);
    assert_eq!(cache.lock().unwrap().load().config.revision(), 2);
    let restarted = ProviderUpdates::default();
    restarted
        .start_with_fetch(
            cache,
            ProviderConfig::bundled(),
            root.path().to_owned(),
            Arc::new(|_| panic!("daily throttle ignored")),
            POLL,
            RETRY,
        )
        .unwrap();
    wait_for(&restarted, State::Throttled);
    restarted.shutdown();
}

#[test]
fn offline_start_retries_after_connectivity_recovers_without_restart() {
    let root = tempfile::tempdir().unwrap();
    let cache = fixture(root.path());
    let updater = ProviderUpdates::default();
    let calls = Arc::new(AtomicUsize::new(0));
    let count = calls.clone();
    let directory = root.path().to_owned();
    let fetch: Arc<Fetch> = Arc::new(move |_| {
        let call = count.fetch_add(1, Ordering::Relaxed);
        assert!(
            last_attempt(&directory).is_none(),
            "offline attempt consumed daily interval"
        );
        if call == 0 {
            Err(FetchError {
                message: "offline".into(),
                completed_http: false,
            })
        } else {
            Ok(SIGNED.to_vec())
        }
    });
    updater
        .start_with_fetch(
            cache,
            ProviderConfig::bundled(),
            root.path().to_owned(),
            fetch,
            POLL,
            Duration::from_millis(10),
        )
        .unwrap();
    wait_for(&updater, State::PendingRestart);
    updater.shutdown();
    assert_eq!(calls.load(Ordering::Relaxed), 2);
}

#[test]
fn invalid_envelopes_and_oversized_payloads_never_replace_settings() {
    for bytes in [b"not signed".to_vec(), vec![b'x'; MAX_ENVELOPE_BYTES + 1]] {
        let root = tempfile::tempdir().unwrap();
        let cache = fixture(root.path());
        let updater = ProviderUpdates::default();
        updater
            .start_with_fetch(
                cache.clone(),
                ProviderConfig::bundled(),
                root.path().to_owned(),
                Arc::new(move |_| Ok(bytes.clone())),
                POLL,
                RETRY,
            )
            .unwrap();
        let status = wait_for(&updater, State::Failed);
        updater.shutdown();
        assert_eq!(status.error.unwrap().kind, "invalid");
        assert!(!root.path().join(".provider_config.json").exists());
        assert!(last_attempt(root.path()).is_some());
    }
}

#[test]
fn tampered_signature_has_a_distinct_authentication_error() {
    let root = tempfile::tempdir().unwrap();
    let cache = fixture(root.path());
    let updater = ProviderUpdates::default();
    let mut value: serde_json::Value = serde_json::from_slice(SIGNED).unwrap();
    value["signature"] = "invalid".into();
    let bytes = serde_json::to_vec(&value).unwrap();
    updater
        .start_with_fetch(
            cache,
            ProviderConfig::bundled(),
            root.path().to_owned(),
            Arc::new(move |_| Ok(bytes.clone())),
            POLL,
            RETRY,
        )
        .unwrap();
    assert_eq!(
        wait_for(&updater, State::Failed).error.unwrap().kind,
        "authentication"
    );
    updater.shutdown();
    assert!(!root.path().join(".provider_config.json").exists());
}

#[test]
fn shutdown_cancels_network_wait_and_never_publishes_a_partial_update() {
    let root = tempfile::tempdir().unwrap();
    let cache = fixture(root.path());
    let updater = ProviderUpdates::default();
    let (send, receive) = std::sync::mpsc::channel();
    let fetch: Arc<Fetch> = Arc::new(move |check| {
        send.send(()).unwrap();
        loop {
            if let Err(message) = check() {
                return Err(FetchError {
                    message,
                    completed_http: false,
                });
            }
            std::thread::park_timeout(Duration::from_millis(1));
        }
    });
    updater
        .start_with_fetch(
            cache,
            ProviderConfig::bundled(),
            root.path().to_owned(),
            fetch,
            POLL,
            RETRY,
        )
        .unwrap();
    receive.recv_timeout(Duration::from_secs(3)).unwrap();
    let started = Instant::now();
    updater.shutdown();
    assert!(started.elapsed() < Duration::from_secs(1));
    assert_eq!(updater.status().state, State::Cancelled);
    assert!(!root.path().join(".provider_config.json").exists());
    assert!(last_attempt(root.path()).is_none());
}

#[test]
fn future_poll_timestamp_does_not_suppress_updates_after_clock_rollback() {
    let root = tempfile::tempdir().unwrap();
    let cache = fixture(root.path());
    remember_attempt(root.path(), timestamp() + 10_000).unwrap();
    let updater = ProviderUpdates::default();
    updater
        .start_with_fetch(
            cache,
            ProviderConfig::bundled(),
            root.path().to_owned(),
            Arc::new(|_| Ok(SIGNED.to_vec())),
            POLL,
            RETRY,
        )
        .unwrap();
    wait_for(&updater, State::PendingRestart);
    updater.shutdown();
}

#[test]
fn cancellation_before_atomic_publication_preserves_existing_configuration() {
    let root = tempfile::tempdir().unwrap();
    let cache = fixture(root.path());
    assert!(
        publish(&cache, &ProviderConfig::bundled(), SIGNED, &|| Err(
            "cancelled".into()
        ))
        .is_err()
    );
    assert!(!root.path().join(".provider_config.json").exists());
}

#[test]
fn checking_the_same_download_keeps_pending_restart_until_activation() {
    let root = tempfile::tempdir().unwrap();
    let cache = fixture(root.path());
    let active = ProviderConfig::bundled();
    assert_eq!(
        publish(&cache, &active, SIGNED, &|| Ok(())).unwrap(),
        (State::PendingRestart, 2)
    );
    assert_eq!(
        publish(&cache, &active, SIGNED, &|| Ok(())).unwrap(),
        (State::PendingRestart, 2),
        "persisted settings are still pending while this backend uses revision 1"
    );
    let restarted = cache.lock().unwrap().load().config;
    assert_eq!(
        publish(&cache, &restarted, SIGNED, &|| Ok(())).unwrap(),
        (State::UpToDate, 2)
    );
}
