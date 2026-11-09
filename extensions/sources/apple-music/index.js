// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/apple-music/index.js
// Inactive source import: no app integration or update trust policy is installed.

const API_BASE = "https://amp-api.music.apple.com/v1/catalog/";

const CACHE_MAX_ENTRIES = 500;

const METADATA_CACHE_TTL_MS = 5 * 60 * 1000;

const SEARCH_CACHE_TTL_MS = 60 * 1000;

const LYRICS_CACHE_TTL_MS = 10 * 60 * 1000;

const NEGATIVE_CACHE_TTL_MS = 30 * 1000;

const API_MAX_ATTEMPTS = 4;

const RETRY_BASE_DELAY_MS = 250;

const RETRY_MAX_DELAY_MS = 4000;

const RETRY_MAX_SERVER_DELAY_MS = 30000;

const MIN_TRACK_MATCH_SCORE = 70;

const CACHE_MISS = { cacheMiss: true };

const MEMORY_CACHE = new Map();

let state = {
  token: null,
  tokenExpiry: 0,
  storefront: "us",
  mediaUserToken: "",
  lyricsTranslation: "",
  lyricsPronunciation: ""
};

function initialize(config) {
  log.info("Apple Music Extension initializing...");
  MEMORY_CACHE.clear();

  // The host passes the flat settings object as the argument. Accept both the
  // flat form and a legacy { settings: {...} } wrapper for safety.
  var s = (config && config.settings) ? config.settings : (config || {});
  if (s) {
    var sf = String(s.storefront || "us").trim().toLowerCase();
    state.storefront = /^[a-z]{2}$/.test(sf) ? sf : "us";
    state.mediaUserToken = (s.mediaUserToken || "").trim();
    state.lyricsTranslation = (s.lyricsTranslation || "").trim().toLowerCase();
    state.lyricsPronunciation = (s.lyricsPronunciation || "").trim().toLowerCase();
  }

  try {
    const cached = storage.get("am_state");
    if (cached) {
      const parsed = JSON.parse(cached);
      if (parsed.token && parsed.tokenExpiry && Date.now() < parsed.tokenExpiry) {
        state.token = parsed.token;
        state.tokenExpiry = parsed.tokenExpiry;
        log.info("Loaded cached token (expires in " +
          Math.round((state.tokenExpiry - Date.now()) / 60000) + " min)");
      }
    }
  } catch (e) {
  }

  return true;
}

function persistState() {
  try {
    return storage.set("am_state", JSON.stringify({
      token: state.token,
      tokenExpiry: state.tokenExpiry
    }));
  } catch (e) {
    log.warn("Failed to persist Apple Music session:", e.message || String(e));
    return false;
  }
}

function cleanup() {
  persistState();
  MEMORY_CACHE.clear();
  return true;
}

function scopedCacheKey(kind, value) {
  return String(state.storefront || "us") + "|" + String(kind || "") + "|" + String(value || "");
}

function cacheGet(key) {
  var entry = MEMORY_CACHE.get(key);
  if (!entry) return null;
  if (Date.now() >= entry.expiresAt) {
    MEMORY_CACHE.delete(key);
    return null;
  }
  MEMORY_CACHE.delete(key);
  MEMORY_CACHE.set(key, entry);
  return entry.value;
}

function cacheSet(key, value, ttlMs) {
  if (!key || value === null || value === undefined) return value;
  if (MEMORY_CACHE.has(key)) MEMORY_CACHE.delete(key);
  MEMORY_CACHE.set(key, {
    value: value,
    expiresAt: Date.now() + Number(ttlMs || METADATA_CACHE_TTL_MS)
  });
  while (MEMORY_CACHE.size > CACHE_MAX_ENTRIES) {
    MEMORY_CACHE.delete(MEMORY_CACHE.keys().next().value);
  }
  return value;
}

function rememberCacheMiss(key) {
  cacheSet(key, CACHE_MISS, NEGATIVE_CACHE_TTL_MS);
  return null;
}

function operationCancelled() {
  try {
    if (typeof utils !== "undefined" && utils) {
      if (typeof utils.isDownloadCancelled === "function" && utils.isDownloadCancelled()) return true;
      if (typeof utils.isRequestCancelled === "function" && utils.isRequestCancelled()) return true;
    }
  } catch (e) {
  }
  return false;
}

function cancellableSleep(ms) {
  var remaining = Math.max(0, Math.round(Number(ms || 0)));
  if (typeof utils === "undefined" || !utils || typeof utils.sleep !== "function") {
    return !operationCancelled();
  }
  while (remaining > 0) {
    if (operationCancelled()) return false;
    var step = Math.min(remaining, 100);
    if (!utils.sleep(step)) return false;
    remaining -= step;
  }
  return !operationCancelled();
}

function responseHeader(headers, name) {
  var wanted = String(name || "").toLowerCase();
  headers = headers || {};
  for (var key in headers) {
    if (Object.prototype.hasOwnProperty.call(headers, key) && String(key).toLowerCase() === wanted) {
      return String(headers[key] || "");
    }
  }
  return "";
}

function retryAfterMilliseconds(response) {
  var raw = responseHeader(response && response.headers, "Retry-After").trim();
  if (!raw) return 0;
  if (/^\d+(?:\.\d+)?$/.test(raw)) {
    return Math.max(0, Math.round(Number(raw) * 1000));
  }
  var timestamp = Date.parse(raw);
  return isNaN(timestamp) ? 0 : Math.max(0, timestamp - Date.now());
}

function retryableStatus(status) {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

function retryableNetworkError(error) {
  var message = String(error || "").toLowerCase();
  return message.indexOf("timeout") >= 0 ||
    message.indexOf("network") >= 0 ||
    message.indexOf("connection") >= 0 ||
    message.indexOf("reset") >= 0 ||
    message.indexOf("refused") >= 0 ||
    message.indexOf("temporar") >= 0;
}

function waitBeforeRetry(attempt, response) {
  var exponential = Math.min(
    RETRY_BASE_DELAY_MS * Math.pow(2, Math.max(0, attempt)),
    RETRY_MAX_DELAY_MS
  );
  var serverDelay = Math.min(retryAfterMilliseconds(response), RETRY_MAX_SERVER_DELAY_MS);
  var delay = Math.max(exponential, serverDelay);
  delay += Math.floor(Math.random() * Math.max(25, Math.floor(exponential / 4)));
  return cancellableSleep(delay);
}

function httpGetWithRetry(url, headers, label) {
  var lastResponse = null;
  var lastError = "";
  for (var attempt = 0; attempt < API_MAX_ATTEMPTS; attempt++) {
    if (operationCancelled()) throw new Error("request cancelled");
    var response = null;
    try {
      response = http.get(url, headers || {});
    } catch (e) {
      lastError = String(e || "network request failed");
      if (!retryableNetworkError(e) || attempt === API_MAX_ATTEMPTS - 1) throw e;
      log.warn("[AppleMusic] " + label + " retry " + (attempt + 2) + "/" + API_MAX_ATTEMPTS +
        " after " + lastError);
      if (!waitBeforeRetry(attempt, null)) throw new Error("request cancelled");
      continue;
    }
    lastResponse = response;
    if (response && !response.error && response.statusCode >= 200 && response.statusCode < 300) {
      return response;
    }
    lastError = response && response.error
      ? String(response.error)
      : "HTTP " + (response ? response.statusCode : "no response");
    var retryable = !response ||
      (response.error && retryableNetworkError(response.error)) ||
      (response && retryableStatus(response.statusCode));
    if (!retryable || attempt === API_MAX_ATTEMPTS - 1) break;
    log.warn("[AppleMusic] " + label + " retry " + (attempt + 2) + "/" + API_MAX_ATTEMPTS +
      " after " + lastError);
    if (!waitBeforeRetry(attempt, response)) throw new Error("request cancelled");
  }
  if (lastResponse) return lastResponse;
  throw new Error(label + " failed: " + lastError);
}

function fetchToken() {
  log.info("Fetching Apple Music developer token...");

  var response = httpGetWithRetry("https://music.apple.com/us/browse", {
    "User-Agent": utils.randomUserAgent()
  }, "developer token page");

  if (!response || response.error || response.statusCode !== 200) {
    throw new Error("Failed to fetch music.apple.com: HTTP " +
      (response ? response.statusCode : "no response"));
  }

  var body = response.body || "";

  // Strategy 1: Token in an iframe devToken= parameter (browser-rendered HTML)
  var tokenMatch = body.match(/devToken=([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)/);

  // Strategy 2: JWT directly in the HTML (match both header field orderings)
  if (!tokenMatch) {
    tokenMatch = body.match(/((?:eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IldlYlBsYXlLaWQifQ|eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IldlYlBsYXlLaWQifQ)\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)/);
  }

  // Strategy 3: Token is in the main JS bundle — find and fetch it
  if (!tokenMatch) {
    log.info("Token not in HTML, checking JS bundles...");
    var bundleMatches = body.match(/src="(\/assets\/index[^"]*\.js)"/g);
    if (!bundleMatches) {
      bundleMatches = body.match(/src="(\/assets\/[^"]*\.js)"/g);
    }
    if (bundleMatches) {
      for (var i = 0; i < bundleMatches.length && i < 6; i++) {
        var srcMatch = bundleMatches[i].match(/src="([^"]+)"/);
        if (!srcMatch) continue;
        // Skip legacy bundles — they're duplicates and may be larger
        if (srcMatch[1].indexOf("-legacy") !== -1) continue;
        var bundleURL = "https://music.apple.com" + srcMatch[1];
        log.debug("Checking bundle:", srcMatch[1]);
        try {
          var bundleResp = httpGetWithRetry(bundleURL, {
            "User-Agent": utils.randomUserAgent()
          }, "developer token bundle");
          if (bundleResp && !bundleResp.error && bundleResp.statusCode === 200) {
            var bundleBody = bundleResp.body || "";
            log.debug("Bundle size:", bundleBody.length, "bytes");
            // Use indexOf for speed on large strings instead of regex
            var token = extractJWTFromString(bundleBody);
            if (token) {
              log.info("Found token in JS bundle:", srcMatch[1]);
              state.token = token;
              parseTokenExpiry();
              return;
            }
          }
        } catch (e) {
          log.debug("Bundle fetch failed:", e.message);
        }
      }
    }
  }

  if (!tokenMatch) {
    throw new Error("Could not find developer token in page HTML or JS bundles");
  }

  state.token = tokenMatch[1];
  parseTokenExpiry();
}

function extractJWTFromString(str) {
  // Apple Music's web token uses the WebPlayKid key id but the JWT header
  // field order has varied over time, so match both known orderings:
  //   {"alg":"ES256","typ":"JWT","kid":"WebPlayKid"}
  //   {"typ":"JWT","alg":"ES256","kid":"WebPlayKid"}
  var prefixes = [
    "eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IldlYlBsYXlLaWQifQ.",
    "eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IldlYlBsYXlLaWQifQ."
  ];
  var idx = -1;
  for (var p = 0; p < prefixes.length; p++) {
    idx = str.indexOf(prefixes[p]);
    if (idx !== -1) break;
  }
  if (idx === -1) return null;

  // Read from the start of the JWT until we hit a non-JWT character
  var start = idx;
  var end = start;
  var jwtChars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_-.";
  while (end < str.length && jwtChars.indexOf(str.charAt(end)) !== -1) {
    end++;
  }

  var candidate = str.substring(start, end);
  // A valid JWT has exactly 3 parts separated by dots
  var parts = candidate.split(".");
  if (parts.length === 3 && parts[0].length > 0 && parts[1].length > 0 && parts[2].length > 0) {
    return candidate;
  }
  return null;
}

function parseTokenExpiry() {
  try {
    var parts = state.token.split(".");
    var payload = JSON.parse(decodeBase64URL(parts[1]));
    if (payload.exp) {
      // Expire 5 minutes early to avoid edge cases
      state.tokenExpiry = (payload.exp * 1000) - 300000;
    } else {
      state.tokenExpiry = Date.now() + (12 * 60 * 60 * 1000);
    }
  } catch (e) {
    state.tokenExpiry = Date.now() + (12 * 60 * 60 * 1000);
  }

  log.info("Token valid for " +
    Math.round((state.tokenExpiry - Date.now()) / 60000) + " minutes");
  persistState();
}

function ensureToken() {
  if (!state.token || Date.now() >= state.tokenExpiry) {
    fetchToken();
  }
}

function apiGet(path, allowTokenRefresh) {
  var tokenRefreshed = false;
  var lastMessage = "API request failed";

  for (var attempt = 0; attempt < API_MAX_ATTEMPTS; attempt++) {
    if (operationCancelled()) throw new Error("request cancelled");
    try {
      ensureToken();
    } catch (tokenError) {
      lastMessage = tokenError && tokenError.message ? tokenError.message : String(tokenError);
      if (attempt === API_MAX_ATTEMPTS - 1 || !retryableNetworkError(lastMessage)) {
        throw tokenError;
      }
      if (!waitBeforeRetry(attempt, null)) throw new Error("request cancelled");
      continue;
    }

    var url = API_BASE + state.storefront + "/" + path;
    var response = null;
    try {
      response = http.get(url, {
        "Authorization": "Bearer " + state.token,
        "Origin": "https://music.apple.com",
        "Referer": "https://music.apple.com/",
        "User-Agent": utils.randomUserAgent()
      });
    } catch (networkError) {
      lastMessage = "API request failed: " + String(networkError || "network error");
      if (!retryableNetworkError(networkError) || attempt === API_MAX_ATTEMPTS - 1) {
        throw networkError;
      }
      log.warn("[AppleMusic] Catalog retry " + (attempt + 2) + "/" + API_MAX_ATTEMPTS +
        " after " + lastMessage);
      if (!waitBeforeRetry(attempt, null)) throw new Error("request cancelled");
      continue;
    }

    if (response && !response.error && response.statusCode === 200) {
      return JSON.parse(response.body);
    }

    if (response && response.statusCode === 401 && allowTokenRefresh !== false && !tokenRefreshed) {
      log.info("Developer token rejected, refreshing once...");
      state.token = null;
      state.tokenExpiry = 0;
      persistState();
      tokenRefreshed = true;
      continue;
    }

    lastMessage = response && response.error
      ? "API request failed: " + response.error
      : "API request failed: HTTP " + (response ? response.statusCode : "no response");
    var retryable = !response ||
      (response.error && retryableNetworkError(response.error)) ||
      (response && retryableStatus(response.statusCode));
    if (!retryable || attempt === API_MAX_ATTEMPTS - 1) {
      throw new Error(lastMessage);
    }
    log.warn("[AppleMusic] Catalog retry " + (attempt + 2) + "/" + API_MAX_ATTEMPTS +
      " after " + lastMessage);
    if (!waitBeforeRetry(attempt, response)) throw new Error("request cancelled");
  }

  throw new Error(lastMessage);
}

function apiGetWithUserToken(path) {
  var tokenRefreshed = false;

  for (var attempt = 0; attempt < API_MAX_ATTEMPTS; attempt++) {
    if (operationCancelled()) return null;
    try {
      ensureToken();
    } catch (tokenError) {
      if (attempt === API_MAX_ATTEMPTS - 1 || !retryableNetworkError(tokenError && tokenError.message)) {
        log.debug("Lyrics developer token refresh failed:", tokenError.message || String(tokenError));
        return null;
      }
      if (!waitBeforeRetry(attempt, null)) return null;
      continue;
    }

    var url = API_BASE + state.storefront + "/" + path;
    var headers = {
      "Authorization": "Bearer " + state.token,
      "Media-User-Token": state.mediaUserToken,
      "Origin": "https://music.apple.com",
      "Referer": "https://music.apple.com/",
      "User-Agent": utils.randomUserAgent()
    };
    var response = null;
    try {
      response = http.get(url, headers);
    } catch (networkError) {
      if (!retryableNetworkError(networkError) || attempt === API_MAX_ATTEMPTS - 1) {
        log.debug("Lyrics API request failed:", String(networkError || "network error"));
        return null;
      }
      log.warn("[AppleMusic] Lyrics retry " + (attempt + 2) + "/" + API_MAX_ATTEMPTS +
        " after " + String(networkError || "network error"));
      if (!waitBeforeRetry(attempt, null)) return null;
      continue;
    }

    if (response && !response.error && response.statusCode === 200) {
      try {
        return JSON.parse(response.body);
      } catch (parseError) {
        log.debug("Failed to parse lyrics API response:", parseError.message);
        return null;
      }
    }
    if (response && response.statusCode === 404) return null;

    if (response && response.statusCode === 401 && !tokenRefreshed) {
      log.info("Lyrics request rejected developer token, refreshing once...");
      state.token = null;
      state.tokenExpiry = 0;
      persistState();
      tokenRefreshed = true;
      continue;
    }
    if (response && (response.statusCode === 401 || response.statusCode === 403)) {
      log.warn("Lyrics API auth failed (HTTP " + response.statusCode +
        "). Media User Token may be invalid or expired.");
      return null;
    }

    var retryable = !response ||
      (response.error && retryableNetworkError(response.error)) ||
      (response && retryableStatus(response.statusCode));
    if (!retryable || attempt === API_MAX_ATTEMPTS - 1) {
      log.debug("Lyrics API request failed:", response && response.error
        ? response.error
        : "HTTP " + (response ? response.statusCode : "no response"));
      return null;
    }
    log.warn("[AppleMusic] Lyrics retry " + (attempt + 2) + "/" + API_MAX_ATTEMPTS);
    if (!waitBeforeRetry(attempt, response)) return null;
  }

  return null;
}

function artworkURL(artwork, size) {
  if (!artwork || !artwork.url) return "";
  size = size || Math.max(Number(artwork.width || 0), Number(artwork.height || 0), 3000);
  if (size > 6000) size = 6000;
  return artwork.url.replace("{w}", String(size)).replace("{h}", String(size));
}

function previewURL(attributes) {
  var previews = attributes && attributes.previews;
  if (!Array.isArray(previews) || previews.length === 0) return "";
  return previews[0] && previews[0].url ? previews[0].url : "";
}

var MOTION_VIDEO_KEYS = [
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
  "motionDetailWide"
];

function motionArtworkIsTallKey(key) {
  return key.indexOf("Tall") >= 0 || key.indexOf("3x4") >= 0;
}

function motionArtworkVideoURL(editorialVideo, allowNonTall) {
  if (!editorialVideo) return "";
  for (var i = 0; i < MOTION_VIDEO_KEYS.length; i++) {
    var key = MOTION_VIDEO_KEYS[i];
    if (!allowNonTall && !motionArtworkIsTallKey(key)) continue;
    var entry = editorialVideo[key];
    if (entry && entry.video) return entry.video;
  }
  return "";
}

function motionArtworkPreviewHeight(key, entry, width) {
  var frame = entry && entry.previewFrame ? entry.previewFrame : null;
  var frameWidth = frame && Number(frame.width || frame.w || 0);
  var frameHeight = frame && Number(frame.height || frame.h || 0);
  if (frameWidth > 0 && frameHeight > 0) {
    return Math.round(width * frameHeight / frameWidth);
  }

  if (motionArtworkIsTallKey(key)) {
    return Math.round(width * 4 / 3);
  }
  if (
    key.indexOf("Wide") >= 0 ||
    key.indexOf("Fullscreen") >= 0 ||
    key.indexOf("16x9") >= 0
  ) {
    return Math.round(width * 9 / 16);
  }
  return width;
}

function motionArtworkPreviewURL(editorialVideo, size) {
  if (!editorialVideo) return "";
  size = size || 1080;
  for (var i = 0; i < MOTION_VIDEO_KEYS.length; i++) {
    var key = MOTION_VIDEO_KEYS[i];
    var entry = editorialVideo[key];
    if (entry && entry.previewFrame && entry.previewFrame.url) {
      var height = motionArtworkPreviewHeight(key, entry, size);
      return entry.previewFrame.url
        .replace("{w}", String(size))
        .replace("{h}", String(height));
    }
  }
  return "";
}

function artistHeaderArtwork(attributes) {
  var attr = attributes || {};
  var editorial = attr.editorialArtwork || {};
  return {
    image: artworkURL(editorial.vipSquare) || artworkURL(attr.artwork) ||
      motionArtworkPreviewURL(attr.editorialVideo),
    video: motionArtworkVideoURL(attr.editorialVideo, true)
  };
}

function artistNameArtworkURL(attributes) {
  var editorial = attributes && attributes.editorialArtwork || {};
  var logo = editorial.musicContentColorLogoTrimmed;
  if (!logo || !logo.url) return "";
  var width = Number(logo.width || 0);
  var height = Number(logo.height || 0);
  if (width <= 0 || height <= 0) return "";
  var outputWidth = Math.min(width, 1200);
  var outputHeight = Math.max(1, Math.round(outputWidth * height / width));
  // A JPEG rendition flattens the transparent logo background.
  return logo.url.replace("{w}", String(outputWidth))
    .replace("{h}", String(outputHeight)).replace(/\.jpg(?=\?|$)/, ".png");
}

function uniqueValues(values) {
  var result = [];
  var seen = {};
  values = values || [];
  for (var i = 0; i < values.length; i++) {
    var value = String(values[i] || "").trim();
    var key = value.toLowerCase();
    if (!value || seen[key]) continue;
    seen[key] = true;
    result.push(value);
  }
  return result;
}

function appleGenres(attributes) {
  var genres = attributes && attributes.genreNames || [];
  return uniqueValues(genres.filter(function (genre) {
    return String(genre || "").trim().toLowerCase() !== "music";
  })).join("; ");
}

function appleAlbumType(attributes) {
  attributes = attributes || {};
  if (attributes.isCompilation === true) return "compilation";
  if (attributes.isSingle === true) return "single";
  return "album";
}

function appleAudioQuality(attributes) {
  var traits = attributes && attributes.audioTraits || [];
  var normalizedTraits = traits.map(function (trait) {
    return String(trait || "").trim().toLowerCase().replace(/_/g, "-");
  });
  if (normalizedTraits.indexOf("hi-res-lossless") >= 0) return "24-bit";
  if (normalizedTraits.indexOf("lossless") >= 0) return "16-bit";
  if (normalizedTraits.indexOf("lossy-stereo") >= 0) return "LOSSY";
  return "";
}

function appleAudioModes(attributes) {
  var traits = attributes && attributes.audioTraits || [];
  var modes = [];
  if (traits.indexOf("atmos") >= 0) modes.push("DOLBY_ATMOS");
  if (traits.indexOf("spatial") >= 0) modes.push("SPATIAL_AUDIO");
  return modes.join(",");
}

function firstRelationshipItem(resource, relationshipName) {
  var relationship = resource && resource.relationships && resource.relationships[relationshipName];
  var items = relationship && relationship.data || [];
  return items.length ? items[0] : null;
}

function appleArtistURL(artist) {
  return String(artist && artist.attributes && artist.attributes.url || "").trim();
}

function appleAlbumURL(album) {
  var attributes = album && album.attributes || {};
  if (attributes.url) return String(attributes.url);
  return album && album.id
    ? "https://music.apple.com/" + state.storefront + "/album/" + album.id
    : "";
}

function totalDiscsFromSongs(songs) {
  var total = 0;
  songs = songs || [];
  for (var i = 0; i < songs.length; i++) {
    var disc = Number(songs[i] && songs[i].attributes && songs[i].attributes.discNumber || 0);
    if (disc > total) total = disc;
  }
  return total;
}

function albumIDFromSong(song) {
  var album = firstRelationshipItem(song, "albums");
  if (album && album.id) return album.id;
  var url = String(song && song.attributes && song.attributes.url || "");
  var match = url.match(/\/album\/[^/]+\/(\d+)/i);
  return match ? match[1] : "";
}

function formatSong(song, albumData, totalDiscsOverride) {
  var attr = song.attributes || {};
  var albumAttr = albumData ? (albumData.attributes || {}) : {};

  // Use square artwork for images (UI display + download embedding).
  // tallArtworkURL is kept for future use when UI supports tall containers.
  var coverURL = artworkURL(attr.artwork);
  var albumID = "";
  var albumName = attr.albumName || "";

  // Try to get album ID from relationships
  var albumRel = song.relationships && song.relationships.albums;
  if (albumRel && albumRel.data && albumRel.data.length > 0) {
    albumID = albumRel.data[0].id || "";
  }
  // If we have albumData directly, use its ID
  if (albumData) {
    albumID = albumData.id || albumID;
    albumName = albumAttr.name || albumName;
    if (!coverURL) coverURL = artworkURL(albumAttr.artwork);
  }

  var artistResource = firstRelationshipItem(song, "artists") ||
    firstRelationshipItem(albumData, "artists");
  var albumURL = appleAlbumURL(albumData) || (albumID
    ? "https://music.apple.com/" + state.storefront + "/album/" + albumID
    : "");
  var trackURL = attr.url || ("https://music.apple.com/" + state.storefront + "/song/" + song.id);
  var totalDiscs = Number(totalDiscsOverride || albumData && albumData._totalDiscs || 0);
  var genre = appleGenres(attr) || appleGenres(albumAttr);

  return {
    id: song.id || "",
    name: attr.name || "",
    artists: attr.artistName || "",
    album_name: albumName,
    album_artist: attr.albumArtistName || albumAttr.artistName || attr.artistName || "",
    artist_id: artistResource && artistResource.id || "",
    artist_url: appleArtistURL(artistResource),
    duration_ms: attr.durationInMillis || 0,
    preview_url: previewURL(attr),
    images: coverURL,
    cover_url: coverURL,
    release_date: albumAttr.releaseDate || attr.releaseDate || "",
    track_number: attr.trackNumber || 0,
    total_tracks: albumAttr.trackCount || 0,
    disc_number: attr.discNumber || 1,
    total_discs: totalDiscs,
    external_urls: trackURL,
    external_links: {
      apple_music_track: trackURL,
      apple_music_album: albumURL
    },
    isrc: attr.isrc || "",
    album_id: albumID,
    album_url: albumURL,
    album_type: appleAlbumType(albumAttr),
    genre: genre,
    label: albumAttr.recordLabel || "",
    copyright: albumAttr.copyright || "",
    composer: attr.composerName || "",
    comment: albumURL,
    explicit: attr.contentRating === "explicit",
    audio_quality: appleAudioQuality(attr),
    audio_modes: appleAudioModes(attr),
    provider_id: "apple-music",
    item_type: "track",
    upc: albumAttr.upc || "",
    is_compilation: albumAttr.isCompilation === true,
    has_lyrics: attr.hasLyrics === true,
    has_time_synced_lyrics: attr.hasTimeSyncedLyrics === true
  };
}

function formatAlbumInfo(album) {
  var attr = album.attributes || {};
  var artistItems = album.relationships && album.relationships.artists
    ? album.relationships.artists.data
    : [];
  var firstArtistId = artistItems.length > 0 ? artistItems[0].id : "";
  var firstArtistURL = artistItems.length > 0 ? appleArtistURL(artistItems[0]) : "";
  var albumURL = appleAlbumURL(album);

  // Use square artwork — tall artwork causes 3:4 covers in downloaded files.
  var coverURL = artworkURL(attr.artwork);
  var editorialVideo = attr.editorialVideo;
  var headerVideo = motionArtworkVideoURL(editorialVideo);
  var headerImage = motionArtworkPreviewURL(editorialVideo) || coverURL;

  return {
    id: album.id || "",
    name: attr.name || "",
    artists: attr.artistName || "",
    artist_id: firstArtistId,
    artist_url: firstArtistURL,
    images: coverURL,
    cover_url: coverURL,
    header_image: headerImage,
    header_video: headerVideo,
    release_date: attr.releaseDate || "",
    total_tracks: attr.trackCount || 0,
    total_discs: Number(album._totalDiscs || 0),
    album_type: appleAlbumType(attr),
    album_url: albumURL,
    external_urls: albumURL,
    record_label: attr.recordLabel || "",
    label: attr.recordLabel || "",
    copyright: attr.copyright || "",
    genre: appleGenres(attr),
    comment: albumURL,
    explicit: attr.contentRating === "explicit",
    audio_traits: attr.audioTraits || [],
    provider_id: "apple-music",
    item_type: "album",
    upc: attr.upc || "",
    is_compilation: attr.isCompilation === true,
    editorial_notes: attr.editorialNotes || null
  };
}

function collectRelationshipItems(resource, relationshipName) {
  var relationship = resource && resource.relationships && resource.relationships[relationshipName];
  var items = relationship && relationship.data ? relationship.data.slice() : [];
  var nextURL = relationship && relationship.next;
  while (nextURL) {
    try {
      var nextPath = nextURL.replace(/^\/v1\/catalog\/[a-z]{2}\//, "");
      var nextData = apiGet(nextPath);
      var nextItems = nextData.data || [];
      if (!nextItems.length) break;
      items = items.concat(nextItems);
      nextURL = nextData.next || null;
    } catch (e) {
      log.debug(relationshipName + " pagination error:", e.message);
      break;
    }
  }
  return items;
}

function hydrateAlbumsForSongs(songs, includeTrackRelationships) {
  var albumIDs = [];
  var seen = {};
  var albumsByID = {};
  songs = songs || [];
  for (var i = 0; i < songs.length; i++) {
    var albumID = albumIDFromSong(songs[i]);
    if (!albumID || seen[albumID]) continue;
    seen[albumID] = true;
    var cachedAlbum = cacheGet(scopedCacheKey("raw-album", albumID));
    if (cachedAlbum && cachedAlbum !== CACHE_MISS) {
      albumsByID[albumID] = cachedAlbum;
    } else {
      albumIDs.push(albumID);
    }
  }

  for (var offset = 0; offset < albumIDs.length; offset += 25) {
    var chunk = albumIDs.slice(offset, offset + 25);
    try {
      var data = apiGet(
        "albums?ids=" + encodeURIComponent(chunk.join(",")) +
        "&include=" + (includeTrackRelationships === false ? "artists" : "tracks,artists") +
        "&extend=artistUrl,editorialArtwork,trackCount,upc"
      );
      var albums = data.data || [];
      for (var j = 0; j < albums.length; j++) {
        var album = albums[j];
        album._totalDiscs = includeTrackRelationships === false
          ? 0
          : totalDiscsFromSongs(collectRelationshipItems(album, "tracks"));
        var id = String(album.id || "");
        if (!id) continue;
        albumsByID[id] = album;
        cacheSet(scopedCacheKey("raw-album", id), album, METADATA_CACHE_TTL_MS);
      }
    } catch (e) {
      log.debug("Batch album hydration failed:", e.message);
    }
  }
  return albumsByID;
}

function fetchAlbum(albumID) {
  albumID = String(albumID || "").trim();
  var cacheKey = scopedCacheKey("album", albumID);
  var cached = cacheGet(cacheKey);
  if (cached === CACHE_MISS) throw new Error("Album not found: " + albumID);
  if (cached) return cached;

  log.info("Fetching album:", albumID);

  var data = apiGet(
    "albums/" + albumID +
    "?include=tracks,artists" +
    "&extend=artistUrl,editorialArtwork,editorialVideo,trackCount,upc"
  );
  var albums = data.data || [];
  if (albums.length === 0) {
    rememberCacheMiss(cacheKey);
    throw new Error("Album not found: " + albumID);
  }

  var album = albums[0];
  var trackItems = collectRelationshipItems(album, "tracks");
  var totalDiscs = totalDiscsFromSongs(trackItems) || (trackItems.length ? 1 : 0);
  album._totalDiscs = totalDiscs;
  cacheSet(scopedCacheKey("raw-album", albumID), album, METADATA_CACHE_TTL_MS);
  var albumAttributes = album.attributes || {};
  var traitValues = (albumAttributes.audioTraits || []).slice();
  for (var traitIndex = 0; traitIndex < trackItems.length; traitIndex++) {
    traitValues = traitValues.concat(
      trackItems[traitIndex] && trackItems[traitIndex].attributes &&
      trackItems[traitIndex].attributes.audioTraits || []
    );
  }
  albumAttributes.audioTraits = uniqueValues(traitValues);
  var albumInfo = formatAlbumInfo(album);

  var tracks = [];
  for (var i = 0; i < trackItems.length; i++) {
    tracks.push(formatSong(trackItems[i], album, totalDiscs));
  }

  log.info("Fetched", tracks.length, "tracks from album");

  return cacheSet(cacheKey, {
    type: "album",
    album_info: albumInfo,
    track_list: tracks
  }, METADATA_CACHE_TTL_MS);
}

function fetchArtist(artistID) {
  artistID = String(artistID || "").trim();
  var cacheKey = scopedCacheKey("artist", artistID);
  var cached = cacheGet(cacheKey);
  if (cached === CACHE_MISS) throw new Error("Artist not found: " + artistID);
  if (cached) return cached;

  var page = /^(\d+):albums:(\d+)$/.exec(artistID);
  if (page) {
    var pageData = apiGet("artists/" + page[1] + "/albums?limit=100&offset=" + page[2]);
    return cacheSet(cacheKey, {
      type: "artist",
      artist: {
        id: page[1],
        albums: formatArtistAlbums(pageData.data || [], page[1], {}),
        albums_next: (pageData.data || []).length
          ? artistAlbumsNext(page[1], pageData.next, Number(page[2])) : "",
        provider_id: "apple-music"
      }
    }, METADATA_CACHE_TTL_MS);
  }

  log.info("Fetching artist:", artistID);

  var data = apiGet("artists/" + artistID + "?include=albums&limit[albums]=100&views=top-songs&extend=editorialVideo,editorialArtwork");
  var artists = data.data || [];
  if (artists.length === 0) {
    rememberCacheMiss(cacheKey);
    throw new Error("Artist not found: " + artistID);
  }

  var artist = artists[0];
  var attr = artist.attributes || {};

  var topTracks = [];
  var topSongsView = artist.views && artist.views["top-songs"];
  if (topSongsView && topSongsView.data) {
    // Artist browsing does not need every track from each top song's album.
    var topAlbums = hydrateAlbumsForSongs(topSongsView.data, false);
    for (var i = 0; i < topSongsView.data.length; i++) {
      var song = topSongsView.data[i];
      var topAlbum = topAlbums[albumIDFromSong(song)] || null;
      topTracks.push(formatSong(song, topAlbum, topAlbum && topAlbum._totalDiscs));
    }
  }

  // Return one page immediately. Large composer catalogs can contain tens of
  // thousands of releases; draining them here exceeds the app request deadline.
  var albumItems = artist.relationships && artist.relationships.albums
    ? artist.relationships.albums.data
    : [];
  var albumNext = artist.relationships && artist.relationships.albums
    ? artist.relationships.albums.next
    : null;
  var albums = formatArtistAlbums(albumItems, artistID, attr);

  log.info("Fetched artist with", albums.length, "releases and", topTracks.length, "top tracks");

  var header = artistHeaderArtwork(attr);

  return cacheSet(cacheKey, {
    type: "artist",
    artist: {
      id: artistID,
      name: attr.name || "",
      image_url: artworkURL(attr.artwork),
      header_image: header.image,
      header_video: header.video,
      header_logo: artistNameArtworkURL(attr),
      concerts: fetchArtistConcerts(artistID),
      artist_url: attr.url || "",
      external_urls: attr.url || "",
      listeners: 0,
      albums: albums,
      albums_next: artistAlbumsNext(artistID, albumNext, 0),
      top_tracks: topTracks,
      provider_id: "apple-music"
    }
  }, METADATA_CACHE_TTL_MS);
}

function artistAlbumsNext(artistID, next, currentOffset) {
  var match = /[?&]offset=(\d+)(?:&|$)/.exec(String(next || ""));
  if (!match || Number(match[1]) <= currentOffset) return "";
  return artistID + ":albums:" + match[1];
}

function parseArtistConcerts(html) {
  var match = /<script\b[^>]*\bid=["']serialized-server-data["'][^>]*>([\s\S]*?)<\/script>/i.exec(html);
  if (!match) return [];
  var payload = JSON.parse(match[1]);
  var pages = Array.isArray(payload) ? payload : payload.data;
  if (!Array.isArray(pages)) return [];
  var concerts = [];
  var seen = Object.create(null);
  pages.slice(0, 5).forEach(function (page) {
    var sections = page && page.data && page.data.sections;
    if (!Array.isArray(sections)) return;
    sections.slice(0, 30).forEach(function (section) {
      if (!section || section.itemKind !== "calendarEventLockup" || !Array.isArray(section.items)) return;
      section.items.slice(0, 500).forEach(function (item) {
        if (!item || item.isDisabled || concerts.length >= 500) return;
        var descriptor = item.contentDescriptor || {};
        if (descriptor.kind !== "concert") return;
        var id = descriptor.identifiers && descriptor.identifiers.storeAdamID;
        var date = item.artwork && item.artwork.date;
        if (typeof id !== "string" || !id || seen[id] ||
            typeof date !== "string" || !Number.isFinite(Date.parse(date))) return;
        var location = typeof item.title === "string" ? item.title.trim() : "";
        if (!location) return;
        var details = typeof item.subtitle === "string" ? item.subtitle.split("·") : [];
        var url = typeof descriptor.url === "string" &&
          /^https:\/\/music\.apple\.com\/[a-z]{2}\/concerts\/ce\.[a-z0-9-]+$/i.test(descriptor.url)
          ? descriptor.url : "";
        seen[id] = true;
        concerts.push({
          id: id,
          location: location,
          venue: (details[0] || "").trim(),
          start_at: date,
          time_zone: typeof item.artwork.timeZone === "string" ? item.artwork.timeZone : "",
          detail_id: url ? id : "",
          url: url
        });
      });
    });
  });
  concerts.sort(function (a, b) { return Date.parse(a.start_at) - Date.parse(b.start_at); });
  return concerts;
}

function fetchArtistConcerts(artistID) {
  if (!/^\d+$/.test(artistID) || operationCancelled()) return [];
  try {
    var storefront = /^[a-z]{2}$/i.test(state.storefront) ? state.storefront.toLowerCase() : "us";
    var response = http.get("https://music.apple.com/" + storefront + "/concerts/artist/" + artistID, {
      "User-Agent": utils.randomUserAgent(),
      "Accept": "text/html"
    });
    if (!response || response.error || response.statusCode !== 200) return [];
    return parseArtistConcerts(response.body);
  } catch (error) {
    // Concerts are optional: an unavailable schedule must not hide the discography.
    log.warn("Artist concerts unavailable:", error.message || String(error));
    return [];
  }
}

function sortAlbumsNewestFirst(items) {
  return items.map(function (album, index) {
    var date = String(album && album.attributes && album.attributes.releaseDate || "");
    return { album: album, index: index, date: date };
  }).sort(function (a, b) {
    if (a.date !== b.date) {
      if (!a.date) return 1;
      if (!b.date) return -1;
      return a.date < b.date ? 1 : -1;
    }
    return a.index - b.index;
  }).map(function (entry) { return entry.album; });
}

function formatArtistAlbums(items, artistID, artistAttributes) {
  return sortAlbumsNewestFirst(items).map(function (album) {
    var attr = album.attributes || {};
    return {
      id: album.id || "",
      name: attr.name || "",
      album_type: appleAlbumType(attr),
      release_date: attr.releaseDate || "",
      total_tracks: attr.trackCount || 0,
      artists: attr.artistName || artistAttributes.name || "",
      artist_id: artistID,
      artist_url: artistAttributes.url || "",
      cover_url: artworkURL(attr.artwork),
      external_urls: attr.url || "",
      provider_id: "apple-music"
    };
  });
}

function searchAppleSongs(searchTerm, limit) {
  var normalizedLimit = Math.max(1, Math.min(25, Number(limit || 10)));
  var key = scopedCacheKey(
    "song-search",
    normalizeText(searchTerm) + "|" + normalizedLimit
  );
  var cached = cacheGet(key);
  if (cached) return cached;
  var searchData = apiGet(
    "search?term=" + encodeURIComponent(searchTerm) +
    "&types=songs&limit=" + normalizedLimit
  );
  var songs = searchData.results && searchData.results.songs
    ? searchData.results.songs.data || []
    : [];
  return cacheSet(key, songs, SEARCH_CACHE_TTL_MS);
}

function scoreAppleSongMatch(song, targetName, targetArtist, targetAlbum, targetDurationMs, targetISRC) {
  var attr = song && song.attributes || {};
  var wantedISRC = String(targetISRC || "").trim().toUpperCase();
  var actualISRC = String(attr.isrc || "").trim().toUpperCase();
  var exactISRC = false;
  if (wantedISRC && actualISRC) {
    if (wantedISRC !== actualISRC) return -1;
    exactISRC = true;
  }

  var titleSimilarity = matching.compareStrings(targetName || "", attr.name || "");
  var artistSimilarity = matching.compareStrings(targetArtist || "", attr.artistName || "");
  if (!exactISRC && (titleSimilarity < 0.55 || artistSimilarity < 0.45)) return -1;

  var score = titleSimilarity * 50 + artistSimilarity * 30;
  if (targetAlbum && attr.albumName) {
    var albumSimilarity = matching.compareStrings(targetAlbum, attr.albumName);
    score += albumSimilarity * 10;
    if (!exactISRC && albumSimilarity < 0.25) score -= 15;
  }
  if (Number(targetDurationMs || 0) > 0 && Number(attr.durationInMillis || 0) > 0) {
    var durationSimilarity = matching.compareDuration(
      Number(targetDurationMs),
      Number(attr.durationInMillis)
    );
    score += durationSimilarity * 10;
    if (!exactISRC && durationSimilarity < 0.5) score -= 25;
  }
  if (exactISRC) score += 120;
  return score;
}

function findBestMatch(songs, targetName, targetArtist, targetAlbum, targetDurationMs, targetISRC) {
  if (!songs || songs.length === 0) return null;
  var best = null;
  var bestScore = -1;
  for (var i = 0; i < songs.length; i++) {
    var score = scoreAppleSongMatch(
      songs[i],
      targetName,
      targetArtist,
      targetAlbum,
      targetDurationMs,
      targetISRC
    );
    if (score > bestScore) {
      bestScore = score;
      best = songs[i];
    }
  }
  if (!best || bestScore < MIN_TRACK_MATCH_SCORE) {
    log.debug("Apple Music match rejected; best score:", bestScore.toFixed ? bestScore.toFixed(1) : bestScore);
    return null;
  }
  return best;
}

function normalizeText(text) {
  if (!text) return "";
  return text.toLowerCase()
    .replace(/[^a-z0-9\u00c0-\u024f\u0400-\u04ff\u3040-\u30ff\u3400-\u9fff\uac00-\ud7af]+/g, " ")
    .replace(/\s+/g, " ")
    .trim();
}

function getAlbum(albumId) {
  try {
    var result = fetchAlbum(albumId);
    var tracks = result.track_list.map(function (t) {
      t.provider_id = "apple-music";
      return t;
    });
    return {
      id: albumId,
      name: result.album_info.name,
      artists: result.album_info.artists,
      artist_id: result.album_info.artist_id,
      artist_url: result.album_info.artist_url,
      release_date: result.album_info.release_date,
      total_tracks: result.album_info.total_tracks,
      total_discs: result.album_info.total_discs,
      album_type: result.album_info.album_type,
      album_url: result.album_info.album_url,
      external_urls: result.album_info.external_urls,
      label: result.album_info.label,
      copyright: result.album_info.copyright,
      genre: result.album_info.genre,
      comment: result.album_info.comment,
      explicit: result.album_info.explicit,
      images: result.album_info.images,
      cover_url: result.album_info.images,
      header_image: result.album_info.header_image,
      header_video: result.album_info.header_video,
      audio_traits: result.album_info.audio_traits,
      editorial_notes: result.album_info.editorial_notes,
      tracks: tracks,
      provider_id: "apple-music"
    };
  } catch (e) {
    log.error("getAlbum failed:", e.message);
    return null;
  }
}

function getArtist(artistId) {
  try {
    var result = fetchArtist(artistId);
    return result.artist;
  } catch (e) {
    log.error("getArtist failed:", e.message);
    return null;
  }
}

function decodeBase64URL(str) {
  str = str.replace(/-/g, "+").replace(/_/g, "/");
  while (str.length % 4 !== 0) {
    str += "=";
  }
  return atob(str);
}

function atob(str) {
  var chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
  var result = "";
  var i = 0;

  str = str.replace(/[^A-Za-z0-9+/=]/g, "");

  while (i < str.length) {
    var enc1 = chars.indexOf(str.charAt(i++));
    var enc2 = chars.indexOf(str.charAt(i++));
    var enc3 = chars.indexOf(str.charAt(i++));
    var enc4 = chars.indexOf(str.charAt(i++));

    var chr1 = (enc1 << 2) | (enc2 >> 4);
    var chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
    var chr3 = ((enc3 & 3) << 6) | enc4;

    result += String.fromCharCode(chr1);
    if (enc3 !== 64) result += String.fromCharCode(chr2);
    if (enc4 !== 64) result += String.fromCharCode(chr3);
  }

  return result;
}

function parseTTMLTime(value) {
  if (!value) return -1;
  value = value.trim();

  // Format: "12.3s" (seconds with s suffix)
  if (value.charAt(value.length - 1) === "s" || value.charAt(value.length - 1) === "S") {
    var secs = parseFloat(value.substring(0, value.length - 1));
    if (isNaN(secs)) return -1;
    return Math.round(secs * 1000);
  }

  var parts = value.split(":");
  var hours = 0, minutes = 0, seconds = 0;

  if (parts.length === 3) {
    hours = parseInt(parts[0], 10);
    minutes = parseInt(parts[1], 10);
    seconds = parseFloat(parts[2].replace(",", "."));
  } else if (parts.length === 2) {
    minutes = parseInt(parts[0], 10);
    seconds = parseFloat(parts[1].replace(",", "."));
  } else {
    seconds = parseFloat(parts[0].replace(",", "."));
  }

  if (isNaN(hours) || isNaN(minutes) || isNaN(seconds)) return -1;
  return Math.round((hours * 3600 + minutes * 60 + seconds) * 1000);
}

function msToInlineLRC(ms) {
  if (ms < 0) return "";
  var totalSec = ms / 1000;
  var min = Math.floor(totalSec / 60);
  var sec = totalSec - min * 60;
  var mm = min < 10 ? "0" + min : "" + min;
  var ss = sec < 10 ? "0" + sec.toFixed(2) : sec.toFixed(2);
  return "<" + mm + ":" + ss + ">";
}

function extractAttr(tag, attrName) {
  // Handle both ns:attr and plain attr
  var patterns = [
    new RegExp('\\b' + attrName + '="([^"]*)"'),
    new RegExp('\\b' + attrName + "='([^']*)'")
  ];
  for (var i = 0; i < patterns.length; i++) {
    var m = tag.match(patterns[i]);
    if (m) return m[1];
  }
  return null;
}

function decodeXMLEntities(text) {
  if (!text) return "";
  return text
    .replace(/&amp;/g, "&")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&apos;/g, "'")
    .replace(/&#(\d+);/g, function (m, code) {
      return String.fromCharCode(parseInt(code, 10));
    })
    .replace(/&#x([0-9a-fA-F]+);/g, function (m, code) {
      return String.fromCharCode(parseInt(code, 16));
    });
}

function stripXMLTags(str) {
  return str.replace(/<[^>]+>/g, "");
}

function extractNestedSpan(str, role) {
  var searchStr = 'ttm:role="' + role + '"';
  var altSearchStr = "ttm:role='" + role + "'";
  var idx = str.indexOf(searchStr);
  if (idx === -1) idx = str.indexOf(altSearchStr);
  if (idx === -1) return null;

  // Find the beginning of this <span> tag
  var tagStart = str.lastIndexOf("<span", idx);
  if (tagStart === -1) return null;

  // Find the end of the opening tag
  var tagEnd = str.indexOf(">", idx);
  if (tagEnd === -1) return null;
  tagEnd++; // past the '>'

  var openTag = str.substring(tagStart, tagEnd);
  var contentStart = tagEnd;

  // Track nesting to find matching </span>
  var depth = 1;
  var pos = contentStart;
  while (pos < str.length && depth > 0) {
    var nextOpen = str.indexOf("<span", pos);
    var nextClose = str.indexOf("</span>", pos);

    if (nextClose === -1) break;

    if (nextOpen !== -1 && nextOpen < nextClose) {
      depth++;
      pos = nextOpen + 5; // past "<span"
    } else {
      depth--;
      if (depth === 0) {
        return {
          start: tagStart,
          end: nextClose + 7, // past "</span>"
          inner: str.substring(contentStart, nextClose),
          openTag: openTag
        };
      }
      pos = nextClose + 7;
    }
  }

  return null;
}

function collectRoleSpans(content) {
  var results = [];
  var re = /<span\s+([^>]*ttm:role="(x-translation|x-roman)"[^>]*)>([^<]*)<\/span>/gi;
  var m;
  while ((m = re.exec(content)) !== null) {
    var lang = "";
    var langM = m[1].match(/xml:lang="([^"]*)"/);
    if (langM) lang = langM[1].toLowerCase();
    results.push({
      role: m[2],
      lang: lang,
      text: decodeXMLEntities(m[3]).trim()
    });
  }
  return results;
}

function removeRoleSpans(content) {
  return content.replace(/<span\s+[^>]*ttm:role="(?:x-translation|x-roman)"[^>]*>[^<]*<\/span>/gi, "");
}

function parseTTML(ttml) {
  if (!ttml) return null;

  var result = {
    lines: [],
    headerTranslations: {},
    headerTransliterations: {},
    timingMode: "Word"
  };

  // Detect timing mode from root <tt> element
  var ttMatch = ttml.match(/<tt\s[^>]*>/);
  if (ttMatch) {
    var timing = extractAttr(ttMatch[0], "itunes:timing");
    if (timing) result.timingMode = timing;
  }

  // ---- Parse header translations/transliterations ----
  var headMatch = ttml.match(/<head[^>]*>([\s\S]*?)<\/head>/i);
  if (headMatch) {
    var headContent = headMatch[1];

    // Extract translations from <iTunesMetadata> or similar container
    // <translation ...><text for="L1">translated text</text></translation>
    var translationBlocks = headContent.match(/<translation\b[^>]*>([\s\S]*?)<\/translation>/gi);
    if (translationBlocks) {
      for (var ti = 0; ti < translationBlocks.length; ti++) {
        var block = translationBlocks[ti];
        var blockLang = extractAttr(block.match(/<translation[^>]*>/)[0], "xml:lang") || "";

        // Check if this translation matches the user's preferred language
        if (state.lyricsTranslation && blockLang.toLowerCase().indexOf(state.lyricsTranslation) !== 0) {
          continue; // Skip non-matching languages
        }

        var textEntries = block.match(/<text\b[^>]*>[\s\S]*?<\/text>/gi);
        if (textEntries) {
          for (var tj = 0; tj < textEntries.length; tj++) {
            var textTag = textEntries[tj];
            var forKey = extractAttr(textTag.match(/<text[^>]*>/)[0], "for");
            if (forKey) {
              // Strip inner tags and get plain text
              var innerText = textTag.replace(/^<text[^>]*>/, "").replace(/<\/text>$/, "");
              // Handle background vocal text inside <span ttm:role="x-bg">
              var bgMatch = innerText.match(/<span[^>]*ttm:role="x-bg"[^>]*>([\s\S]*?)<\/span>/i);
              var mainText = innerText;
              if (bgMatch) {
                mainText = innerText.replace(bgMatch[0], "");
              }
              result.headerTranslations[forKey] = decodeXMLEntities(stripXMLTags(mainText)).trim();
            }
          }
        }
      }
    }

    // Extract transliterations
    var translitBlocks = headContent.match(/<transliteration\b[^>]*>([\s\S]*?)<\/transliteration>/gi);
    if (translitBlocks) {
      for (var ri = 0; ri < translitBlocks.length; ri++) {
        var rBlock = translitBlocks[ri];
        var rBlockLang = extractAttr(rBlock.match(/<transliteration[^>]*>/)[0], "xml:lang") || "";

        if (state.lyricsPronunciation && rBlockLang.toLowerCase().indexOf(state.lyricsPronunciation) !== 0) {
          continue;
        }

        var rTextEntries = rBlock.match(/<text\b[^>]*>[\s\S]*?<\/text>/gi);
        if (rTextEntries) {
          for (var rj = 0; rj < rTextEntries.length; rj++) {
            var rTextTag = rTextEntries[rj];
            var rForKey = extractAttr(rTextTag.match(/<text[^>]*>/)[0], "for");
            if (rForKey) {
              var rInnerText = rTextTag.replace(/^<text[^>]*>/, "").replace(/<\/text>$/, "");
              var rBgMatch = rInnerText.match(/<span[^>]*ttm:role="x-bg"[^>]*>([\s\S]*?)<\/span>/i);
              var rMainText = rInnerText;
              if (rBgMatch) {
                rMainText = rInnerText.replace(rBgMatch[0], "");
              }
              result.headerTransliterations[rForKey] = decodeXMLEntities(stripXMLTags(rMainText)).trim();
            }
          }
        }
      }
    }
  }

  // ---- Parse body: extract <p> lines ----
  var bodyMatch = ttml.match(/<body[^>]*>([\s\S]*?)<\/body>/i);
  if (!bodyMatch) return result;

  var bodyContent = bodyMatch[1];

  // Extract all <p> elements (may be nested in <div>)
  var pPattern = /<p\s([^>]*)>([\s\S]*?)<\/p>/gi;
  var pMatch;
  while ((pMatch = pPattern.exec(bodyContent)) !== null) {
    var pAttrs = pMatch[1];
    var pContent = pMatch[2];

    var lineStartMs = parseTTMLTime(extractAttr("<p " + pAttrs + ">", "begin"));
    var lineEndMs = parseTTMLTime(extractAttr("<p " + pAttrs + ">", "end"));
    var lineKey = extractAttr("<p " + pAttrs + ">", "itunes:key") || "";
    var lineAgent = extractAttr("<p " + pAttrs + ">", "ttm:agent") || "";

    var line = {
      startMs: lineStartMs,
      endMs: lineEndMs,
      key: lineKey,
      agent: lineAgent,
      syllables: [],
      translation: "",
      roman: "",
      bgSyllables: [],
      bgTranslation: "",
      bgRoman: "",
      plainText: ""
    };

    // First, extract background vocal span using nesting-aware extraction.
    // bg spans can contain nested <span> tags, so regex alone won't work.
    var mainContent = pContent;
    var bgContent = "";
    var bgExtracted = extractNestedSpan(pContent, "x-bg");
    if (bgExtracted) {
      bgContent = bgExtracted.inner;
      mainContent = pContent.substring(0, bgExtracted.start) +
                    pContent.substring(bgExtracted.end);
    }

    // Collect all role-based spans from main content (don't modify while iterating).
    var roleSpans = collectRoleSpans(mainContent);
    for (var ri = 0; ri < roleSpans.length; ri++) {
      var rs = roleSpans[ri];
      if (rs.role === "x-translation") {
        if (!state.lyricsTranslation || rs.lang.indexOf(state.lyricsTranslation) === 0) {
          line.translation = rs.text;
        }
      } else if (rs.role === "x-roman") {
        if (!state.lyricsPronunciation || rs.lang.indexOf(state.lyricsPronunciation) === 0) {
          line.roman = rs.text;
        }
      }
    }

    // Remove role spans from mainContent for syllable extraction
    mainContent = removeRoleSpans(mainContent);

    // Extract timed syllable spans from main content
    var timedSpanRe = /<span\s+([^>]*)>([^<]*)<\/span>/gi;
    var tsMatch;
    var tsPrevEnd = -1;
    while ((tsMatch = timedSpanRe.exec(mainContent)) !== null) {
      // Apple separates words with whitespace text nodes between the word
      // spans. The regex only captures span contents, so preserve that gap as
      // a trailing space on the previous syllable; otherwise words run
      // together (e.g. "Brownguiltyeyes"). Syllables within a single word have
      // no gap and stay joined.
      if (tsPrevEnd >= 0 && line.syllables.length > 0) {
        var gap = decodeXMLEntities(mainContent.substring(tsPrevEnd, tsMatch.index));
        if (/\s/.test(gap)) {
          var prevSyl = line.syllables[line.syllables.length - 1];
          if (!/\s$/.test(prevSyl.text)) prevSyl.text += " ";
        }
      }
      tsPrevEnd = timedSpanRe.lastIndex;

      var sTag = "<span " + tsMatch[1] + ">";
      var sBegin = parseTTMLTime(extractAttr(sTag, "begin"));
      var sEnd = parseTTMLTime(extractAttr(sTag, "end"));
      var sText = decodeXMLEntities(tsMatch[2]);

      if (sBegin >= 0) {
        line.syllables.push({ startMs: sBegin, endMs: sEnd, text: sText });
      } else if (sText.trim()) {
        // Untimed span — just text
        line.syllables.push({ startMs: -1, endMs: -1, text: sText });
      }
    }

    // If no syllable spans found, get plain text from content
    if (line.syllables.length === 0) {
      var cleanText = decodeXMLEntities(stripXMLTags(mainContent)).trim();
      cleanText = cleanText.replace(/\s+/g, " ");
      if (cleanText) {
        line.plainText = cleanText;
      }
    } else {
      // Build plain text from syllables
      var pt = [];
      for (var si = 0; si < line.syllables.length; si++) {
        pt.push(line.syllables[si].text);
      }
      line.plainText = pt.join("").replace(/\s+/g, " ").trim();
    }

    // Process background vocals
    if (bgContent) {
      var bgRoles = collectRoleSpans(bgContent);
      for (var bri = 0; bri < bgRoles.length; bri++) {
        var br = bgRoles[bri];
        if (br.role === "x-translation") {
          if (!state.lyricsTranslation || br.lang.indexOf(state.lyricsTranslation) === 0) {
            line.bgTranslation = br.text;
          }
        } else if (br.role === "x-roman") {
          if (!state.lyricsPronunciation || br.lang.indexOf(state.lyricsPronunciation) === 0) {
            line.bgRoman = br.text;
          }
        }
      }

      var bgClean = removeRoleSpans(bgContent);
      var bgTimedRe = /<span\s+([^>]*)>([^<]*)<\/span>/gi;
      var bgTsMatch;
      var bgPrevEnd = -1;
      while ((bgTsMatch = bgTimedRe.exec(bgClean)) !== null) {
        if (bgPrevEnd >= 0 && line.bgSyllables.length > 0) {
          var bgGap = decodeXMLEntities(bgClean.substring(bgPrevEnd, bgTsMatch.index));
          if (/\s/.test(bgGap)) {
            var prevBg = line.bgSyllables[line.bgSyllables.length - 1];
            if (!/\s$/.test(prevBg.text)) prevBg.text += " ";
          }
        }
        bgPrevEnd = bgTimedRe.lastIndex;

        var bgTag = "<span " + bgTsMatch[1] + ">";
        var bgBegin = parseTTMLTime(extractAttr(bgTag, "begin"));
        var bgEnd = parseTTMLTime(extractAttr(bgTag, "end"));
        var bgText = decodeXMLEntities(bgTsMatch[2]);
        if (bgBegin >= 0) {
          line.bgSyllables.push({ startMs: bgBegin, endMs: bgEnd, text: bgText });
        }
      }
    }

    // Fall back to header translations/transliterations if inline not found
    if (!line.translation && lineKey && result.headerTranslations[lineKey]) {
      line.translation = result.headerTranslations[lineKey];
    }
    if (!line.roman && lineKey && result.headerTransliterations[lineKey]) {
      line.roman = result.headerTransliterations[lineKey];
    }

    result.lines.push(line);
  }

  return result;
}

function ttmlToLyricsResult(parsed) {
  if (!parsed || !parsed.lines || parsed.lines.length === 0) {
    return null;
  }

  var lines = [];
  var plainParts = [];
  var hasTranslation = false;
  var hasRoman = false;
  var translationLines = [];
  var romanLines = [];

  for (var i = 0; i < parsed.lines.length; i++) {
    var line = parsed.lines[i];
    if (line.startMs < 0) continue;

    var words = "";

    // Build word-by-word content with inline timestamps
    if (line.syllables.length > 0) {
      var parts = [];
      for (var s = 0; s < line.syllables.length; s++) {
        var syl = line.syllables[s];
        var chunk = "";
        if (syl.startMs >= 0) {
          chunk += msToInlineLRC(syl.startMs);
        }
        chunk += syl.text;
        if (syl.endMs >= 0 && s === line.syllables.length - 1) {
          // Add end time marker for last syllable
          chunk += msToInlineLRC(syl.endMs);
        }
        parts.push(chunk);
      }
      words = parts.join("");
    } else {
      words = line.plainText || "";
    }

    if (!words.trim()) continue;

    // Add background vocals as [bg:...] tag
    if (line.bgSyllables.length > 0) {
      var bgParts = [];
      for (var b = 0; b < line.bgSyllables.length; b++) {
        var bgSyl = line.bgSyllables[b];
        var bgChunk = "";
        if (bgSyl.startMs >= 0) {
          bgChunk += msToInlineLRC(bgSyl.startMs);
        }
        bgChunk += bgSyl.text;
        if (bgSyl.endMs >= 0 && b === line.bgSyllables.length - 1) {
          bgChunk += msToInlineLRC(bgSyl.endMs);
        }
        bgParts.push(bgChunk);
      }
      words += "\n[bg:" + bgParts.join("") + "]";
    }

    lines.push({
      startTimeMs: line.startMs,
      words: words,
      endTimeMs: line.endMs
    });

    plainParts.push(line.plainText || words);

    // Collect translation lines
    if (line.translation && state.lyricsTranslation) {
      hasTranslation = true;
      translationLines.push({
        startTimeMs: line.startMs,
        words: line.translation,
        endTimeMs: line.endMs
      });
    }

    // Collect pronunciation/romanization lines
    if (line.roman && state.lyricsPronunciation) {
      hasRoman = true;
      romanLines.push({
        startTimeMs: line.startMs,
        words: line.roman,
        endTimeMs: line.endMs
      });
    }
  }

  if (lines.length === 0) return null;

  // Apple serves only plain text for some tracks (itunes:timing="None"), sometimes with every
  // line stamped 0. Reporting that as LINE_SYNCED made every line "[00:00.00]". Several lines
  // that all start at the same moment carry no timing, so they are reported as UNSYNCED.
  var hasRealTiming = String(parsed.timingMode || "").toLowerCase() !== "none";
  if (hasRealTiming && lines.length > 1) {
    hasRealTiming = false;
    for (var ti = 1; ti < lines.length; ti++) {
      if (lines[ti].startTimeMs !== lines[0].startTimeMs) { hasRealTiming = true; break; }
    }
  }

  // Append translation lines after main lyrics (with blank separator)
  if (hasTranslation && translationLines.length > 0) {
    // Add separator
    lines.push({ startTimeMs: 999999999, words: "", endTimeMs: 999999999 });
    for (var tl = 0; tl < translationLines.length; tl++) {
      lines.push(translationLines[tl]);
    }
  }

  // Append pronunciation lines
  if (hasRoman && romanLines.length > 0) {
    lines.push({ startTimeMs: 999999999, words: "", endTimeMs: 999999999 });
    for (var rl = 0; rl < romanLines.length; rl++) {
      lines.push(romanLines[rl]);
    }
  }

  return {
    lines: lines,
    syncType: hasRealTiming ? "LINE_SYNCED" : "UNSYNCED",
    instrumental: false,
    plainLyrics: plainParts.join("\n"),
    provider: "Apple Music"
  };
}

function fetchLyrics(trackName, artistName, albumName, durationSec) {
  if (!state.mediaUserToken) {
    log.debug("fetchLyrics: No Media User Token configured, skipping.");
    return null;
  }

  var lyricsCacheKey = scopedCacheKey(
    "lyrics",
    normalizeText(trackName) + "|" + normalizeText(artistName) + "|" +
    normalizeText(albumName) + "|" + Math.round(Number(durationSec || 0)) + "|" +
    state.lyricsTranslation + "|" + state.lyricsPronunciation
  );
  var cachedLyrics = cacheGet(lyricsCacheKey);
  if (cachedLyrics === CACHE_MISS) return null;
  if (cachedLyrics) return cachedLyrics;

  log.info("fetchLyrics: Searching for", trackName, "by", artistName);
  var trackId = findTrackId(trackName, artistName, albumName, durationSec);
  if (!trackId) {
    log.info("fetchLyrics: Could not find track on Apple Music.");
    return rememberCacheMiss(lyricsCacheKey);
  }

  log.info("fetchLyrics: Found Apple Music track ID:", trackId);
  var lyricsData = apiGetWithUserToken("songs/" + trackId + "/syllable-lyrics");
  if (!lyricsData || !lyricsData.data || lyricsData.data.length === 0) {
    log.info("fetchLyrics: No syllable lyrics available for track", trackId);
    lyricsData = apiGetWithUserToken("songs/" + trackId + "/lyrics");
    if (!lyricsData || !lyricsData.data || lyricsData.data.length === 0) {
      log.info("fetchLyrics: No lyrics available for track", trackId);
      return rememberCacheMiss(lyricsCacheKey);
    }
  }

  var attrs = lyricsData.data[0].attributes;
  var ttml = attrs ? attrs.ttml || null : null;
  if (!ttml) {
    log.info("fetchLyrics: No TTML content in lyrics response.");
    return rememberCacheMiss(lyricsCacheKey);
  }

  log.info("fetchLyrics: Got TTML lyrics (" + ttml.length + " bytes), parsing...");
  var parsed = parseTTML(ttml);
  if (!parsed || parsed.lines.length === 0) {
    log.info("fetchLyrics: TTML parsing returned no lines.");
    return rememberCacheMiss(lyricsCacheKey);
  }

  log.info("fetchLyrics: Parsed " + parsed.lines.length + " lines (timing: " + parsed.timingMode + ")");
  var result = ttmlToLyricsResult(parsed);
  if (result) {
    log.info("fetchLyrics: Returning " + result.lines.length + " lyrics lines" +
      (state.lyricsTranslation ? " (with translation)" : "") +
      (state.lyricsPronunciation ? " (with pronunciation)" : ""));
    return cacheSet(lyricsCacheKey, result, LYRICS_CACHE_TTL_MS);
  }
  return rememberCacheMiss(lyricsCacheKey);
}

function findTrackId(trackName, artistName, albumName, durationSec) {
  var searchTerm = ((trackName || "") + " " + (artistName || "")).trim();
  if (!searchTerm) return null;

  try {
    var songs = searchAppleSongs(searchTerm, 10);
    var best = findBestMatch(
      songs,
      trackName,
      artistName,
      albumName,
      Number(durationSec || 0) * 1000,
      ""
    );
    return best && best.id ? best.id : null;
  } catch (e) {
    log.debug("findTrackId: Search failed:", e.message);
    return null;
  }
}

var __upstream_initialize = initialize;
var __upstream_cleanup = cleanup;
var __upstream_getArtist = getArtist;
var __upstream_getAlbum = getAlbum;
var __upstream_fetchLyrics = fetchLyrics;

function __artworkOnly(value) {
  if (!value || typeof value !== "object") return value;
  if (value.success === false || value.error) return value;
  var item = value.artist_info || value.album_info || value.artist || value.album || value;
  var output = {};
  ["id", "name", "image_url", "images", "cover_url", "header_image", "header_video", "header_logo"].forEach(function(key) {
    if (typeof item[key] !== "undefined") output[key] = item[key];
  });
  return output;
}
var __internalSource = {
  getArtistArtwork: function(id) { return __artworkOnly(__upstream_getArtist(id)); }
};
__internalSource.initialize = __upstream_initialize;
__internalSource.cleanup = __upstream_cleanup;
__internalSource.getAlbumArtwork = function(id) { return __artworkOnly(__upstream_getAlbum(id)); };
__internalSource.fetchLyrics = __upstream_fetchLyrics;
registerExtension(__internalSource);
