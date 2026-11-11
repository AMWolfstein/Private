use super::*;
use serde_json::{Value, json};

const KEYS: &[u8] = include_bytes!("../../../../../extensions/config/tests/trusted-test-key.json");
const SIGNED: &[u8] =
    include_bytes!("../../../../../extensions/config/tests/signed-test-config.json");
const MASTER: &str = "AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";

fn backend(root: &Path) -> Backend {
    let environment = ExtensionEnvironment::new(&root.join("data"), MASTER, "1").unwrap();
    Backend::with_environment_and_lyrics(
        &root.join("sources"),
        environment,
        RuntimeLimits::default(),
        MetadataOptions::default(),
        &[],
        FetchOptions::default(),
        TrustedKeys::parse(KEYS).unwrap(),
    )
    .unwrap()
}

#[test]
fn signed_installation_is_pending_until_restart_and_does_not_mutate_the_old_owner() {
    let root = tempfile::tempdir().unwrap();
    let first = backend(root.path());
    assert_eq!(first.provider_config.revision(), 1);
    assert_eq!(first.install_provider_configuration(SIGNED).unwrap(), 2);
    assert_eq!(first.provider_config.revision(), 1);
    assert_eq!(
        first.provider_config.lyrics_cache_name(),
        ".lyrics_cache.json"
    );
    assert!(matches!(
        first.install_provider_configuration(SIGNED),
        Err(ConfigError::Revision)
    ));
    first.shutdown_checked().unwrap();
    assert!(matches!(
        first.install_provider_configuration(SIGNED),
        Err(ConfigError::BackendUnavailable(_))
    ));
    drop(first);
    let restarted = backend(root.path());
    assert_eq!(restarted.provider_config.revision(), 2);
    assert_eq!(
        restarted.provider_config.lyrics_cache_name(),
        ".lyrics_cache.config-2.json"
    );
    assert!(restarted.provider_config_fallback.is_none());
    let status: Value =
        serde_json::from_str(&restarted.provider_configuration_status_json().unwrap()).unwrap();
    assert_eq!(status["active_revision"], json!(2));
    assert_eq!(status["automatic_updates_enabled"], json!(false));
    assert_eq!(status["update"]["state"], "not_started");
    std::fs::write(root.path().join("data/.provider_config.json"), b"corrupt").unwrap();
    assert!(matches!(
        restarted.install_provider_configuration(SIGNED),
        Err(ConfigError::Revision)
    ));
    restarted.shutdown_checked().unwrap();
}

#[test]
fn corrupt_cache_is_reported_while_native_lyrics_defaults_survive() {
    let root = tempfile::tempdir().unwrap();
    std::fs::create_dir_all(root.path().join("data")).unwrap();
    std::fs::write(root.path().join("data/.provider_config.json"), b"corrupt").unwrap();
    let backend = backend(root.path());
    assert_eq!(backend.provider_config, ProviderConfig::bundled());
    assert!(backend.provider_config_fallback.is_some());
    let status: Value =
        serde_json::from_str(&backend.provider_configuration_status_json().unwrap()).unwrap();
    assert!(
        status["fallback_reason"]
            .as_str()
            .unwrap()
            .contains("invalid")
    );
    assert!(backend.install_provider_configuration(b"invalid").is_err());
    assert_eq!(
        std::fs::read(root.path().join("data/.provider_config.json")).unwrap(),
        b"corrupt"
    );
    backend.shutdown_checked().unwrap();
}

#[test]
fn production_defaults_do_not_trust_the_fixture_signer() {
    let root = tempfile::tempdir().unwrap();
    let backend = Backend::new(
        &root.path().join("sources"),
        &root.path().join("data"),
        MASTER,
        "1",
        RuntimeLimits::default(),
    )
    .unwrap();
    assert!(matches!(
        backend.install_provider_configuration(SIGNED),
        Err(ConfigError::Authentication(_))
    ));
    assert!(!root.path().join("data/.provider_config.json").exists());
    backend.shutdown_checked().unwrap();
}
