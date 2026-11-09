// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/tidal-web/index.js
// Inactive source import: no app integration or update trust policy is installed.

var CONFIG = {
  apiBaseURL: "https://tidal.com/v1",
  resourceBaseURL: "https://resources.tidal.com",
  downloadAPIURL: "/dl/tid",
  publicToken: "49YxDN9a2aFV6RTG",
  countryCode: "US",
  locale: "en_US",
  deviceType: "BROWSER",
  mirrorBaseURLs: [],
  preferMirrors: false,
  maxAlbumItems: 1000,
  maxPlaylistTracks: 500,
  pageSize: 50,
  metadataCacheTtlMs: 5 * 60 * 1000,
  searchCacheTtlMs: 60 * 1000,
  metadataCacheMaxEntries: 500,
  maxDownloadAttempts: 5,
  retryBaseDelayMs: 250,
  retryMaxDelayMs: 4000
};

var METADATA_CACHE = new Map();

function metadataCacheGet(key) {
  var normalizedKey = String(key || "");
  var entry = METADATA_CACHE.get(normalizedKey);
  if (!entry) return null;
  if (Date.now() >= entry.expiresAt) {
    METADATA_CACHE.delete(normalizedKey);
    return null;
  }
  METADATA_CACHE.delete(normalizedKey);
  METADATA_CACHE.set(normalizedKey, entry);
  return entry.value;
}

function metadataCacheSet(key, value, ttlMs) {
  var normalizedKey = String(key || "");
  if (!normalizedKey || value === null || value === undefined) return value;
  if (METADATA_CACHE.has(normalizedKey)) METADATA_CACHE.delete(normalizedKey);
  METADATA_CACHE.set(normalizedKey, {
    value: value,
    expiresAt: Date.now() + Number(ttlMs || CONFIG.metadataCacheTtlMs)
  });
  while (METADATA_CACHE.size > CONFIG.metadataCacheMaxEntries) {
    METADATA_CACHE.delete(METADATA_CACHE.keys().next().value);
  }
  return value;
}

function initialize(settings) {
  settings = settings || {};
  var publicToken = String(settings.publicToken || "").trim();
  if (publicToken) {
    CONFIG.publicToken = publicToken;
  }

  var downloadAPIURL = normalizeMirrorBaseURL(settings.downloadApiUrl);
  if (downloadAPIURL.indexOf("https://api.zarz.moe/") === 0) {
    downloadAPIURL = CONFIG.downloadAPIURL;
  }
  if (downloadAPIURL) {
    CONFIG.downloadAPIURL = downloadAPIURL;
  }

  // A user-hosted hifi-api compatible server is tried before the default API.
  var customEndpoint = normalizeCustomEndpoint(settings.customEndpoint);
  CONFIG.mirrorBaseURLs = customEndpoint ? [customEndpoint] : [];
  CONFIG.preferMirrors = !!customEndpoint;

  var countryCode = String(settings.countryCode || "").trim().toUpperCase();
  if (countryCode) {
    CONFIG.countryCode = countryCode;
  }

  var locale = String(settings.locale || "").trim();
  if (locale) {
    CONFIG.locale = locale;
  }

  var deviceType = String(settings.deviceType || "").trim().toUpperCase();
  if (deviceType) {
    CONFIG.deviceType = deviceType;
  }

  return true;
}

function cleanup() {
  METADATA_CACHE.clear();
  return true;
}

function normalizeCustomEndpoint(value) {
  var text = String(value || "").trim();
  if (!/^https?:\/\/[^\/?#]+/i.test(text)) return "";
  return text.replace(/[?#].*$/, "").replace(/\/+$/, "");
}

function normalizeMirrorBaseURL(value) {
  var text = String(value || "").trim();
  if (!text) return "";
  if (text.indexOf("http://") === 0) {
    text = "https://" + text.substring("http://".length);
  }
  return text.replace(/\/+$/, "");
}

function appUserAgent() {
  if (utils && typeof utils.appUserAgent === "function") {
    return String(utils.appUserAgent() || "").trim() || "SpotiFLAC-Mobile";
  }
  return "SpotiFLAC-Mobile";
}

function requestUserAgent() {
  if (utils && typeof utils.randomUserAgent === "function") {
    return String(utils.randomUserAgent() || "").trim() || appUserAgent();
  }
  return appUserAgent();
}

function ensureHTTPS(url) {
  var text = String(url || "").trim();
  if (!text) return "";
  if (text.indexOf("http://") === 0) {
    return "https://" + text.substring("http://".length);
  }
  return text;
}

function withPrefix(id) {
  var raw = String(id || "").trim();
  if (!raw) return "";
  return raw.indexOf("tidal:") === 0 ? raw : "tidal:" + raw;
}

function normalizeDate(value) {
  var text = String(value || "").trim();
  if (!text) return "";
  if (text.length >= 10) return text.substring(0, 10);
  return text;
}

function imageURL(imageID, size) {
  var normalizedID = String(imageID || "").trim();
  var normalizedSize = String(size || "").trim();
  if (!normalizedID || !normalizedSize) return "";
  return CONFIG.resourceBaseURL + "/images/" + normalizedID.replace(/-/g, "/") + "/" + normalizedSize + ".jpg";
}

function joinArtistNames(artists) {
  if (!artists || !artists.length) return "";

  var names = [];
  for (var i = 0; i < artists.length; i++) {
    var artist = artists[i] || {};
    var name = String(artist.name || "").trim();
    if (!name) continue;
    names.push(name);
  }
  return names.join(", ");
}

function requestHeaders() {
  return {
    "Accept": "application/json",
    "User-Agent": requestUserAgent(),
    "x-tidal-token": CONFIG.publicToken
  };
}

function buildMetadataURL(path, extraQuery) {
  var normalizedPath = String(path || "").trim().replace(/^\/+/, "");
  var query = [];
  extraQuery = extraQuery || {};

  query.push("countryCode=" + encodeURIComponent(CONFIG.countryCode));
  query.push("locale=" + encodeURIComponent(CONFIG.locale));
  query.push("deviceType=" + encodeURIComponent(CONFIG.deviceType));

  for (var key in extraQuery) {
    if (!extraQuery.hasOwnProperty(key)) continue;
    var value = extraQuery[key];
    if (value === null || value === undefined || value === "") continue;
    query.push(encodeURIComponent(key) + "=" + encodeURIComponent(String(value)));
  }

  if (!query.length) {
    return CONFIG.apiBaseURL + "/" + normalizedPath;
  }

  var separator = "?";
  if (normalizedPath.indexOf("?") !== -1) {
    separator = /[?&]$/.test(normalizedPath) ? "" : "&";
  }

  return CONFIG.apiBaseURL + "/" + normalizedPath + separator + query.join("&");
}

function getJSON(url) {
  var response = http.get(url, requestHeaders());
  if (!response || response.error) {
    throw new Error(response && response.error ? response.error : "request failed");
  }
  if (response.statusCode !== 200) {
    throw new Error("HTTP " + response.statusCode + " for " + url);
  }
  return JSON.parse(response.body);
}

function parseNumericID(value, resourceType) {
  var raw = String(value || "").trim();
  if (!raw) return "";

  var direct = raw.match(/^\d+$/);
  if (direct) return direct[0];

  var prefixed = raw.match(/^tidal:(\d+)$/i);
  if (prefixed) return prefixed[1];

  var pattern = new RegExp(resourceType + "\\/(\\d+)", "i");
  var match = raw.match(pattern);
  if (match) return match[1];

  return "";
}

function parseArtistID(value) {
  return parseNumericID(value, "artist");
}

function externalAlbumURL(album) {
  if (!album) return "";
  if (album.url) return ensureHTTPS(album.url);
  if (album.id) return "https://tidal.com/browse/album/" + album.id;
  return "";
}

function albumArtistsDisplay(album) {
  if (!album) return "";
  return joinArtistNames(album.artists || []);
}

function tidalAlbumTitle(album) {
  if (!album) return "";
  var title = String(album.title || "").trim();
  var version = String(album.version || "").trim();
  if (!title || !version) return title;
  var normalizedTitle = title.toLowerCase();
  var normalizedVersion = version.toLowerCase();
  if (normalizedTitle.indexOf("(" + normalizedVersion + ")") >= 0 ||
      normalizedTitle.indexOf("[" + normalizedVersion + "]") >= 0 ||
      normalizedTitle.indexOf(" - " + normalizedVersion) >= 0) {
    return title;
  }
  return title + " (" + version + ")";
}

function albumBelongsToArtist(album, targetID) {
  if (!album) return false;
  var target = String(targetID || "");
  if (!target) return true;
  var hasArtistInfo = false;
  if (album.artist && album.artist.id !== undefined && album.artist.id !== null && String(album.artist.id) !== "") {
    hasArtistInfo = true;
    if (String(album.artist.id) === target) return true;
  }
  var artists = album.artists || [];
  for (var i = 0; i < artists.length; i++) {
    var a = artists[i] || {};
    if (a.id === undefined || a.id === null || String(a.id) === "") continue;
    hasArtistInfo = true;
    var type = String(a.type || "MAIN").toUpperCase();
    if (type === "MAIN" && String(a.id) === target) return true;
  }
  return !hasArtistInfo;
}

function formatArtistAlbum(album, fallbackType) {
  if (!album || !album.id) return null;

  var albumType = String(album.type || "").trim().toLowerCase();
  if (!albumType) albumType = String(fallbackType || "").trim().toLowerCase();
  if (!albumType) albumType = "album";

  return {
    id: withPrefix(album.id),
    name: tidalAlbumTitle(album),
    artists: albumArtistsDisplay(album),
    cover_url: imageURL(album.cover || "", "1280x1280"),
    images: imageURL(album.cover || "", "1280x1280"),
    release_date: normalizeDate(album.releaseDate || ""),
    total_tracks: Number(album.numberOfTracks || 0),
    total_discs: Number(album.numberOfVolumes || 0),
    album_type: albumType,
    provider_id: "tidal-web",
    item_type: "album",
    album_url: externalAlbumURL(album),
    external_urls: externalAlbumURL(album),
    copyright: String(album.copyright || ""),
    comment: externalAlbumURL(album),
    explicit: album.explicit === true
  };
}

function formatArtistInfo(artist) {
  if (!artist || !artist.id) return null;

  var image = imageURL(artist.picture || "", "750x750");
  return {
    id: withPrefix(artist.id),
    name: String(artist.name || ""),
    image_url: image,
    images: image,
    header_image: image,
    listeners: 0,
    provider_id: "tidal-web",
    item_type: "artist"
  };
}

function findModule(page, moduleType) {
  if (!page || !page.rows) return null;

  for (var i = 0; i < page.rows.length; i++) {
    var row = page.rows[i] || {};
    var modules = row.modules || [];
    for (var j = 0; j < modules.length; j++) {
      var module = modules[j] || {};
      if (module.type === moduleType) {
        return module;
      }
    }
  }
  return null;
}

function artistAlbumTypeFromModuleTitle(title) {
  var normalized = String(title || "").trim().toLowerCase();
  if (normalized === "albums" || normalized === "compilations" || normalized === "appears on") {
    return "album";
  }
  if (normalized === "ep & singles" || normalized === "eps & singles" || normalized === "singles" || normalized === "ep" || normalized === "eps") {
    return "single";
  }
  return "";
}

function fetchArtistPage(artistID) {
  var id = parseArtistID(artistID);
  if (!id) throw new Error("Invalid TIDAL artist ID: " + artistID);
  return getJSON(buildMetadataURL("pages/artist", { artistId: id }));
}

function fetchArtistAlbumsPage(dataAPIPath, offset, limit) {
  return getJSON(buildMetadataURL(dataAPIPath, {
    offset: offset,
    limit: limit
  }));
}

function appendArtistAlbums(albums, items, artistID, fallbackType, seen) {
  for (var i = 0; i < items.length; i++) {
    if (!albumBelongsToArtist(items[i], artistID)) continue;
    var album = formatArtistAlbum(items[i], fallbackType);
    if (!album || !album.id || seen[album.id]) continue;
    seen[album.id] = true;
    albums.push(album);
  }
}

function artistAlbumsCursor(artistID, pages) {
  if (!pages.length) return "";
  return "artist-albums:" + encodeURIComponent(JSON.stringify({ id: artistID, pages: pages }));
}

function fetchArtistAlbumsContinuation(cursor) {
  var state = JSON.parse(decodeURIComponent(cursor.slice("artist-albums:".length)));
  if (!state || !/^\d+$/.test(String(state.id || "")) || !Array.isArray(state.pages) || !state.pages.length) {
    throw new Error("Invalid artist albums cursor");
  }
  var pending = state.pages;
  var current = pending[0];
  if (!current || typeof current.path !== "string" || !current.path.trim() ||
      !Number.isInteger(current.offset) || current.offset < 0) {
    throw new Error("Invalid artist albums page");
  }
  // One provider request per app scroll request. The remaining module cursors
  // travel with the result, so pagination survives cache expiry or app restart.
  var page = fetchArtistAlbumsPage(current.path, current.offset, CONFIG.pageSize);
  var items = page.items || [];
  var albums = [];
  appendArtistAlbums(albums, items, state.id, current.type, {});
  var offset = current.offset + items.length;
  var total = Number(page.totalNumberOfItems === undefined
    ? current.total : page.totalNumberOfItems);
  if (!items.length || offset >= total) {
    pending.shift();
  } else {
    current.offset = offset;
    current.total = total;
  }
  return {
    id: withPrefix(state.id),
    albums: albums,
    albums_next: artistAlbumsCursor(state.id, pending),
    provider_id: "tidal-web",
    item_type: "artist"
  };
}

function getArtist(artistID) {
  try {
    var resourceID = String(artistID || "").trim();
    var cacheKey = "artist:" + CONFIG.countryCode + ":" + CONFIG.locale + ":" + resourceID;
    var cached = metadataCacheGet(cacheKey);
    if (cached) return cached;
    if (resourceID.indexOf("artist-albums:") === 0) {
      return metadataCacheSet(cacheKey, fetchArtistAlbumsContinuation(resourceID));
    }
    var page = fetchArtistPage(artistID);
    var headerModule = findModule(page, "ARTIST_HEADER");
    if (!headerModule || !headerModule.artist) {
      throw new Error("TIDAL artist page missing artist header");
    }

    var artistInfo = formatArtistInfo(headerModule.artist);
    var targetArtistID = String(headerModule.artist.id || "");
    var albums = [];
    var seen = {};
    var pending = [];
    var seenPaths = {};

    if (page.rows) {
      for (var rowIndex = 0; rowIndex < page.rows.length; rowIndex++) {
        var row = page.rows[rowIndex] || {};
        var modules = row.modules || [];
        for (var moduleIndex = 0; moduleIndex < modules.length; moduleIndex++) {
          var module = modules[moduleIndex] || {};
          if (module.type !== "ALBUM_LIST" || !module.pagedList) continue;

          var fallbackType = artistAlbumTypeFromModuleTitle(module.title);
          var items = module.pagedList.items || [];
          appendArtistAlbums(albums, items, targetArtistID, fallbackType, seen);
          var offset = Number(module.pagedList.offset || 0) + items.length;
          var total = Number(module.pagedList.totalNumberOfItems || 0);
          var dataPath = String(module.pagedList.dataApiPath || "").trim();
          if (offset < total && dataPath && !seenPaths[dataPath]) {
            seenPaths[dataPath] = true;
            pending.push({ path: dataPath, offset: offset, total: total, type: fallbackType });
          }
        }
      }
    }

    artistInfo.albums = albums;
    artistInfo.albums_next = artistAlbumsCursor(targetArtistID, pending);
    return metadataCacheSet(cacheKey, artistInfo);
  } catch (e) {
    log.error("[TidalWeb] getArtist failed:", e.message);
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
