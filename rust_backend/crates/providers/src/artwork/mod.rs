//! Native artwork codecs adapted from the pinned Mornye-Extension sources.
//! Network/authentication and app activation are separate from parsing; these
//! functions never evaluate JavaScript or modify local library identities.
mod apple;
mod client;
pub use client::ArtworkClient;
mod deezer;

use serde::{Deserialize, Serialize};
use serde_json::{Map, Value};

#[derive(Clone, Copy, Debug, Deserialize, Eq, PartialEq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Artist,
    Album,
}

#[derive(Debug, thiserror::Error)]
pub enum ArtworkError {
    #[error("native artwork provider or operation is unsupported")]
    Unsupported,
    #[error("artwork request cancelled: {0}")]
    Cancelled(String),
    #[error("artwork lookup timed out")]
    Timeout,
    #[error("artwork authentication failed")]
    Authentication,
    #[error("artwork HTTP request failed: {0}")]
    Network(String),
    #[error("artwork resource was not found")]
    NotFound,
    #[error("invalid artwork response: {0}")]
    Invalid(&'static str),
}

#[derive(Debug, Serialize)]
pub struct ArtworkDocument {
    pub provider_id: String,
    pub resource_id: String,
    pub kind: Kind,
    pub artwork: Value,
    /// Additional editorial fields, never a replacement for local track data.
    pub metadata: Map<String, Value>,
}

pub fn parse(
    provider: &str,
    kind: Kind,
    resource_id: &str,
    response: &Value,
) -> Result<ArtworkDocument, ArtworkError> {
    if resource_id.is_empty() || resource_id.len() > 256 {
        return Err(ArtworkError::Invalid("resource identity"));
    }
    let (artwork, metadata) = match provider {
        "apple-music" => apple::parse(kind, resource_id, response)?,
        "deezer" if kind == Kind::Artist => deezer::parse(resource_id, response)?,
        _ => return Err(ArtworkError::Unsupported),
    };
    Ok(ArtworkDocument {
        provider_id: provider.into(),
        resource_id: resource_id.into(),
        kind,
        artwork,
        metadata,
    })
}

fn text(value: &Value) -> &str {
    value.as_str().unwrap_or("")
}

fn number(value: &Value) -> f64 {
    value
        .as_f64()
        .or_else(|| value.as_str()?.trim().parse().ok())
        .or_else(|| value.as_bool().map(|value| if value { 1.0 } else { 0.0 }))
        .filter(|n| n.is_finite())
        .unwrap_or(0.0)
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn pinned_javascript_artwork_and_editorial_fixtures_match() {
        let fixtures: Value = serde_json::from_str(include_str!(
            "../../../../../extensions/artwork/fixtures/apple-deezer.json"
        ))
        .unwrap();
        let cases = fixtures["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 20);
        for case in cases {
            let result = parse(
                case["provider"].as_str().unwrap(),
                serde_json::from_value(case["kind"].clone()).unwrap(),
                case["id"].as_str().unwrap(),
                &case["response"],
            )
            .unwrap_or_else(|error| panic!("{}: {error}", case["name"]));
            assert_eq!(result.artwork, case["expected"], "{}", case["name"]);
            if let Some(expected) = case["expected_metadata"].as_object() {
                for (key, value) in expected {
                    assert_eq!(
                        result.metadata.get(key),
                        Some(value),
                        "{}: {key}",
                        case["name"]
                    );
                }
            }
        }
    }

    #[test]
    fn missing_and_wrong_identity_are_not_successful_artwork() {
        assert!(matches!(
            parse("apple-music", Kind::Artist, "42", &json!({"data":[]})),
            Err(ArtworkError::NotFound)
        ));
        assert!(matches!(
            parse(
                "apple-music",
                Kind::Artist,
                "42",
                &json!({"data":[{"id":"43","attributes":{}}]})
            ),
            Err(ArtworkError::Invalid(_))
        ));
        assert!(matches!(
            parse(
                "deezer",
                Kind::Artist,
                "42",
                &json!({"error":{"code":800,"message":"missing"}})
            ),
            Err(ArtworkError::NotFound)
        ));
        assert!(matches!(
            parse(
                "deezer",
                Kind::Artist,
                "42",
                &json!({"id":43,"name":"Other"})
            ),
            Err(ArtworkError::Invalid(_))
        ));
    }

    #[test]
    fn malformed_catalog_envelopes_are_not_resource_misses() {
        for response in [
            json!({}),
            json!({"data": {}}),
            json!({"data": null}),
            json!({"data": "bad"}),
            json!({"data": [null]}),
        ] {
            assert!(
                matches!(
                    parse("apple-music", Kind::Artist, "42", &response),
                    Err(ArtworkError::Invalid(_))
                ),
                "{response}"
            );
        }
        assert!(matches!(
            parse("apple-music", Kind::Artist, "42", &json!({"data": []})),
            Err(ArtworkError::NotFound)
        ));
    }

    #[test]
    fn unsupported_source_does_not_claim_to_have_a_native_port() {
        assert!(matches!(
            parse("jellyfin", Kind::Artist, "42", &json!({})),
            Err(ArtworkError::Unsupported)
        ));
        assert!(matches!(
            parse("deezer", Kind::Album, "42", &json!({})),
            Err(ArtworkError::Unsupported)
        ));
    }
}
