use base64::{Engine, engine::general_purpose::STANDARD};
use ring::signature::{Ed25519KeyPair, KeyPair};
use serde_json::{Value, json};
use std::path::Path;
use std::process::Command;

fn cli(arguments: &[&str]) -> std::process::Output {
    Command::new(env!("CARGO_BIN_EXE_provider-config"))
        .args(arguments)
        .output()
        .unwrap()
}

#[test]
fn operator_tool_validates_signs_verifies_and_refuses_overwrite_or_tampering() {
    let root = tempfile::tempdir().unwrap();
    let config = root.path().join("config.json");
    let private = root.path().join("private.pk8");
    let trust = root.path().join("trust.json");
    let output = root.path().join("signed.json");
    let mut value: Value = serde_json::from_slice(include_bytes!(
        "../../../../extensions/config/providers.json"
    ))
    .unwrap();
    value["revision"] = json!(2);
    std::fs::write(&config, serde_json::to_vec(&value).unwrap()).unwrap();
    let key = Ed25519KeyPair::generate_pkcs8(&ring::rand::SystemRandom::new()).unwrap();
    let pair = Ed25519KeyPair::from_pkcs8(key.as_ref()).unwrap();
    std::fs::write(&private, key.as_ref()).unwrap();
    std::fs::write(
        &trust,
        serde_json::to_vec(&json!({"test": STANDARD.encode(pair.public_key().as_ref())})).unwrap(),
    )
    .unwrap();
    let text = |path: &Path| path.to_str().unwrap().to_owned();
    assert!(cli(&["validate", &text(&config)]).status.success());
    assert!(
        cli(&[
            "sign",
            &text(&config),
            "test",
            &text(&private),
            &text(&output)
        ])
        .status
        .success()
    );
    assert!(
        cli(&["verify", &text(&output), &text(&trust)])
            .status
            .success()
    );
    let original = std::fs::read(&output).unwrap();
    assert!(
        !cli(&[
            "sign",
            &text(&config),
            "test",
            &text(&private),
            &text(&output)
        ])
        .status
        .success()
    );
    assert_eq!(std::fs::read(&output).unwrap(), original);
    let mut modified: Value = serde_json::from_slice(&original).unwrap();
    modified["payload"] = STANDARD.encode(b"{}").into();
    std::fs::write(&output, serde_json::to_vec(&modified).unwrap()).unwrap();
    assert!(
        !cli(&["verify", &text(&output), &text(&trust)])
            .status
            .success()
    );
    assert!(!cli(&["validate", &text(&output)]).status.success());
}
