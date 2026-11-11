// SPDX-License-Identifier: LGPL-3.0-only
// Adapted from Mornye-Extension 12530ceda46dc78a10f9258b7d65a71452dfcf50,
// sources/deezer/index.js: formatArtist, coverFromArtist, highestQualityDeezerCoverURL.
use super::{ArtworkError, text};
use regex::Regex;
use serde_json::{Map, Value, json};
use std::sync::LazyLock;
static SIZE: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"/(\d+)x(\d+)-(\d+)-(\d+)-(\d+)-(\d+)\.jpg([?#]|$)").unwrap());
pub(super) fn parse(
    id: &str,
    response: &Value,
) -> Result<(Value, Map<String, Value>), ArtworkError> {
    if !response["error"].is_null() {
        return Err(match response["error"]["code"].as_u64() {
            Some(800) => ArtworkError::NotFound,
            Some(200 | 300) => ArtworkError::Authentication,
            Some(code) => ArtworkError::Network(format!("Deezer service error {code}")),
            None => ArtworkError::Invalid("Deezer service error envelope"),
        });
    }
    if response["id"].is_null() {
        return Err(ArtworkError::Invalid("artist identity"));
    }
    let actual = match &response["id"] {
        Value::String(v) => v.clone(),
        Value::Number(v) => v.to_string(),
        _ => return Err(ArtworkError::Invalid("artist identity")),
    };
    let raw = id.strip_prefix("deezer:").unwrap_or(id);
    if actual != raw {
        return Err(ArtworkError::Invalid("artist identity mismatch"));
    }
    let mut image = [
        "picture_xl",
        "picture_big",
        "picture_medium",
        "picture",
        "cover_xl",
        "cover_big",
        "cover_medium",
        "cover",
    ]
    .iter()
    .map(|key| text(&response[key]).trim())
    .find(|value| !value.is_empty())
    .unwrap_or("")
    .to_owned();
    if image.contains(".dzcdn.net/")
        && let Some(caps) = SIZE.captures(&image)
    {
        let width = caps[1].parse::<u64>().unwrap_or_default();
        let height = caps[2].parse::<u64>().unwrap_or_default();
        if width < 1400 || height < 1400 {
            let replacement = format!(
                "/1400x1400-{}-{}-{}-{}.jpg{}",
                &caps[3], &caps[4], &caps[5], &caps[6], &caps[7]
            );
            let m = caps.get(0).unwrap();
            image.replace_range(m.range(), &replacement);
        }
    }
    Ok((
        json!({"id":format!("deezer:{actual}"),"name":text(&response["name"]),"image_url":image,"images":image,"header_image":image}),
        Map::new(),
    ))
}
