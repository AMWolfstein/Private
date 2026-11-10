//! Operator tool. Private signing keys are never application assets.
use base64::{Engine, engine::general_purpose::STANDARD};
use mornye_providers::configuration::{ProviderConfig, SIGNING_CONTEXT, TrustedKeys};
use ring::signature::{Ed25519KeyPair, KeyPair};
use serde_json::json;
use std::fs;
use std::io::Write;

fn run(args: &[String]) -> Result<(), Box<dyn std::error::Error>> {
    match args.get(1).map(String::as_str) {
        Some("validate") if args.len() == 3 => {
            let config = ProviderConfig::parse(&fs::read(&args[2])?)?;
            println!("Valid configuration revision {}", config.revision());
        }
        Some("verify") if args.len() == 4 => {
            let keys = TrustedKeys::parse(&fs::read(&args[3])?)?;
            let config = keys.verify(&fs::read(&args[2])?)?;
            println!("Authenticated configuration revision {}", config.revision());
        }
        Some("sign") if args.len() == 6 => {
            let payload = fs::read(&args[2])?;
            ProviderConfig::parse(&payload)?;
            let pair = Ed25519KeyPair::from_pkcs8_maybe_unchecked(&fs::read(&args[4])?)
                .map_err(|_| "invalid Ed25519 PKCS#8 private key")?;
            // Validate the ID/public-key pair using the same trust-map parser.
            TrustedKeys::parse(&serde_json::to_vec(&json!({
                &args[3]: STANDARD.encode(pair.public_key().as_ref()),
            }))?)?;
            let mut message = SIGNING_CONTEXT.to_vec();
            message.extend_from_slice(&payload);
            let envelope = serde_json::to_vec_pretty(&json!({
                "format": 1, "key_id": args[3], "payload": STANDARD.encode(&payload),
                "signature": STANDARD.encode(pair.sign(&message).as_ref()),
            }))?;
            // Never clobber another release artifact by accident.
            fs::OpenOptions::new().write(true).create_new(true)
                .open(&args[5])?.write_all(&envelope)?;
            println!("Signed provider configuration: {}", args[5]);
        }
        _ => return Err("usage: provider-config validate CONFIG | verify ENVELOPE TRUSTED_KEYS | sign CONFIG KEY_ID PRIVATE_PKCS8 OUTPUT (generate and protect an Ed25519 key outside this repository)".into()),
    }
    Ok(())
}

fn main() {
    if let Err(error) = run(&std::env::args().collect::<Vec<_>>()) {
        eprintln!("{error}");
        std::process::exit(1);
    }
}
