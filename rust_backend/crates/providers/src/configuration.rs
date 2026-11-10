//! Bounded data-only configuration for the existing native lyrics clients.
//!
//! A configuration generation lasts for one Backend lifetime. Installation
//! persists a signed candidate for the next startup; it never mutates readers.
use base64::{Engine, engine::general_purpose::STANDARD};
use ring::signature::{ED25519, UnparsedPublicKey};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::io::Write;
use std::path::{Path, PathBuf};
use url::Url;

#[cfg(test)]
mod tests;

pub const MAX_CONFIG_BYTES: usize = 64 << 10;
pub const MAX_ENVELOPE_BYTES: usize = 96 << 10;
pub const SIGNING_CONTEXT: &[u8] = b"mornye-provider-config-v1\0";
const DEFAULTS: &[u8] = include_bytes!("../../../../extensions/config/providers.json");
const TRUST: &[u8] = include_bytes!("../../../../extensions/config/trusted-keys.json");
const ORIGINS: &[&str] = &[
    "https://lrclib.net",
    "https://lyrics.paxsenix.org",
    "https://lyricsplus.prjktla.my.id",
    "https://lyricsplus.binimum.org",
    "https://beta.music.apple.com",
    "https://amp-api.music.apple.com",
    "https://api.zarz.moe",
    "https://c.y.qq.com",
    "https://lyrics.kugou.com",
    "https://genius.com",
    "https://lrc.red",
    "https://lyrics-api.boidu.dev",
];

#[derive(Debug, thiserror::Error)]
pub enum ConfigError {
    #[error("provider configuration backend unavailable: {0}")]
    BackendUnavailable(String),
    #[error("invalid provider configuration: {0}")]
    Invalid(String),
    #[error("provider configuration authentication failed: {0}")]
    Authentication(String),
    #[error("provider configuration persistence failed: {0}")]
    Persistence(#[from] std::io::Error),
    #[error("provider configuration revision must increase")]
    Revision,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(deny_unknown_fields)]
pub struct ProviderConfig {
    schema_version: u32,
    runtime_version: u32,
    revision: u64,
    #[serde(deserialize_with = "unique_map")]
    lyrics_origins: BTreeMap<String, String>,
}

// serde's ordinary map deserializer accepts duplicate keys with last-wins
// semantics. Reject ambiguity in both provider documents and trusted key maps.
fn unique_map<'de, D>(deserializer: D) -> Result<BTreeMap<String, String>, D::Error>
where
    D: serde::Deserializer<'de>,
{
    struct Visitor;
    impl<'de> serde::de::Visitor<'de> for Visitor {
        type Value = BTreeMap<String, String>;
        fn expecting(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
            f.write_str("a map without duplicate keys")
        }
        fn visit_map<M>(self, mut map: M) -> Result<Self::Value, M::Error>
        where
            M: serde::de::MapAccess<'de>,
        {
            let mut result = BTreeMap::new();
            while let Some((key, value)) = map.next_entry::<String, String>()? {
                if result.insert(key, value).is_some() {
                    return Err(serde::de::Error::custom("duplicate key"));
                }
            }
            Ok(result)
        }
    }
    deserializer.deserialize_map(Visitor)
}

impl ProviderConfig {
    pub fn bundled() -> Self {
        Self::parse(DEFAULTS).expect("validated bundled native provider configuration")
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, ConfigError> {
        if bytes.len() > MAX_CONFIG_BYTES {
            return Err(ConfigError::Invalid("document exceeds 64 KiB".into()));
        }
        let config: Self = serde_json::from_slice(bytes)
            .map_err(|error| ConfigError::Invalid(error.to_string()))?;
        if config.schema_version != 1 || config.runtime_version != 1 || config.revision == 0 {
            return Err(ConfigError::Invalid(
                "unsupported schema/runtime/revision".into(),
            ));
        }
        if config.lyrics_origins.len() != ORIGINS.len()
            || ORIGINS
                .iter()
                .any(|origin| !config.lyrics_origins.contains_key(*origin))
        {
            return Err(ConfigError::Invalid(
                "request origin inventory differs".into(),
            ));
        }
        for (origin, replacement) in &config.lyrics_origins {
            let url =
                Url::parse(replacement).map_err(|error| ConfigError::Invalid(error.to_string()))?;
            if !ORIGINS.contains(&replacement.as_str())
                || url.scheme() != "https"
                || !url.username().is_empty()
                || url.password().is_some()
                || url.query().is_some()
                || url.fragment().is_some()
                || url.path() != "/"
                || url.port().is_some()
            {
                return Err(ConfigError::Invalid(
                    "destination outside compiled HTTPS origins".into(),
                ));
            }
            // Keep authenticated service requests inside their native trust
            // boundary. A signed document is still not permission to send an
            // Apple catalog token to an unrelated provider. Only equivalent
            // existing unauthenticated proxy endpoints may substitute origins.
            let same_service = origin == replacement;
            let lyrics_plus = |value: &str| {
                matches!(
                    value,
                    "https://lyricsplus.prjktla.my.id" | "https://lyricsplus.binimum.org"
                )
            };
            let apple_proxy = |value: &str| {
                matches!(
                    value,
                    "https://lyrics.paxsenix.org" | "https://api.zarz.moe"
                )
            };
            if !same_service
                && !(lyrics_plus(origin) && lyrics_plus(replacement))
                && !(apple_proxy(origin) && apple_proxy(replacement))
            {
                return Err(ConfigError::Invalid(
                    "cross-service origin substitution".into(),
                ));
            }
        }
        Ok(config)
    }

    pub fn revision(&self) -> u64 {
        self.revision
    }

    /// Existing native endpoint injection preserves paths, queries, cancellation
    /// and provider-specific parsing. This schema does not configure algorithms.
    pub fn lyrics_endpoints(&self) -> BTreeMap<String, String> {
        self.lyrics_origins.clone()
    }

    pub fn lyrics_cache_name(&self) -> String {
        // Keep the old cache at the identity generation for compatibility. A
        // changed revision gets its own persistence domain on Backend restart.
        if self.revision == 1 && self == &Self::bundled() {
            ".lyrics_cache.json".into()
        } else {
            format!(".lyrics_cache.config-{}.json", self.revision)
        }
    }
}

#[derive(Clone, Debug, Default)]
pub struct TrustedKeys(BTreeMap<String, Vec<u8>>);

impl TrustedKeys {
    pub fn bundled() -> Self {
        Self::parse(TRUST).expect("validated bundled provider trust keys")
    }

    pub fn parse(bytes: &[u8]) -> Result<Self, ConfigError> {
        if bytes.len() > 4096 {
            return Err(ConfigError::Invalid("trust map exceeds 4 KiB".into()));
        }
        let mut deserializer = serde_json::Deserializer::from_slice(bytes);
        let map = unique_map(&mut deserializer)
            .map_err(|error| ConfigError::Invalid(error.to_string()))?;
        deserializer
            .end()
            .map_err(|error| ConfigError::Invalid(error.to_string()))?;
        if map.len() > 8 {
            return Err(ConfigError::Invalid("at most eight trusted keys".into()));
        }
        let mut keys = BTreeMap::new();
        for (id, encoded) in map {
            if id.is_empty()
                || id.len() > 64
                || !id
                    .bytes()
                    .all(|c| c.is_ascii_alphanumeric() || b"_-".contains(&c))
            {
                return Err(ConfigError::Invalid("invalid key ID".into()));
            }
            let bytes = STANDARD
                .decode(encoded)
                .map_err(|_| ConfigError::Invalid("invalid public key encoding".into()))?;
            if bytes.len() != 32 {
                return Err(ConfigError::Invalid(
                    "Ed25519 public key must be 32 bytes".into(),
                ));
            }
            keys.insert(id, bytes);
        }
        Ok(Self(keys))
    }

    pub fn is_empty(&self) -> bool {
        self.0.is_empty()
    }

    pub fn verify(&self, bytes: &[u8]) -> Result<ProviderConfig, ConfigError> {
        if bytes.len() > MAX_ENVELOPE_BYTES {
            return Err(ConfigError::Invalid("envelope exceeds 96 KiB".into()));
        }
        let envelope: Envelope = serde_json::from_slice(bytes)
            .map_err(|error| ConfigError::Invalid(error.to_string()))?;
        if envelope.format != 1 {
            return Err(ConfigError::Invalid("unsupported envelope format".into()));
        }
        let key = self
            .0
            .get(&envelope.key_id)
            .ok_or_else(|| ConfigError::Authentication("unknown signing key".into()))?;
        let payload = STANDARD
            .decode(envelope.payload)
            .map_err(|_| ConfigError::Authentication("invalid payload encoding".into()))?;
        let signature = STANDARD
            .decode(envelope.signature)
            .map_err(|_| ConfigError::Authentication("invalid signature encoding".into()))?;
        // Domain separation prevents a signature made for an unrelated protocol
        // from authorizing a provider configuration. Sign the exact payload bytes.
        let mut message = SIGNING_CONTEXT.to_vec();
        message.extend_from_slice(&payload);
        UnparsedPublicKey::new(&ED25519, key)
            .verify(&message, &signature)
            .map_err(|_| ConfigError::Authentication("invalid signature".into()))?;
        ProviderConfig::parse(&payload)
    }
}

#[derive(Deserialize)]
#[serde(deny_unknown_fields)]
struct Envelope {
    format: u32,
    key_id: String,
    payload: String,
    signature: String,
}

pub struct ConfigCache {
    path: PathBuf,
    keys: TrustedKeys,
}

pub struct LoadedConfig {
    pub config: ProviderConfig,
    /// Missing cache is normal. Invalid or inaccessible cache is explicit while
    /// the bundled configuration remains usable for offline startup.
    pub fallback_reason: Option<String>,
}

impl ConfigCache {
    pub fn new(data_directory: &Path, keys: TrustedKeys) -> Self {
        Self {
            path: data_directory.join(".provider_config.json"),
            keys,
        }
    }

    fn read_verified(&self) -> Result<ProviderConfig, ConfigError> {
        use std::io::Read;
        let file = fs::File::open(&self.path)?;
        let mut bytes = Vec::new();
        file.take((MAX_ENVELOPE_BYTES + 1) as u64)
            .read_to_end(&mut bytes)?;
        let config = self.keys.verify(&bytes)?;
        if config.revision < ProviderConfig::bundled().revision {
            return Err(ConfigError::Revision);
        }
        Ok(config)
    }

    pub fn load(&self) -> LoadedConfig {
        match self.read_verified() {
            Ok(config) => LoadedConfig {
                config,
                fallback_reason: None,
            },
            Err(ConfigError::Persistence(error))
                if error.kind() == std::io::ErrorKind::NotFound =>
            {
                LoadedConfig {
                    config: ProviderConfig::bundled(),
                    fallback_reason: None,
                }
            }
            Err(error) => LoadedConfig {
                config: ProviderConfig::bundled(),
                fallback_reason: Some(error.to_string()),
            },
        }
    }

    /// The Backend owner serializes installation. A successful write takes
    /// effect only on next initialization. No caller's live cache is invalidated.
    pub fn install(&self, bytes: &[u8]) -> Result<ProviderConfig, ConfigError> {
        let candidate = self.keys.verify(bytes)?;
        let previous = self.load().config;
        if candidate.revision <= previous.revision {
            return Err(ConfigError::Revision);
        }
        let directory = self.path.parent().expect("owned cache directory");
        let mut file = tempfile::NamedTempFile::new_in(directory)?;
        file.write_all(bytes)?;
        file.as_file().sync_all()?;
        file.persist(&self.path)
            .map_err(|error| ConfigError::Persistence(error.error))?;
        Ok(candidate)
    }
}
