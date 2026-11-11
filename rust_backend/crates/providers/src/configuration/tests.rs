use super::*;
use ring::signature::{Ed25519KeyPair, KeyPair};
use serde_json::{Value, json};

fn fixture() -> (Ed25519KeyPair, TrustedKeys) {
    // Test-only deterministic key. This key is never bundled by the application.
    let pair = Ed25519KeyPair::from_seed_unchecked(&[77; 32]).unwrap();
    let keys = TrustedKeys::parse(
        &serde_json::to_vec(&json!({"test": STANDARD.encode(pair.public_key().as_ref())})).unwrap(),
    )
    .unwrap();
    (pair, keys)
}

fn document(revision: u64) -> Value {
    let mut value: Value = serde_json::from_slice(DEFAULTS).unwrap();
    value["revision"] = revision.into();
    value
}

fn sign(pair: &Ed25519KeyPair, payload: &[u8]) -> Vec<u8> {
    let mut message = b"mornye-provider-config-v1\0".to_vec();
    message.extend_from_slice(payload);
    serde_json::to_vec(&json!({
        "format": 1, "key_id": "test", "payload": STANDARD.encode(payload),
        "signature": STANDARD.encode(pair.sign(&message).as_ref()),
    }))
    .unwrap()
}

#[test]
fn bundled_settings_preserve_all_native_request_origins() {
    let bundled = ProviderConfig::bundled();
    assert_eq!(bundled.revision(), 1);
    assert_eq!(bundled.lyrics_cache_name(), ".lyrics_cache.json");
    assert_eq!(bundled.lyrics_endpoints().len(), 12);
    assert!(bundled.lyrics_endpoints().iter().all(|(a, b)| a == b));
    assert!(
        !TrustedKeys::bundled().is_empty(),
        "release signer must be provisioned"
    );
    assert!(
        TrustedKeys::bundled()
            .verify(include_bytes!(
                "../../../../../extensions/config/tests/signed-test-config.json"
            ))
            .is_err(),
        "fixture signer must never be trusted by production"
    );
}

#[test]
fn malformed_unknown_duplicate_oversized_and_incompatible_documents_are_rejected() {
    for bytes in [
        b"null".to_vec(),
        vec![b' '; MAX_CONFIG_BYTES + 1],
        b"{}".to_vec(),
    ] {
        assert!(ProviderConfig::parse(&bytes).is_err());
    }
    for (key, value) in [
        ("schema_version", json!(2)),
        ("runtime_version", json!(2)),
        ("revision", json!(0)),
        ("javascript", json!("run()")),
    ] {
        let mut doc = document(1);
        doc[key] = value;
        assert!(ProviderConfig::parse(&serde_json::to_vec(&doc).unwrap()).is_err());
    }
    let text = String::from_utf8(DEFAULTS.to_vec()).unwrap();
    let duplicate = text.replacen("\"revision\": 1", "\"revision\": 1, \"revision\": 2", 1);
    assert!(ProviderConfig::parse(duplicate.as_bytes()).is_err());
    let duplicate_origin = text.replacen("\"https://lrclib.net\": \"https://lrclib.net\"", "\"https://lrclib.net\": \"https://lrclib.net\", \"https://lrclib.net\": \"https://lyrics.paxsenix.org\"",1);
    assert!(ProviderConfig::parse(duplicate_origin.as_bytes()).is_err());
    let mut doc = document(1);
    doc["lyrics_origins"]
        .as_object_mut()
        .unwrap()
        .remove("https://lrclib.net");
    assert!(ProviderConfig::parse(&serde_json::to_vec(&doc).unwrap()).is_err());
}

#[test]
fn settings_cannot_add_hosts_credentials_ports_paths_or_query_parameters() {
    for target in [
        "http://lrclib.net",
        "https://127.0.0.1",
        "https://localhost",
        "https://example.org",
        "https://user:pass@lrclib.net",
        "https://lrclib.net:8443",
        "https://lrclib.net/api",
        "https://lrclib.net?token=x",
        "https://lrclib.net#x",
        "https://lrclib.net/",
    ] {
        let mut doc = document(2);
        doc["lyrics_origins"]["https://lrclib.net"] = target.into();
        assert!(
            ProviderConfig::parse(&serde_json::to_vec(&doc).unwrap()).is_err(),
            "{target}"
        );
    }
}

#[test]
fn origin_substitution_cannot_forward_service_credentials_to_another_provider() {
    let mut doc = document(2);
    doc["lyrics_origins"]["https://amp-api.music.apple.com"] = "https://genius.com".into();
    assert!(ProviderConfig::parse(&serde_json::to_vec(&doc).unwrap()).is_err());
    doc = document(2);
    doc["lyrics_origins"]["https://lyricsplus.prjktla.my.id"] =
        "https://lyricsplus.binimum.org".into();
    let config = ProviderConfig::parse(&serde_json::to_vec(&doc).unwrap()).unwrap();
    assert_eq!(
        config.lyrics_endpoints()["https://lyricsplus.prjktla.my.id"],
        "https://lyricsplus.binimum.org"
    );
}

#[test]
fn only_a_trusted_signature_over_exact_domain_separated_payload_authorizes_settings() {
    let (pair, keys) = fixture();
    let bytes = serde_json::to_vec(&document(2)).unwrap();
    let signed = sign(&pair, &bytes);
    assert_eq!(keys.verify(&signed).unwrap().revision(), 2);
    assert!(TrustedKeys::default().verify(&signed).is_err());
    for key in ["payload", "signature", "key_id"] {
        let mut modified: Value = serde_json::from_slice(&signed).unwrap();
        modified[key] = "modified".into();
        assert!(
            keys.verify(&serde_json::to_vec(&modified).unwrap())
                .is_err()
        );
    }
    let other = Ed25519KeyPair::from_seed_unchecked(&[78; 32]).unwrap();
    assert!(keys.verify(&sign(&other, &bytes)).is_err());
    let mut raw: Value = serde_json::from_slice(&signed).unwrap();
    raw["signature"] = STANDARD.encode(pair.sign(&bytes).as_ref()).into();
    assert!(keys.verify(&serde_json::to_vec(&raw).unwrap()).is_err());
    assert!(
        keys.verify(&sign(&pair, &vec![b' '; MAX_CONFIG_BYTES + 1]))
            .is_err()
    );
}

#[test]
fn install_survives_restart_without_mutating_live_generation_and_rejects_downgrades() {
    let root = tempfile::tempdir().unwrap();
    let (pair, keys) = fixture();
    let cache = ConfigCache::new(root.path(), keys.clone());
    let live = cache.load().config;
    assert_eq!(live.revision(), 1);
    assert!(cache.load().fallback_reason.is_none());
    let signed = sign(&pair, &serde_json::to_vec(&document(2)).unwrap());
    let installed = cache.install(&signed).unwrap();
    assert_eq!(live.revision(), 1);
    assert_eq!(installed.revision(), 2);
    let restarted = ConfigCache::new(root.path(), keys);
    let loaded = restarted.load();
    assert!(loaded.fallback_reason.is_none());
    assert_eq!(loaded.config.revision(), 2);
    assert_eq!(
        loaded.config.lyrics_cache_name(),
        ".lyrics_cache.config-2.json"
    );
    assert!(matches!(cache.install(&signed), Err(ConfigError::Revision)));
    assert!(cache.install(b"not signed").is_err());
    assert_eq!(fs::read(&cache.path).unwrap(), signed);
}

#[test]
fn invalid_cache_falls_back_explicitly_and_failed_write_cannot_replace_previous_file() {
    let root = tempfile::tempdir().unwrap();
    let (pair, keys) = fixture();
    let cache = ConfigCache::new(root.path(), keys.clone());
    fs::write(&cache.path, b"corrupt").unwrap();
    let loaded = cache.load();
    assert_eq!(loaded.config.revision(), 1);
    assert!(loaded.fallback_reason.is_some());
    let missing = ConfigCache::new(&root.path().join("missing"), keys);
    assert!(
        missing
            .install(&sign(&pair, &serde_json::to_vec(&document(2)).unwrap()))
            .is_err()
    );
    assert_eq!(fs::read(&cache.path).unwrap(), b"corrupt");
}

#[test]
fn trust_maps_reject_duplicate_keys_and_trailing_documents() {
    let (_, keys) = fixture();
    let public = STANDARD.encode(keys.0["test"].as_slice());
    let duplicate = format!("{{\"test\":\"{public}\",\"test\":\"{public}\"}}");
    assert!(TrustedKeys::parse(duplicate.as_bytes()).is_err());
    assert!(TrustedKeys::parse(b"{} {}").is_err());
    assert!(TrustedKeys::parse(b"{\"bad\":\"AA==\"}").is_err());
}
