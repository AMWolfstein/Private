use regex::Regex;
use std::sync::LazyLock;

static METADATA: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)^\[[a-z][a-z0-9_-]*:.*\]$").unwrap());
static BACKGROUND: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^\[bg:(.*)\]$").unwrap());
static LEADING_TIME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"^\[[0-9]{1,3}:[0-9]{1,2}(?:[.:][0-9]{1,3})?\]").unwrap());
static INLINE_TIME: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"<[0-9]{1,3}:[0-9]{1,2}(?:[.:][0-9]{1,3})?>").unwrap());
static VOICE_PREFIX: LazyLock<Regex> = LazyLock::new(|| Regex::new(r"(?i)^v[1-9][0-9]*:").unwrap());
static INSTRUMENTAL: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r"(?i)^\[instrumental:true\]$").unwrap());
pub fn is_instrumental_marker(raw: &str) -> bool {
    INSTRUMENTAL.is_match(raw.trim())
}

/// Headers, empty timestamps and empty vocal markers are not embedded lyrics.
pub fn has_usable_content(raw: &str) -> bool {
    if is_instrumental_marker(raw) {
        return true;
    }
    for line in raw.split('\n') {
        let mut cleaned = line.trim();
        if cleaned.is_empty() {
            continue;
        }
        if let Some(background) = BACKGROUND.captures(cleaned) {
            cleaned = background.get(1).unwrap().as_str().trim();
        } else if METADATA.is_match(cleaned) {
            continue;
        }
        while let Some(timestamp) = LEADING_TIME.find(cleaned) {
            cleaned = cleaned[timestamp.end()..].trim();
        }
        let without_inline = INLINE_TIME.replace_all(cleaned, "");
        cleaned = without_inline.trim();
        if let Some(voice) = VOICE_PREFIX.find(cleaned) {
            cleaned = cleaned[voice.end()..].trim();
        }
        if !cleaned.is_empty() {
            return true;
        }
    }
    false
}
