// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/soundcloud/index.js
// Inactive source import: no app integration or update trust policy is installed.

var SC_API = "https://api-v2.soundcloud.com";

var TRACK_CACHE = new Map();

var state = {
  clientId: null,
  clientIdExpiry: 0,
  scVersion: ""
};

function initialize(config) {
  log.info("[SC] SoundCloud Extension initializing...");

  try {
    var cached = storage.get("sc_state");
    if (cached) {
      var parsed = JSON.parse(cached);
      if (parsed.clientId && parsed.clientIdExpiry && Date.now() < parsed.clientIdExpiry) {
        state.clientId = parsed.clientId;
        state.clientIdExpiry = parsed.clientIdExpiry;
        state.scVersion = parsed.scVersion || "";
        log.info("[SC] Loaded cached client_id (expires in " +
          Math.round((state.clientIdExpiry - Date.now()) / 60000) + " min)");
      }
    }
  } catch (e) {
  }

  return true;
}

function cleanup() {
  TRACK_CACHE.clear();
  persistSoundCloudState();
}

function persistSoundCloudState() {
  try {
    storage.set("sc_state", JSON.stringify({
      clientId: state.clientId,
      clientIdExpiry: state.clientIdExpiry,
      scVersion: state.scVersion
    }));
  } catch (e) {}
}

function soundCloudResponseError(response) {
  if (!response) return "no response";
  if (response.error) return String(response.error);
  return response.statusCode ? "HTTP " + response.statusCode : "missing HTTP status";
}

function soundCloudGet(url, headers) {
  var response;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      response = http.get(url, headers);
    } catch (error) {
      response = { error: (error && error.message) || String(error) };
    }
    var reason = soundCloudResponseError(response);
    var retryable = !response || response.error || response.statusCode === 408 || response.statusCode >= 500;
    if (attempt === 1 || !retryable || /cancel|denied|not permitted|certificate/i.test(reason)) break;
    log.warn("[SC] Request retry after:", reason);
    if (typeof utils.sleep === "function" && utils.sleep(250) === false) {
      throw new Error("SoundCloud request cancelled");
    }
  }
  return response;
}

function fetchClientId() {
  log.info("[SC] Fetching SoundCloud client_id...");

  var response = soundCloudGet("https://soundcloud.com/", {
    "User-Agent": utils.randomUserAgent()
  });

  if (!response || response.error || response.statusCode !== 200) {
    throw new Error("Failed to fetch soundcloud.com: " + soundCloudResponseError(response));
  }

  var body = response.body || "";

  // Extract __sc_version for cache key
  var versionMatch = body.match(/__sc_version="(\d{10})"/);
  if (versionMatch) {
    var newVersion = versionMatch[1];
    if (newVersion === state.scVersion && state.clientId) {
      state.clientIdExpiry = Date.now() + (24 * 60 * 60 * 1000);
      persistSoundCloudState();
      log.info("[SC] SoundCloud version unchanged, reusing cached client_id");
      return;
    }
    state.scVersion = newVersion;
  }

  // Strategy 1: Look for client_id directly in HTML
  var directMatch = body.match(/["']?client_id["']?\s*[:=]\s*["']([a-zA-Z0-9]{32})["']/);
  if (directMatch) {
    state.clientId = directMatch[1];
    state.clientIdExpiry = Date.now() + (24 * 60 * 60 * 1000); // 24h
    persistSoundCloudState();
    log.info("[SC] Found client_id in HTML");
    return;
  }

  // Strategy 2: Extract from JS bundles at a-v2.sndcdn.com
  var scriptMatches = body.match(/src="(https:\/\/a-v2\.sndcdn\.com\/assets\/[^"]+\.js)"/g);
  if (!scriptMatches) {
    // Fallback: any script with sndcdn
    scriptMatches = body.match(/src="(https:\/\/[^"]*sndcdn\.com[^"]*\.js)"/g);
  }

  var lastBundleError = null;
  if (scriptMatches) {
    // Process from last to first (client_id is usually in later bundles)
    for (var i = scriptMatches.length - 1; i >= 0 && i >= scriptMatches.length - 8; i--) {
      var srcMatch = scriptMatches[i].match(/src="([^"]+)"/);
      if (!srcMatch) continue;

      var bundleURL = srcMatch[1];
      log.debug("[SC] Checking bundle:", bundleURL.substring(bundleURL.lastIndexOf("/") + 1));

      try {
        var bundleResp = soundCloudGet(bundleURL, {
          "User-Agent": utils.randomUserAgent()
        });

        if (bundleResp && !bundleResp.error && bundleResp.statusCode === 200) {
          var bundleBody = bundleResp.body || "";

          // Look for client_id pattern: client_id:"XXXX" or client_id=XXXX
          var cidMatch = bundleBody.match(/["']?client_id["']?\s*[:=]\s*["']([a-zA-Z0-9]{32})["']/);
          if (!cidMatch) {
            // Alternative pattern: ("client_id=XXXXX")
            cidMatch = bundleBody.match(/\("client_id=([a-zA-Z0-9]{32})"\)/);
          }
          if (!cidMatch) {
            // client_id=XXXXX within a string
            var idx = bundleBody.indexOf("client_id=");
            if (idx !== -1) {
              var start = idx + 10;
              var end = start;
              var chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789";
              while (end < bundleBody.length && end - start < 32 && chars.indexOf(bundleBody.charAt(end)) !== -1) {
                end++;
              }
              if (end - start === 32) {
                cidMatch = [null, bundleBody.substring(start, end)];
              }
            }
          }

          if (cidMatch) {
            state.clientId = cidMatch[1];
            state.clientIdExpiry = Date.now() + (24 * 60 * 60 * 1000);
            persistSoundCloudState();
            log.info("[SC] Found client_id in JS bundle");
            return;
          }
        } else {
          lastBundleError = soundCloudResponseError(bundleResp);
        }
      } catch (e) {
        lastBundleError = e.message || String(e);
        log.debug("[SC] Bundle fetch failed:", e.message);
      }
    }
  }

  throw new Error("Could not find SoundCloud client_id in page or JS bundles" +
    (lastBundleError ? ": " + lastBundleError : ""));
}

function ensureClientId() {
  if (!state.clientId || Date.now() >= state.clientIdExpiry) {
    fetchClientId();
  }
}

function scGet(path, extraParams) {
  ensureClientId();

  var sep = path.indexOf("?") === -1 ? "?" : "&";
  var url = SC_API + "/" + path + sep + "client_id=" + state.clientId;
  if (extraParams) {
    url += "&" + extraParams;
  }

  var response = soundCloudGet(url, {
    "User-Agent": utils.randomUserAgent(),
    "Accept": "application/json"
  });

  if (!response || response.error) {
    throw new Error("SoundCloud API failed: " + soundCloudResponseError(response));
  }

  if (response.statusCode === 401 || response.statusCode === 403) {
    // client_id may be invalid, try refreshing
    log.info("[SC] Authorization rejected, refreshing client_id...");
    state.clientId = null;
    state.clientIdExpiry = 0;
    ensureClientId();
    // Retry once
    sep = path.indexOf("?") === -1 ? "?" : "&";
    url = SC_API + "/" + path + sep + "client_id=" + state.clientId;
    if (extraParams) url += "&" + extraParams;
    response = soundCloudGet(url, {
      "User-Agent": utils.randomUserAgent(),
      "Accept": "application/json"
    });
    if (!response || response.error || response.statusCode !== 200) {
      throw new Error("SoundCloud API failed after retry: " + soundCloudResponseError(response));
    }
  }

  if (response.statusCode !== 200) {
    throw new Error("SoundCloud API returned HTTP " + response.statusCode);
  }

  return JSON.parse(response.body);
}

function hiResArtwork(url) {
  if (!url) return "";
  return url.replace("-large.", "-t500x500.");
}

function originalArtwork(url) {
  if (!url) return "";
  return url.replace("-large.", "-original.");
}

function formatTrack(track) {
  if (!track || !track.id) return null;

  var attr = track;
  var user = attr.user || {};
  var pub = attr.publisher_metadata || {};

  var artist = pub.artist || attr.metadata_artist || user.username || "";
  var albumName = pub.album_title || pub.release_title || "";

  // Build cover URL — prefer original, fallback to t500x500
  var coverURL = originalArtwork(attr.artwork_url);
  if (!coverURL && user.avatar_url) {
    coverURL = hiResArtwork(user.avatar_url);
  }

  return {
    id: String(attr.id),
    name: attr.title || "",
    artists: artist,
    album_name: albumName,
    album_artist: user.username || "",
    duration_ms: attr.full_duration || attr.duration || 0,
    cover_url: coverURL,
    images: coverURL,
    release_date: formatDate(attr.display_date || attr.created_at),
    track_number: 0,
    disc_number: 1,
    isrc: pub.isrc || attr.isrc || "",
    label: attr.label_name || "",
    copyright: pub.p_line_for_display || pub.c_line_for_display || "",
    genre: attr.genre || "",
    composer: pub.writer_composer || "",
    external_urls: attr.permalink_url || "",
    provider_id: "soundcloud",
    item_type: "track"
  };
}

function formatPlaylistOrAlbum(playlist) {
  if (!playlist || !playlist.id) return null;

  var user = playlist.user || {};
  var isAlbum = playlist.is_album || (playlist.set_type === "album") ||
                (playlist.set_type === "ep") || (playlist.set_type === "compilation") ||
                (playlist.set_type === "single");

  var coverURL = originalArtwork(playlist.artwork_url);
  if (!coverURL && user.avatar_url) {
    coverURL = hiResArtwork(user.avatar_url);
  }

  var albumType = playlist.set_type || (isAlbum ? "album" : "playlist");

  return {
    id: String(playlist.id),
    name: playlist.title || "",
    artists: user.username || "",
    artist_id: user.id ? String(user.id) : "",
    images: coverURL,
    cover_url: coverURL,
    release_date: formatDate(playlist.display_date || playlist.published_at || playlist.created_at),
    total_tracks: playlist.track_count || 0,
    album_type: albumType,
    record_label: playlist.label_name || "",
    genre: playlist.genre || "",
    external_urls: playlist.permalink_url || "",
    provider_id: "soundcloud",
    item_type: isAlbum ? "album" : "playlist"
  };
}

function formatUser(user) {
  if (!user || !user.id) return null;

  var avatarURL = originalArtwork(user.avatar_url);

  return {
    id: String(user.id),
    name: user.username || user.full_name || "",
    image_url: avatarURL,
    images: avatarURL,
    listeners: user.followers_count || 0,
    external_urls: user.permalink_url || "",
    provider_id: "soundcloud",
    item_type: "artist"
  };
}

function formatDate(dateStr) {
  if (!dateStr) return "";
  return dateStr.substring(0, 10);
}

function fetchArtist(userId) {
  log.info("[SC] Fetching artist:", userId);
  var userData = scGet("users/" + userId);
  var artistInfo = formatUser(userData);
  if (!artistInfo) throw new Error("Failed to format user");

  // Fetch top tracks
  var topTracks = [];
  try {
    var topData = scGet("users/" + userId + "/toptracks", "limit=20");
    var topItems = topData.collection || topData || [];
    if (Array.isArray(topItems)) {
      for (var i = 0; i < topItems.length; i++) {
        var t = formatTrack(topItems[i]);
        if (t) topTracks.push(t);
      }
    }
  } catch (e) {
    log.debug("[SC] Top tracks fetch failed:", e.message);
    // Fallback to recent tracks
    try {
      var recentData = scGet("users/" + userId + "/tracks", "limit=20");
      var recentItems = recentData.collection || recentData || [];
      if (Array.isArray(recentItems)) {
        for (var ri = 0; ri < recentItems.length; ri++) {
          var rt = formatTrack(recentItems[ri]);
          if (rt) topTracks.push(rt);
        }
      }
    } catch (e2) {
      log.debug("[SC] Recent tracks fetch failed:", e2.message);
    }
  }

  // Fetch albums
  var albums = [];
  try {
    var albumData = scGet("users/" + userId + "/albums", "limit=50");
    var albumItems = albumData.collection || albumData || [];
    if (Array.isArray(albumItems)) {
      for (var a = 0; a < albumItems.length; a++) {
        var albumInfo = formatPlaylistOrAlbum(albumItems[a]);
        if (albumInfo) albums.push(albumInfo);
      }
    }
  } catch (e) {
    log.debug("[SC] Albums fetch failed:", e.message);
  }

  return {
    type: "artist",
    artist: {
      id: artistInfo.id,
      name: artistInfo.name,
      image_url: artistInfo.image_url,
      listeners: artistInfo.listeners,
      albums: albums,
      top_tracks: topTracks,
      provider_id: "soundcloud"
    }
  };
}

function getArtist(artistId) {
  try {
    var result = fetchArtist(artistId);
    return result.artist;
  } catch (e) {
    log.error("[SC] getArtist failed:", e.message);
    return null;
  }
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
