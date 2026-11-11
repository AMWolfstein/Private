// SPDX-License-Identifier: LGPL-3.0-only
// Adapted from Mornye-Extension 12530ceda46dc78a10f9258b7d65a71452dfcf50,
// sources/apple-music/index.js: fetchToken, extractJWTFromString, apiGet.
//! On-demand native artwork HTTP. No network I/O at construction, persistent
//! credentials, downloaded code execution, or detached background work.
use super::{ArtworkDocument, ArtworkError, Kind, parse};
use crate::resolver::Check;
use mornye_network::{HttpRequest, NetworkService, NetworkSession, policy::NetworkPermissions};
use regex::Regex;
use serde_json::Value;
use std::{
    collections::BTreeMap,
    sync::{Arc, LazyLock},
    time::{Duration, Instant},
};

const LIMIT: usize = 8 << 20;
const DEADLINE: Duration = Duration::from_secs(30);
static TOKEN: LazyLock<Regex> = LazyLock::new(|| {
    Regex::new(
    r"(?:devToken=([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+))|((?:eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IldlYlBsYXlLaWQifQ|eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IldlYlBsYXlLaWQifQ)\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)"
).unwrap()
});
static BUNDLES: LazyLock<Regex> =
    LazyLock::new(|| Regex::new(r#"src="(/assets/[^" ]+\.js)""#).unwrap());

#[derive(Clone, Copy)]
enum Role {
    Deezer,
    AppleWeb,
    AppleCatalog,
}
struct Response {
    status: u16,
    body: Vec<u8>,
}
trait Transport: Send + Sync {
    fn get(
        &self,
        role: Role,
        url: &str,
        headers: BTreeMap<String, String>,
        remaining: Duration,
        check: &Check<'_>,
    ) -> Result<Response, ArtworkError>;
}
struct Http {
    deezer: Arc<NetworkSession>,
    web: Arc<NetworkSession>,
    catalog: Arc<NetworkSession>,
}
impl Transport for Http {
    fn get(
        &self,
        role: Role,
        url: &str,
        headers: BTreeMap<String, String>,
        remaining: Duration,
        check: &Check<'_>,
    ) -> Result<Response, ArtworkError> {
        let session = match role {
            Role::Deezer => &self.deezer,
            Role::AppleWeb => &self.web,
            Role::AppleCatalog => &self.catalog,
        };
        let failure = |error: String| match check() {
            Err(reason) => ArtworkError::Cancelled(reason),
            Ok(()) => ArtworkError::Network(error),
        };
        let mut stream = session
            .open_stream(
                HttpRequest {
                    url: url.into(),
                    method: "GET".into(),
                    body: String::new(),
                    headers,
                    default_json: false,
                    user_agent: mornye_network::random_user_agent(),
                },
                remaining,
                remaining,
                check,
            )
            .map_err(failure)?;
        let status = stream.response.status;
        let body = stream
            .read_limited(LIMIT, &mut [0; 16 << 10], check)
            .map_err(failure)?
            .ok_or(ArtworkError::Invalid("response exceeds size limit"))?;
        Ok(Response { status, body })
    }
}

// shortcut: no token cache during inactive migration; add owned expiry-aware
// caching and source retry parity before connecting application callers.
pub struct ArtworkClient {
    transport: Arc<dyn Transport>,
}
impl ArtworkClient {
    pub fn new(network: &Arc<NetworkService>) -> Self {
        let session = |host: &str| {
            network.session(
                NetworkPermissions {
                    domains: vec![host.into()],
                    allow_http: false,
                },
                DEADLINE,
            )
        };
        // Separate sessions prevent catalog Bearer credentials reaching another
        // provider through a redirect. NetworkSession validates every hop.
        Self {
            transport: Arc::new(Http {
                deezer: session("api.deezer.com"),
                web: session("music.apple.com"),
                catalog: session("amp-api.music.apple.com"),
            }),
        }
    }

    pub fn lookup(
        &self,
        provider: &str,
        kind: Kind,
        id: &str,
        check: &Check<'_>,
    ) -> Result<ArtworkDocument, ArtworkError> {
        if !matches!(
            (provider, kind),
            ("apple-music", _) | ("deezer", Kind::Artist)
        ) {
            return Err(ArtworkError::Unsupported);
        }
        let id = id.strip_prefix(&format!("{provider}:")).unwrap_or(id);
        if id.is_empty() || id.len() > 32 || !id.bytes().all(|byte| byte.is_ascii_digit()) {
            return Err(ArtworkError::Invalid("resource identity"));
        }
        let started = Instant::now();
        let budget = || {
            check()?;
            if started.elapsed() >= DEADLINE {
                Err("artwork lookup deadline exceeded".into())
            } else {
                Ok(())
            }
        };
        let run = || {
            let response = if provider == "deezer" {
                self.get(
                    Role::Deezer,
                    &format!("https://api.deezer.com/artist/{id}"),
                    BTreeMap::new(),
                    started,
                    &budget,
                )?
            } else {
                let resource = match kind {
                    Kind::Artist => "artists",
                    Kind::Album => "albums",
                };
                // Artwork-only: exclude track pagination, discography and concerts.
                let url = format!(
                    "https://amp-api.music.apple.com/v1/catalog/us/{resource}/{id}?extend=artistUrl,editorialArtwork,editorialVideo"
                );
                let mut response = None;
                for _ in 0..2 {
                    let token = self.apple_token(started, &budget)?;
                    let headers = BTreeMap::from([
                        ("Authorization".into(), format!("Bearer {token}")),
                        ("Origin".into(), "https://music.apple.com".into()),
                        ("Referer".into(), "https://music.apple.com/".into()),
                    ]);
                    let value = self.get(Role::AppleCatalog, &url, headers, started, &budget)?;
                    let retry = value.status == 401;
                    response = Some(value);
                    if !retry {
                        break;
                    }
                }
                response.expect("at least one catalog attempt")
            };
            match response.status {
                200 => {}
                404 => return Err(ArtworkError::NotFound),
                401 | 403 => return Err(ArtworkError::Authentication),
                status => return Err(ArtworkError::Network(format!("HTTP {status}"))),
            }
            let value: Value = serde_json::from_slice(&response.body)
                .map_err(|_| ArtworkError::Invalid("JSON document"))?;
            budget().map_err(ArtworkError::Cancelled)?;
            parse(provider, kind, id, &value)
        };
        let result = run();
        // Cancellation takes precedence over a late successful parse, while an
        // expired internal budget remains distinguishable from owner cancellation.
        check().map_err(ArtworkError::Cancelled)?;
        if started.elapsed() >= DEADLINE {
            return Err(ArtworkError::Timeout);
        }
        result
    }

    fn get(
        &self,
        role: Role,
        url: &str,
        headers: BTreeMap<String, String>,
        started: Instant,
        check: &Check<'_>,
    ) -> Result<Response, ArtworkError> {
        check().map_err(ArtworkError::Cancelled)?;
        let remaining = DEADLINE.saturating_sub(started.elapsed());
        if remaining.is_zero() {
            return Err(ArtworkError::Timeout);
        }
        let response = self.transport.get(role, url, headers, remaining, check)?;
        if response.body.len() > LIMIT {
            return Err(ArtworkError::Invalid("response exceeds size limit"));
        }
        Ok(response)
    }

    fn apple_token(&self, started: Instant, check: &Check<'_>) -> Result<String, ArtworkError> {
        let page = self.get(
            Role::AppleWeb,
            "https://music.apple.com/us/browse",
            BTreeMap::new(),
            started,
            check,
        )?;
        if page.status != 200 {
            return Err(ArtworkError::Network(format!(
                "Apple token page HTTP {}",
                page.status
            )));
        }
        let html = String::from_utf8_lossy(&page.body);
        if let Some(token) = extract_token(&html) {
            return Ok(token);
        }
        // Same index-bundle preference and six-candidate cap as the pinned source.
        let all: Vec<_> = BUNDLES
            .captures_iter(&html)
            .map(|item| item[1].to_owned())
            .collect();
        let indexed: Vec<_> = all
            .iter()
            .filter(|path| path.starts_with("/assets/index"))
            .collect();
        let candidates: Vec<_> = if indexed.is_empty() {
            all.iter().collect()
        } else {
            indexed
        };
        for path in candidates.into_iter().take(6) {
            if path.contains("-legacy") {
                continue;
            }
            let response = self.get(
                Role::AppleWeb,
                &format!("https://music.apple.com{path}"),
                BTreeMap::new(),
                started,
                check,
            )?;
            if response.status == 200
                && let Some(token) = extract_token(&String::from_utf8_lossy(&response.body))
            {
                return Ok(token);
            }
        }
        Err(ArtworkError::Authentication)
    }
}
fn extract_token(text: &str) -> Option<String> {
    TOKEN
        .captures(text)
        .and_then(|capture| capture.get(1).or_else(|| capture.get(2)))
        .map(|token| token.as_str().to_owned())
}

#[cfg(test)]
mod tests;
