// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/qobuz-web/index.js
// Inactive source import: no app integration or update trust policy is installed.

var CONFIG = {
  apiBaseURL: "https://api.zarz.moe/v2/qbz",
  fallbackApiBaseURL: "",
  appID: "798273057",
  previewApiBaseURL: "https://www.qobuz.com",
  previewAppID: "712109809",
  previewAppSecret: "589be88e4538daea11f509d29e4a23b1",
  widgetAppID: "735532640",
  storeBaseURL: "https://www.qobuz.com/us-en",
  openBaseURL: "https://open.qobuz.com",
  playBaseURL: "https://play.qobuz.com",
  countryCode: "US",
  maxArtistAlbums: 100,
  pageSize: 50,
  metadataCacheTtlMs: 5 * 60 * 1000,
  searchCacheTtlMs: 60 * 1000,
  negativeCacheTtlMs: 30 * 1000,
  previewCacheTtlMs: 60 * 60 * 1000,
  metadataCacheMaxEntries: 500,
  maxDownloadAttempts: 5,
  metadataAttempts: 3,
  retryBaseDelayMs: 250,
  retryMaxDelayMs: 4000,
  downloadProviders: [
    { name: "zarz-v2", url: "/dl/qbz" }
  ],
  customEndpoint: "",
  customEndpointApiKey: ""
};

var DEFAULT_DOWNLOAD_PROVIDERS = CONFIG.downloadProviders.slice();

var IMAGE_SIZE_REGEX = /_\d+\.jpg$/;

var METADATA_CACHE = new Map();

function initialize(settings) {
  settings = settings || {};

  // V2 metadata is signed and bound to the manifest baseUrl. Ignore persisted
  // V1 API URL settings so upgrades cannot silently fall back to /v1.

  var appID = String(settings.appId || "").trim();
  if (appID) {
    CONFIG.appID = appID;
  }

  var countryCode = String(settings.countryCode || "").trim().toUpperCase();
  if (countryCode) {
    CONFIG.countryCode = countryCode;
  }

  // A user-hosted qobuz-rest-api compatible server is tried before the default API.
  CONFIG.customEndpoint = normalizeCustomEndpoint(settings.customEndpoint);
  CONFIG.customEndpointApiKey = String(settings.customEndpointApiKey || "").trim();
  CONFIG.downloadProviders = (CONFIG.customEndpoint ? [{ name: "custom", custom: true }] : [])
    .concat(DEFAULT_DOWNLOAD_PROVIDERS);

  return true;
}

function normalizeCustomEndpoint(value) {
  var text = String(value || "").trim();
  if (!/^https?:\/\/[^\/?#]+/i.test(text)) return "";
  return text.replace(/[?#].*$/, "").replace(/\/+$/, "");
}

function cleanup() {
  METADATA_CACHE.clear();
  return true;
}

function firstNonEmpty() {
  for (var i = 0; i < arguments.length; i++) {
    var value = String(arguments[i] || "").trim();
    if (value) return value;
  }
  return "";
}

function uniquePush(target, value, seen) {
  var text = String(value || "").trim();
  if (!text) return;
  var key = text.toLowerCase();
  if (seen[key]) return;
  seen[key] = true;
  target.push(text);
}

function getHeaderValue(headers, name) {
  if (!headers) return "";
  var lower = String(name || "").toLowerCase();
  for (var key in headers) {
    if (!headers.hasOwnProperty(key)) continue;
    if (String(key).toLowerCase() === lower) {
      return String(headers[key] || "");
    }
  }
  return "";
}

function summarizeErrorBody(body) {
  var text = String(body || "").trim();
  if (!text) return "";
  try {
    var parsed = JSON.parse(text);
    if (parsed && typeof parsed === "object") {
      text = String(parsed.error || parsed.message || parsed.detail || JSON.stringify(parsed));
    }
  } catch (e) {
    // Keep the raw text.
  }
  text = text.replace(/\s+/g, " ").trim();
  if (text.length > 180) {
    text = text.substring(0, 177) + "...";
  }
  return text ? ": " + text : "";
}

function throwIfVerificationRequired(response) {
  if (response && response.needsVerification) {
    var verificationError = new Error("VERIFY_REQUIRED");
    verificationError.needsVerification = true;
    verificationError.authUrl = response.auth_url || response.open_auth_url || "";
    throw verificationError;
  }
}

function signedJSON(method, path, body, headers) {
  if (typeof session === "undefined" || !session || typeof session.signedFetch !== "function") {
    throw new Error("signed session runtime is not available");
  }
  var response = session.signedFetch(method, path, body || null, headers || {});
  throwIfVerificationRequired(response);
  if (!response || response.error) {
    var error = response && response.error ? response.error : "signed request failed";
    var signedError = new Error(error);
    signedError.retryAfterMs = retryAfterMilliseconds(response);
    signedError.retryMode = response && response.retryMode ? String(response.retryMode) : "";
    signedError.retryable = !!(response && response.retryable);
    signedError.code = response && response.code ? String(response.code) : "";
    throw signedError;
  }
  if (response.statusCode !== 200) {
    var statusError = new Error("HTTP " + response.statusCode + " for " + path + summarizeErrorBody(response.body));
    statusError.retryAfterMs = retryAfterMilliseconds(response);
    statusError.retryMode = response.retryMode ? String(response.retryMode) : "";
    statusError.retryable = !!response.retryable;
    statusError.code = response.code ? String(response.code) : "";
    throw statusError;
  }
  return JSON.parse(response.body || "{}");
}

function retryAfterMilliseconds(response) {
  var raw = getHeaderValue(response && response.headers, "Retry-After").trim();
  if (!raw) {
    var seconds = Number(response && response.retryAfterSeconds || 0);
    return seconds > 0 ? Math.round(seconds * 1000) : 0;
  }
  if (/^\d+(?:\.\d+)?$/.test(raw)) return Math.max(0, Math.round(Number(raw) * 1000));
  var timestamp = Date.parse(raw);
  return isNaN(timestamp) ? 0 : Math.max(0, timestamp - Date.now());
}

function waitBeforeRetry(attempt, retryAfterMs) {
  var exponential = Math.min(
    CONFIG.retryBaseDelayMs * Math.pow(2, Math.max(0, attempt)),
    CONFIG.retryMaxDelayMs
  );
  var delay = Math.max(exponential, Number(retryAfterMs || 0));
  delay += Math.floor(Math.random() * Math.max(25, Math.floor(exponential / 4)));
  if (utils && typeof utils.sleep === "function") return utils.sleep(delay);
  return true;
}

function isVerificationRequiredError(error) {
  var message = String(error && error.message || error || "");
  return message.indexOf("VERIFY_REQUIRED") >= 0 || message.indexOf("verification_required") >= 0;
}

function withPrefix(id) {
  var raw = String(id || "").trim();
  if (!raw) return "";
  return raw.indexOf("qobuz:") === 0 ? raw : "qobuz:" + raw;
}

function parseNumericID(value, resourceType) {
  var raw = String(value || "").trim();
  if (!raw) return "";

  var direct = raw.match(/^\d+$/);
  if (direct) return direct[0];

  var prefixed = raw.match(/^qobuz:(\d+)$/i);
  if (prefixed) return prefixed[1];

  var pattern = new RegExp(resourceType + "\\/(\\d+)", "i");
  var match = raw.match(pattern);
  if (match) return match[1];

  return "";
}

function parseArtistID(value) {
  return parseNumericID(value, "interpreter");
}

function normalizeDate(value) {
  var text = String(value || "").trim();
  if (!text) return "";
  if (text.length >= 10) return text.substring(0, 10);
  return text;
}

function upscaleImageURL(url) {
  var text = String(url || "").trim();
  if (!text) return "";
  return text.replace(IMAGE_SIZE_REGEX, "_max.jpg");
}

function ensureNotCancelled() {
  return !!(utils && typeof utils.isDownloadCancelled === "function" && utils.isDownloadCancelled());
}

function metadataURL(path, params, useFallback) {
  var base = useFallback ? CONFIG.fallbackApiBaseURL : CONFIG.apiBaseURL;
  var query = [];
  params = params || {};

  for (var key in params) {
    if (!params.hasOwnProperty(key)) continue;
    var value = params[key];
    if (value === null || value === undefined || value === "") continue;
    query.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)));
  }

  if (!useFallback && CONFIG.appID) {
    query.push("app_id=" + encodeURIComponent(CONFIG.appID));
  }

  return base + "/" + String(path || "").replace(/^\/+/, "") + (query.length ? ("?" + query.join("&")) : "");
}

function previewTrackID(track) {
  if (!track) return "";
  if (track.previewable === false && track.sampleable === false && track.streamable === false) {
    return "";
  }
  return String(track.id || "").trim();
}

function deferredPreviewURL(track) {
  var trackID = previewTrackID(track);
  return trackID ? "mornye-preview:qobuz-web/" + encodeURIComponent(trackID) : "";
}

function shouldRetryMetadataError(error) {
  if (!error || isTerminalLookupError(error)) return false;
  if (error.retryable) return true;
  var message = String(error.message || error).toLowerCase();
  return /http (408|425|429|5\d\d)\b/.test(message) ||
    /timeout|timed out|temporar|network|connection|socket|reset|eof|unavailable/.test(message);
}

function getMetadataJSON(path, params, validator) {
  var primaryURL = metadataURL(path, params, false);
  var relative = primaryURL.replace(/^https:\/\/api\.zarz\.moe\/v2/i, "");
  var attempts = Math.max(1, Number(CONFIG.metadataAttempts || 1));
  var lastError = null;

  for (var attempt = 0; attempt < attempts; attempt++) {
    if (ensureNotCancelled()) throw new Error("download cancelled");
    try {
      var payload = signedJSON("GET", relative, null, {});
      if (typeof validator === "function" && !validator(payload)) {
        var shapeError = new Error("Metadata response missing expected payload for " + path);
        shapeError.retryable = true;
        throw shapeError;
      }
      return payload;
    } catch (e) {
      if (isVerificationRequiredError(e)) throw e;
      lastError = e;
      if (attempt + 1 >= attempts || !shouldRetryMetadataError(e)) throw e;
      waitBeforeRetry(attempt, e.retryAfterMs);
    }
  }

  throw lastError || new Error("Metadata request failed for " + path);
}

function trackDisplayTitle(track) {
  if (!track) return "";
  var title = String(track.title || "").trim();
  var version = String(track.version || "").trim();
  if (!title || !version) return title;
  if (title.toLowerCase().indexOf(version.toLowerCase()) >= 0) return title;
  return title + " (" + version + ")";
}

function albumDisplayTitle(album) {
  if (!album) return "";
  var title = String(album.title || "").trim();
  var version = String(album.version || "").trim();
  if (!title || !version) return title;
  if (title.toLowerCase().indexOf(version.toLowerCase()) >= 0) return title;
  return title + " (" + version + ")";
}

function qobuzAlbumURL(album) {
  if (!album) return "";
  return firstNonEmpty(album.id ? CONFIG.openBaseURL + "/album/" + album.id : "", album.url);
}

function qobuzTrackURL(track) {
  return track && track.id ? CONFIG.openBaseURL + "/track/" + track.id : "";
}

function qobuzArtistURL(artist) {
  return artist && artist.id ? CONFIG.openBaseURL + "/artist/" + artist.id : "";
}

function releaseDateForAlbum(album) {
  if (!album) return "";
  return normalizeDate(firstNonEmpty(
    album.release_date_download,
    album.release_date_stream,
    album.release_date_original,
    album.release_date_purchase
  ));
}

function creditNamesForRoles(rawCredits, rolePattern) {
  var names = [];
  var seen = {};
  var groups = String(rawCredits || "").split(/\s+-\s+/);
  for (var i = 0; i < groups.length; i++) {
    var parts = String(groups[i] || "").split(/\s*,\s*/);
    if (parts.length < 2) continue;
    var name = String(parts.shift() || "").trim();
    var roles = parts.join(",");
    if (name && rolePattern.test(roles)) uniquePush(names, name, seen);
  }
  return names;
}

function trackComposerNames(track) {
  var names = [];
  var seen = {};
  uniquePush(names, track && track.composer && track.composer.name, seen);
  var parsed = creditNamesForRoles(
    track && track.performers,
    /(composer|writer|lyricist)/i
  );
  for (var i = 0; i < parsed.length; i++) uniquePush(names, parsed[i], seen);
  return names.join(", ");
}

function genreDisplayName(album) {
  return String(album && album.genre && (album.genre.full_name || album.genre.name) || "").trim();
}

function joinArtistNames(artists, fallback) {
  var names = [];
  var seen = {};
  artists = artists || [];
  for (var i = 0; i < artists.length; i++) {
    uniquePush(names, artists[i] && artists[i].name, seen);
  }
  if (names.length) return names.join(", ");
  return String(fallback || "").trim();
}

function trackArtistName(track) {
  if (!track) return "";
  var names = [];
  var seen = {};

  // Qobuz exposes only the primary performer in `performer`. Additional
  // credited artists live in the role-based `performers` string.
  uniquePush(names, track.performer && track.performer.name, seen);

  var artists = track.artists || [];
  for (var i = 0; i < artists.length; i++) {
    uniquePush(names, artists[i] && artists[i].name, seen);
  }

  var credited = creditNamesForRoles(
    track.performers,
    /(?:main|featured)[\s_-]*artist/i
  );
  for (var j = 0; j < credited.length; j++) {
    uniquePush(names, credited[j], seen);
  }

  if (!names.length) {
    uniquePush(names, track.album && track.album.artist && track.album.artist.name, seen);
  }
  return names.join(", ");
}

function trackAlbumArtist(track) {
  if (!track || !track.album) return "";
  return joinArtistNames(track.album.artists || [], track.album.artist && track.album.artist.name);
}

function albumTypeFromRelease(releaseType, productType, totalTracks) {
  var kind = String(releaseType || productType || "").trim().toLowerCase();
  switch (kind) {
    case "album":
    case "single":
    case "ep":
    case "compilation":
      return kind;
  }
  if (Number(totalTracks || 0) > 0 && Number(totalTracks || 0) <= 3) {
    return "single";
  }
  return "album";
}

function trackAlbumImage(track) {
  if (!track || !track.album) return "";
  return upscaleImageURL(firstNonEmpty(
    track.album.image && track.album.image.large,
    track.album.image && track.album.image.small,
    track.album.image && track.album.image.thumbnail
  ));
}

function albumImage(album) {
  if (!album) return "";
  return upscaleImageURL(firstNonEmpty(
    album.image && album.image.large,
    album.image && album.image.small,
    album.image && album.image.thumbnail
  ));
}

function artistImage(artist) {
  if (!artist) return "";
  return firstNonEmpty(
    artist.image && artist.image.large,
    artist.image && artist.image.small,
    artist.image && artist.image.thumbnail
  );
}

function qobuzAudioQualityLabel(track) {
  var bitDepth = Number(track.maximum_bit_depth || 0);
  var sampleRate = Number(track.maximum_sampling_rate || 0);
  if (bitDepth <= 0 || sampleRate <= 0) return "";
  var rateDisplay = sampleRate % 1 === 0 ? String(sampleRate) : sampleRate.toFixed(1);
  return bitDepth + "bit/" + rateDisplay + "kHz";
}

function formatTrack(track, totalDiscsOverride, options) {
  if (!track) return null;
  options = options || {};

  var album = track.album || {};
  var totalTracks = Number(album.tracks_count || 0);
  var totalDiscs = Number(totalDiscsOverride || 0);
  if (!totalDiscs) totalDiscs = Number(album.media_count || album.total_discs || 0);
  var albumURL = qobuzAlbumURL(album);
  var trackURL = qobuzTrackURL(track);
  var artist = track.performer || album.artist || {};

  var formatted = {
    id: withPrefix(track.id),
    name: trackDisplayTitle(track),
    artists: trackArtistName(track),
    artist_id: withPrefix(artist.id || ""),
    artist_url: qobuzArtistURL(artist),
    album_name: albumDisplayTitle(album),
    album_artist: trackAlbumArtist(track),
    album_id: withPrefix(album.id || ""),
    album_url: albumURL,
    duration_ms: Number(track.duration || 0) * 1000,
    cover_url: trackAlbumImage(track),
    images: trackAlbumImage(track),
    release_date: releaseDateForAlbum(album),
    track_number: Number(track.track_number || 0),
    total_tracks: totalTracks,
    disc_number: Number(track.media_number || 0),
    total_discs: totalDiscs,
    isrc: String(track.isrc || "").trim(),
    upc: String(album.upc || "").trim(),
    provider_id: "qobuz-web",
    item_type: "track",
    album_type: albumTypeFromRelease(
      album.release_type,
      album.product_type,
      totalTracks
    ),
    explicit: track.parental_warning === true,
    qobuz_id: String(track.id || "").trim(),
    external_urls: trackURL,
    external_links: {
      qobuz: trackURL,
      qobuz_track: trackURL,
      qobuz_album: albumURL,
      qobuz_store_album: String(album.url || "").trim()
    },
    label: String(album.label && album.label.name || "").trim(),
    genre: genreDisplayName(album),
    copyright: firstNonEmpty(track.copyright, album.copyright),
    composer: trackComposerNames(track),
    comment: albumURL,
    audio_quality: qobuzAudioQualityLabel(track)
  };

  if (options.includePreview) {
    var previewURL = deferredPreviewURL(track);
    if (previewURL) formatted.preview_url = previewURL;
  }

  return formatted;
}

function qobuzCollectionItems(collection) {
  if (!collection) return [];
  if (Array.isArray(collection)) return collection;
  return Array.isArray(collection.items) ? collection.items : [];
}

function artistTopTrackItems(artist) {
  if (!artist) return [];
  var candidates = [artist.top_tracks, artist.topTracks, artist.tracks];
  for (var i = 0; i < candidates.length; i++) {
    var items = qobuzCollectionItems(candidates[i]);
    if (items.length) return items;
  }
  return [];
}

function formatArtistAlbum(album) {
  if (!album) return null;
  return {
    id: withPrefix(album.id),
    name: albumDisplayTitle(album),
    artists: joinArtistNames(album.artists || [], album.artist && album.artist.name),
    cover_url: albumImage(album),
    images: albumImage(album),
    release_date: releaseDateForAlbum(album),
    total_tracks: Number(album.tracks_count || 0),
    album_url: qobuzAlbumURL(album),
    external_urls: qobuzAlbumURL(album),
    upc: String(album.upc || "").trim(),
    album_type: albumTypeFromRelease(album.release_type, album.product_type, album.tracks_count),
    tracks: [],
    provider_id: "qobuz-web",
    item_type: "album"
  };
}

function formatArtist(artist, albums) {
  albums = albums || [];
  var formattedAlbums = [];
  for (var i = 0; i < albums.length; i++) {
    var formattedAlbum = formatArtistAlbum(albums[i]);
    if (formattedAlbum) formattedAlbums.push(formattedAlbum);
  }

  var rawTopTracks = artistTopTrackItems(artist);
  var formattedTopTracks = [];
  for (var j = 0; j < rawTopTracks.length; j++) {
    var formattedTrack = formatTrack(rawTopTracks[j]);
    if (formattedTrack) formattedTopTracks.push(formattedTrack);
  }

  return {
    id: withPrefix(artist && artist.id || ""),
    name: String(artist && artist.name || "").trim(),
    image_url: artistImage(artist),
    header_image: artistImage(artist),
    cover_url: artistImage(artist),
    images: artistImage(artist),
    artist_url: qobuzArtistURL(artist),
    external_urls: qobuzArtistURL(artist),
    albums: formattedAlbums,
    releases: formattedAlbums,
    top_tracks: formattedTopTracks,
    provider_id: "qobuz-web",
    item_type: "artist"
  };
}

function fetchArtistAlbums(artistID) {
  var normalizedID = parseArtistID(artistID);
  if (!normalizedID) {
    throw new Error("Invalid Qobuz artist ID");
  }
  var payload = getMetadataJSON("artist/get", {
    artist_id: normalizedID,
    extra: "albums",
    limit: CONFIG.maxArtistAlbums,
    offset: 0
  });
  var albums = qobuzCollectionItems(payload && payload.albums);
  try {
    var artistPage = getMetadataJSON("artist/page", {
      artist_id: normalizedID
    });
    var topTracks = artistTopTrackItems(artistPage);
    if (topTracks.length) {
      payload.top_tracks = topTracks;
    }
  } catch (e) {
    // Popular tracks are optional. A failure here must not hide the artist's
    // valid profile and album catalogue.
    log.warn("[QobuzWeb] Artist popular tracks unavailable: " + e.message);
  }
  return {
    artist: payload,
    albums: albums
  };
}

function getArtist(artistID) {
  var payload = fetchArtistAlbums(artistID);
  return formatArtist(payload.artist, payload.albums);
}

function isTerminalLookupError(error) {
  return isVerificationRequiredError(error) || ensureNotCancelled() ||
    /cancelled|execution timeout exceeded/i.test(String(error && error.message || error));
}

var __upstream_initialize = initialize;
var __upstream_cleanup = cleanup;
var __upstream_getArtist = getArtist;

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

registerExtension(__internalSource);
