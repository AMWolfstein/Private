// SPDX-License-Identifier: LGPL-3.0-only
// Adapted from Mornye-Extension 12530ceda46dc78a10f9258b7d65a71452dfcf50,
// sources/apple-music/index.js: artworkURL, artistHeaderArtwork,
// artistNameArtworkURL, motionArtwork* and formatAlbumInfo.
use super::{ArtworkError, Kind, number, text};
use serde_json::{Map, Value, json};

const MOTION_KEYS: &[&str] = &[
    "motionDetailTall",
    "motionTallVideo3x4",
    "motionArtworkTall3x4",
    "motionArtistSquare1x1",
    "motionDetailSquare",
    "motionSquareVideo1x1",
    "motionArtworkSquare1x1",
    "motionArtistFullscreen16x9",
    "motionArtistWide16x9",
    "motionArtworkWide16x9",
    "motionDetailWide",
];
fn rendition(url: &str, width: f64, height: f64) -> String {
    url.replacen("{w}", &format!("{:.0}", width.round()), 1)
        .replacen("{h}", &format!("{:.0}", height.round()), 1)
}
fn artwork(value: &Value) -> String {
    let url = text(&value["url"]);
    if url.is_empty() {
        return String::new();
    }
    let size = number(&value["width"])
        .max(number(&value["height"]))
        .clamp(3000.0, 6000.0);
    rendition(url, size, size)
}
fn tall(key: &str) -> bool {
    key.contains("Tall") || key.contains("3x4")
}
fn video(value: &Value, allow_non_tall: bool) -> String {
    MOTION_KEYS
        .iter()
        .filter(|key| allow_non_tall || tall(key))
        .map(|key| text(&value[key]["video"]))
        .find(|url| !url.is_empty())
        .unwrap_or("")
        .into()
}
fn dimension(frame: &Value, key: &str, alias: &str) -> f64 {
    let primary = &frame[key];
    let absent = match primary {
        Value::Null | Value::Bool(false) => true,
        Value::Number(value) => value.as_f64() == Some(0.0),
        Value::String(value) => value.is_empty(),
        _ => false,
    };
    number(if absent { &frame[alias] } else { primary })
}
fn preview(value: &Value) -> String {
    for key in MOTION_KEYS {
        let frame = &value[key]["previewFrame"];
        let url = text(&frame["url"]);
        if url.is_empty() {
            continue;
        }
        let width = dimension(frame, "width", "w");
        let height = dimension(frame, "height", "h");
        let output_height = if width > 0.0 && height > 0.0 {
            1080.0 * height / width
        } else if tall(key) {
            1440.0
        } else if key.contains("Wide") || key.contains("Fullscreen") || key.contains("16x9") {
            607.5
        } else {
            1080.0
        };
        if output_height.is_finite() {
            return rendition(url, 1080.0, output_height);
        }
    }
    String::new()
}
fn logo(attributes: &Value) -> String {
    let value = &attributes["editorialArtwork"]["musicContentColorLogoTrimmed"];
    let (width, height) = (number(&value["width"]), number(&value["height"]));
    if width <= 0.0 || height <= 0.0 {
        return String::new();
    }
    let output_width = width.min(1200.0);
    let output_height = (output_width * height / width).round().max(1.0);
    if !output_height.is_finite() {
        return String::new();
    }
    let url = rendition(text(&value["url"]), output_width, output_height);
    let end = url.find('?').unwrap_or(url.len());
    if url[..end].ends_with(".jpg") {
        format!("{}.png{}", &url[..end - 4], &url[end..])
    } else {
        url
    }
}
fn genres(value: &Value) -> String {
    let mut output = Vec::new();
    let mut seen = std::collections::BTreeSet::new();
    for value in value.as_array().into_iter().flatten() {
        let name = text(value).trim();
        let key = name.to_lowercase();
        if !name.is_empty() && key != "music" && seen.insert(key) {
            output.push(name);
        }
    }
    output.join("; ")
}
pub(super) fn parse(
    kind: Kind,
    id: &str,
    response: &Value,
) -> Result<(Value, Map<String, Value>), ArtworkError> {
    let items = response["data"]
        .as_array()
        .ok_or(ArtworkError::Invalid("catalog data"))?;
    let resource = items.first().ok_or(ArtworkError::NotFound)?;
    if text(&resource["id"]) != id {
        return Err(ArtworkError::Invalid("catalog identity mismatch"));
    }
    let attr = &resource["attributes"];
    if !attr.is_object() {
        return Err(ArtworkError::Invalid("catalog attributes"));
    }
    let cover = artwork(&attr["artwork"]);
    let motion = &attr["editorialVideo"];
    let mut metadata = Map::new();
    let result = match kind {
        Kind::Artist => {
            let editorial = artwork(&attr["editorialArtwork"]["vipSquare"]);
            let header = if !editorial.is_empty() {
                editorial
            } else if !cover.is_empty() {
                cover.clone()
            } else {
                preview(motion)
            };
            json!({"id":id,"name":text(&attr["name"]),"image_url":cover,"header_image":header,"header_video":video(motion,true),"header_logo":logo(attr)})
        }
        Kind::Album => {
            for (target, source) in [
                ("release_date", "releaseDate"),
                ("label", "recordLabel"),
                ("copyright", "copyright"),
            ] {
                metadata.insert(target.into(), text(&attr[source]).into());
            }
            metadata.insert("genre".into(), genres(&attr["genreNames"]).into());
            metadata.insert("editorial_notes".into(), attr["editorialNotes"].clone());
            let header = preview(motion);
            json!({"id":id,"name":text(&attr["name"]),"images":cover,"cover_url":cover,"header_image":if header.is_empty(){cover.clone()}else{header},"header_video":video(motion,false)})
        }
    };
    Ok((result, metadata))
}
