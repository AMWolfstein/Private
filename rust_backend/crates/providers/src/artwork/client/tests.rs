use super::*;
use serde_json::json;
use std::sync::{
    Mutex,
    atomic::{AtomicUsize, Ordering},
};

struct Step {
    url: String,
    bearer: Option<String>,
    status: u16,
    body: Vec<u8>,
}
struct Script(Mutex<std::collections::VecDeque<Step>>);
impl Transport for Script {
    fn get(
        &self,
        role: Role,
        url: &str,
        headers: BTreeMap<String, String>,
        remaining: Duration,
        check: &Check<'_>,
    ) -> Result<Response, ArtworkError> {
        check().map_err(ArtworkError::Cancelled)?;
        assert!(remaining > Duration::ZERO && remaining <= DEADLINE);
        let next = self
            .0
            .lock()
            .unwrap()
            .pop_front()
            .expect("unexpected request");
        assert_eq!(url, next.url);
        assert_eq!(headers.get("Authorization").cloned(), next.bearer);
        match role {
            Role::AppleCatalog => {
                assert_eq!(headers.get("Origin").unwrap(), "https://music.apple.com");
                assert!(url.starts_with("https://amp-api.music.apple.com/"));
            }
            Role::AppleWeb => assert!(url.starts_with("https://music.apple.com/")),
            Role::Deezer => assert!(url.starts_with("https://api.deezer.com/")),
        }
        Ok(Response {
            status: next.status,
            body: next.body,
        })
    }
}
fn script(steps: Vec<Step>) -> (ArtworkClient, Arc<Script>) {
    let transport = Arc::new(Script(Mutex::new(steps.into())));
    (
        ArtworkClient {
            transport: transport.clone(),
        },
        transport,
    )
}
fn step(url: &str, body: &str) -> Step {
    Step {
        url: url.into(),
        bearer: None,
        status: 200,
        body: body.as_bytes().to_vec(),
    }
}
fn fixture(provider: &str, kind: &str) -> String {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../../../../extensions/artwork/fixtures/apple-deezer.json"
    ))
    .unwrap();
    fixtures["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["provider"] == provider && case["kind"] == kind)
        .unwrap()["response"]
        .to_string()
}
fn fixture_id(provider: &str, kind: &str) -> String {
    let fixtures: Value = serde_json::from_str(include_str!(
        "../../../../../../extensions/artwork/fixtures/apple-deezer.json"
    ))
    .unwrap();
    fixtures["cases"]
        .as_array()
        .unwrap()
        .iter()
        .find(|case| case["provider"] == provider && case["kind"] == kind)
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .into()
}
#[test]
fn deezer_fetches_only_artist_and_preserves_reference_artwork() {
    let id = fixture_id("deezer", "artist");
    let raw_id = id.strip_prefix("deezer:").unwrap_or(&id);
    let (client, script) = script(vec![step(
        &format!("https://api.deezer.com/artist/{raw_id}"),
        &fixture("deezer", "artist"),
    )]);
    let output = client
        .lookup("deezer", Kind::Artist, &id, &|| Ok(()))
        .unwrap();
    assert_eq!(
        output.artwork,
        parse(
            "deezer",
            Kind::Artist,
            raw_id,
            &serde_json::from_str(&fixture("deezer", "artist")).unwrap()
        )
        .unwrap()
        .artwork
    );
    assert!(script.0.lock().unwrap().is_empty());
}
#[test]
fn apple_refreshes_401_once_and_does_not_fetch_catalog_tracks() {
    let id = fixture_id("apple-music", "album");
    let url = format!(
        "https://amp-api.music.apple.com/v1/catalog/us/albums/{id}?extend=artistUrl,editorialArtwork,editorialVideo"
    );
    let mut unauthorized = step(&url, "");
    unauthorized.status = 401;
    unauthorized.bearer = Some("Bearer a.b.c".into());
    let mut success = step(&url, &fixture("apple-music", "album"));
    success.bearer = Some("Bearer d.e.f".into());
    let (client, script) = script(vec![
        step(
            "https://music.apple.com/us/browse",
            "<iframe src=\"x?devToken=a.b.c\">",
        ),
        unauthorized,
        step("https://music.apple.com/us/browse", "devToken=d.e.f"),
        success,
    ]);
    let output = client
        .lookup("apple-music", Kind::Album, &id, &|| Ok(()))
        .unwrap();
    assert_eq!(output.kind, Kind::Album);
    assert!(script.0.lock().unwrap().is_empty());
}
#[test]
fn apple_discovers_index_bundle_with_known_jwt_header() {
    let token = "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IldlYlBsYXlLaWQifQ.payload.signature";
    let (client, script) = script(vec![
        step(
            "https://music.apple.com/us/browse",
            r#"<script src="/assets/other.js"></script><script src="/assets/index-legacy.js"></script><script src="/assets/index-main.js"></script>"#,
        ),
        step(
            "https://music.apple.com/assets/index-main.js",
            &format!("const token='{token}';"),
        ),
    ]);
    assert_eq!(
        client.apple_token(Instant::now(), &|| Ok(())).unwrap(),
        token
    );
    assert!(script.0.lock().unwrap().is_empty());
}
#[test]
fn malformed_ids_and_unsupported_operations_never_make_http_calls() {
    let (client, _) = script(vec![]);
    for id in ["", "../42", "42?token=secret", "deezer:12/3"] {
        assert!(matches!(
            client.lookup("deezer", Kind::Artist, id, &|| Ok(())),
            Err(ArtworkError::Invalid(_))
        ));
    }
    assert!(matches!(
        client.lookup("jellyfin", Kind::Artist, "42", &|| Ok(())),
        Err(ArtworkError::Unsupported)
    ));
    assert!(matches!(
        client.lookup("deezer", Kind::Album, "42", &|| Ok(())),
        Err(ArtworkError::Unsupported)
    ));
}
#[test]
fn not_found_invalid_json_and_oversize_stay_distinct() {
    for (status, body, expected) in [
        (404, Vec::new(), "missing"),
        (200, b"not json".to_vec(), "invalid"),
        (200, vec![b' '; LIMIT + 1], "invalid"),
        (403, Vec::new(), "auth"),
    ] {
        let mut next = step("https://api.deezer.com/artist/42", "");
        next.status = status;
        next.body = body;
        let (client, _) = script(vec![next]);
        let result = client.lookup("deezer", Kind::Artist, "42", &|| Ok(()));
        match expected {
            "missing" => assert!(matches!(result, Err(ArtworkError::NotFound))),
            "auth" => assert!(matches!(result, Err(ArtworkError::Authentication))),
            _ => assert!(matches!(result, Err(ArtworkError::Invalid(_)))),
        }
    }
}
#[test]
fn cancellation_after_response_prevents_publication() {
    let (client, _) = script(vec![step(
        "https://api.deezer.com/artist/42",
        &json!({"id":42,"name":"Artist"}).to_string(),
    )]);
    let calls = AtomicUsize::new(0);
    let result = client.lookup("deezer", Kind::Artist, "42", &|| {
        if calls.fetch_add(1, Ordering::SeqCst) < 2 {
            Ok(())
        } else {
            Err("closed".into())
        }
    });
    assert!(matches!(result, Err(ArtworkError::Cancelled(_))));
}
#[test]
fn cancellation_and_expired_budget_do_not_dispatch() {
    let (client, _) = script(vec![]);
    assert!(matches!(
        client.lookup("deezer", Kind::Artist, "42", &|| Err("closed".into())),
        Err(ArtworkError::Cancelled(_))
    ));
    assert!(matches!(
        client.get(
            Role::Deezer,
            "https://api.deezer.com/artist/42",
            BTreeMap::new(),
            Instant::now() - DEADLINE,
            &|| Ok(())
        ),
        Err(ArtworkError::Timeout)
    ));
}

#[test]
fn deezer_service_failures_are_not_resource_misses() {
    for (body, expected) in [
        (
            json!({"error":{"code":4,"message":"Quota limit exceeded"}}),
            "network",
        ),
        (
            json!({"error":{"code":300,"message":"Invalid OAuth token"}}),
            "auth",
        ),
        (json!({"error":{"code":800,"message":"no data"}}), "missing"),
        (json!({}), "invalid"),
        (
            json!({"error":{"message":"unknown service failure"}}),
            "invalid",
        ),
    ] {
        let (client, _) = script(vec![step(
            "https://api.deezer.com/artist/42",
            &body.to_string(),
        )]);
        let result = client.lookup("deezer", Kind::Artist, "42", &|| Ok(()));
        match expected {
            "network" => assert!(matches!(result, Err(ArtworkError::Network(_)))),
            "auth" => assert!(matches!(result, Err(ArtworkError::Authentication))),
            "missing" => assert!(matches!(result, Err(ArtworkError::NotFound))),
            _ => assert!(matches!(result, Err(ArtworkError::Invalid(_)))),
        }
    }
}
