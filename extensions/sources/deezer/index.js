// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/deezer/index.js
// Inactive source import: no app integration or update trust policy is installed.

var CONFIG = {
  resolverBaseURL: "https://api.zarz.moe",
  resolverDownloadPath: "/dl/dzr",
  deezerBaseURL: "https://www.deezer.com",
  apiBaseURL: "https://api.deezer.com",
  gatewayURL: "https://www.deezer.com/ajax/gw-light.php",
  blowfishSecret: "g4el58wc0zvf9na1",
  blowfishIVHex: "0001020304050607",
  chunkSize: 2048,
  maxCollectionTracks: 200,
  maxArtistAlbums: 100,
  maxArtistTopTracks: 20,
  coverMaxSize: 1400,
  metadataCacheTtlMs: 5 * 60 * 1000,
  metadataCacheMaxEntries: 500,
  gatewayTokenTtlMs: 30 * 60 * 1000
};

var metadataCache = new Map();

var gatewayToken = "";

var gatewayTokenCreatedAt = 0;

function nowMs() {
  return Date.now();
}

function cacheGet(key) {
  var entry = metadataCache.get(key);
  if (!entry) return null;
  if (nowMs() - entry.createdAt > CONFIG.metadataCacheTtlMs) {
    metadataCache.delete(key);
    return null;
  }
  metadataCache.delete(key);
  metadataCache.set(key, entry);
  return entry.value;
}

function initialize(settings) {
  settings = settings || {};
  var configuredBase = String(settings.apiBaseUrl || "").trim();
  if (configuredBase) {
    CONFIG.resolverBaseURL = configuredBase.replace(/\/+$/, "");
  }
  return true;
}

function cleanup() {
  metadataCache = new Map();
  gatewayToken = "";
  gatewayTokenCreatedAt = 0;
  return true;
}

function appUserAgent() {
  if (utils && typeof utils.appUserAgent === "function") {
    return String(utils.appUserAgent() || "").trim() || "SpotiFLAC-Mobile";
  }
  return "SpotiFLAC-Mobile";
}

function userAgentForURL(url) {
  var text = String(url || "").trim().toLowerCase();
  if (text.indexOf("https://api.zarz.moe") === 0 || text.indexOf("http://api.zarz.moe") === 0) {
    return appUserAgent();
  }
  return utils.randomUserAgent();
}

function getJSON(url, headers) {
  var response = http.get(url, headers || {});
  if (!response || response.error) {
    throw new Error(response && response.error ? response.error : "request failed");
  }
  if (response.statusCode !== 200) {
    throw new Error("HTTP " + response.statusCode + " for " + url);
  }
  return JSON.parse(response.body);
}

function normalizedUserAgent() {
  return {
    "User-Agent": userAgentForURL(CONFIG.resolverBaseURL),
    "Accept": "application/json"
  };
}

function normalizeDate(value) {
  var text = String(value || "").trim();
  if (!text) return "";
  if (text.length >= 10) return text.substring(0, 10);
  return text;
}

function uniqueValues(values) {
  var out = [];
  var seen = {};
  for (var i = 0; i < values.length; i++) {
    var value = String(values[i] || "").trim();
    var key = value.toLowerCase();
    if (!value || seen[key]) continue;
    seen[key] = true;
    out.push(value);
  }
  return out;
}

function numberValue(value) {
  var parsed = Number(value || 0);
  return isFinite(parsed) && parsed > 0 ? parsed : 0;
}

function isTruthyMetadata(value) {
  if (value === true || value === 1) return true;
  var normalized = String(value || "").trim().toLowerCase();
  return normalized === "1" || normalized === "true" || normalized === "explicit";
}

function directURL(resourceType, id) {
  var rawID = stripPrefix(id);
  if (!rawID) return "";
  return "https://www.deezer.com/" + resourceType + "/" + encodeURIComponent(rawID);
}

function withPrefix(id) {
  var raw = String(id || "").trim();
  if (!raw) return "";
  return raw.indexOf("deezer:") === 0 ? raw : "deezer:" + raw;
}

function stripPrefix(value) {
  var raw = String(value || "").trim();
  if (!raw) return "";
  return raw.indexOf("deezer:") === 0 ? raw.substring("deezer:".length) : raw;
}

function parseNumericID(value, resourceType) {
  var raw = String(value || "").trim();
  if (!raw) return "";

  var direct = raw.match(/^\d+$/);
  if (direct) return direct[0];

  var prefixed = raw.match(/^deezer:(\d+)$/i);
  if (prefixed) return prefixed[1];

  var pattern = new RegExp(resourceType + "\\/(\\d+)", "i");
  var match = raw.match(pattern);
  if (match) return match[1];

  return "";
}

function parseArtistID(value) {
  return parseNumericID(value, "artist");
}

function gatewayContributorNames(gatewayData, roles) {
  var contributors = gatewayData && gatewayData.SNG_CONTRIBUTORS;
  if (!contributors || typeof contributors !== "object") return [];
  var names = [];
  for (var i = 0; i < roles.length; i++) {
    var values = contributors[roles[i]];
    if (Array.isArray(values)) names = names.concat(values);
  }
  return uniqueValues(names);
}

function publicContributorNames(trackData, rolePattern) {
  var contributors = trackData && trackData.contributors;
  if (!Array.isArray(contributors)) return [];
  var names = [];
  for (var i = 0; i < contributors.length; i++) {
    var role = String(contributors[i] && contributors[i].role || "").toLowerCase();
    if (rolePattern.test(role)) names.push(contributors[i].name);
  }
  return uniqueValues(names);
}

function normalizeArtists(trackData, gatewayData) {
  if (!trackData) return "";

  var gatewayArtists = [];
  if (gatewayData && Array.isArray(gatewayData.ARTISTS)) {
    gatewayArtists = uniqueValues(gatewayData.ARTISTS.map(function(artist) {
      return artist && (artist.ART_NAME || artist.name);
    }));
  }
  if (!gatewayArtists.length) {
    gatewayArtists = gatewayContributorNames(gatewayData, [
      "main_artist", "featured_artist", "featuring", "artist", "performer"
    ]);
  }
  if (gatewayArtists.length) return gatewayArtists.join(", ");

  var publicArtists = publicContributorNames(trackData, /main|featured|artist|performer/);
  if (publicArtists.length) {
    return publicArtists.join(", ");
  }

  if (trackData.artist && trackData.artist.name) {
    return String(trackData.artist.name);
  }

  return "";
}

function composerNames(trackData, gatewayData) {
  var names = [];
  if (trackData && trackData.composer) names.push(trackData.composer);
  names = names.concat(gatewayContributorNames(gatewayData, [
    "composer", "author", "songwriter", "writer", "lyricist", "lyrics"
  ]));
  names = names.concat(publicContributorNames(trackData, /composer|author|songwriter|writer|lyricist/));
  return uniqueValues(names).join("; ");
}

var deezerCoverSizePattern = /\/(\d+)x(\d+)-(\d+)-(\d+)-(\d+)-(\d+)\.jpg(?=([?#]|$))/;

function highestQualityDeezerCoverURL(value) {
  var url = String(value || "").trim();
  if (!url || url.indexOf(".dzcdn.net/") === -1) return url;

  return url.replace(deezerCoverSizePattern, function(match, width, height, quality, padding, output, format) {
    if (Number(width) >= CONFIG.coverMaxSize && Number(height) >= CONFIG.coverMaxSize) {
      return match;
    }
    return "/" + CONFIG.coverMaxSize + "x" + CONFIG.coverMaxSize +
      "-" + quality + "-" + padding + "-" + output + "-" + format + ".jpg";
  });
}

function coverFromAlbum(album) {
  if (!album) return "";
  return highestQualityDeezerCoverURL(
    album.cover_xl ||
    album.cover_big ||
    album.cover_medium ||
    album.cover ||
    album.picture_xl ||
    album.picture_big ||
    album.picture_medium ||
    album.picture ||
    ""
  );
}

function coverFromArtist(artist) {
  if (!artist) return "";
  return highestQualityDeezerCoverURL(
    artist.picture_xl ||
    artist.picture_big ||
    artist.picture_medium ||
    artist.picture ||
    artist.cover_xl ||
    artist.cover_big ||
    artist.cover_medium ||
    artist.cover ||
    ""
  );
}

function albumTypeFromRecordType(value) {
  var normalized = String(value || "").trim().toLowerCase();
  if (!normalized) return "album";
  switch (normalized) {
    case "ep":
    case "single":
    case "compilation":
    case "album":
      return normalized;
    default:
      return "album";
  }
}

function deezerGet(pathOrURL) {
  var url = String(pathOrURL || "").trim();
  if (!url) {
    throw new Error("missing Deezer API URL");
  }

  if (!/^https?:\/\//i.test(url)) {
    if (url.charAt(0) !== "/") {
      url = "/" + url;
    }
    url = CONFIG.apiBaseURL + url;
  }

  return getJSON(url, normalizedUserAgent());
}

function collectPaginatedItems(container, limit) {
  var items = [];
  var nextURL = "";
  var source = container;
  var remaining = typeof limit === "number" && limit > 0 ? limit : 0;

  while (source) {
    var pageItems = source.data || [];
    for (var i = 0; i < pageItems.length; i++) {
      items.push(pageItems[i]);
      if (remaining > 0 && items.length >= remaining) {
        return items;
      }
    }

    nextURL = source.next || "";
    if (!nextURL) break;
    source = deezerGet(nextURL);
  }

  return items;
}

function fetchArtistData(artistID) {
  return deezerGet("/artist/" + encodeURIComponent(artistID));
}

function fetchArtistAlbums(artistID) {
  var result = deezerGet("/artist/" + encodeURIComponent(artistID) + "/albums?limit=100");
  return collectPaginatedItems(result, CONFIG.maxArtistAlbums);
}

function fetchArtistTopTracks(artistID) {
  var result = deezerGet("/artist/" + encodeURIComponent(artistID) + "/top?limit=" + CONFIG.maxArtistTopTracks);
  return collectPaginatedItems(result, CONFIG.maxArtistTopTracks);
}

function formatTrack(trackData, context) {
  if (!trackData || !trackData.id) return null;
  context = context || {};

  var albumData = context.album || trackData.album || null;
  var artistData = context.artist || trackData.artist || null;
  var gatewayTrack = context.gatewayTrack || null;
  var gatewayAlbum = context.gatewayAlbum || null;
  var artistName = normalizeArtists(trackData, gatewayTrack);
  if (!artistName && context.albumArtist) {
    artistName = context.albumArtist;
  }
  if (!artistName && artistData && artistData.name) {
    artistName = String(artistData.name);
  }

  var albumName = context.albumName || (albumData && albumData.title) || "";
  var albumArtist = context.albumArtist || (albumData && albumData.artist && albumData.artist.name) || (artistData && artistData.name) || artistName;
  var coverURL = context.coverURL || coverFromAlbum(albumData) || coverFromArtist(artistData);
  var releaseDate = context.releaseDate || (albumData && albumData.release_date) || trackData.release_date ||
    (gatewayAlbum && (gatewayAlbum.PHYSICAL_RELEASE_DATE || gatewayAlbum.DIGITAL_RELEASE_DATE || gatewayAlbum.ORIGINAL_RELEASE_DATE)) ||
    (gatewayTrack && (gatewayTrack.PHYSICAL_RELEASE_DATE || gatewayTrack.DIGITAL_RELEASE_DATE)) || "";
  var totalTracks = context.totalTracks || (albumData && albumData.nb_tracks) || 0;
  var itemID = withPrefix(trackData.id);
  var albumID = context.albumID || (albumData && albumData.id ? withPrefix(albumData.id) : "");
  var artistID = context.artistID || (artistData && artistData.id ? withPrefix(artistData.id) : "");
  var trackURL = String(trackData.link || directURL("track", trackData.id));
  var albumURL = String((albumData && albumData.link) || directURL("album", albumID));
  var artistURL = String((artistData && artistData.link) || directURL("artist", artistID));
  var discNumber = numberValue(trackData.disk_number || context.discNumber || (gatewayTrack && gatewayTrack.DISK_NUMBER));
  var trackNumber = numberValue(trackData.track_position || context.trackNumber || (gatewayTrack && gatewayTrack.TRACK_NUMBER));
  var isExplicit = !!(trackData.explicit_lyrics || isTruthyMetadata(trackData.explicit_content_lyrics) ||
    isTruthyMetadata(gatewayTrack && gatewayTrack.EXPLICIT_LYRICS) ||
    isTruthyMetadata(gatewayTrack && gatewayTrack.EXPLICIT_TRACK_CONTENT));

  return {
    id: itemID,
    spotify_id: itemID,
    deezer_id: String(trackData.id),
    name: String(trackData.title || trackData.title_short || ""),
    artists: artistName,
    album_name: String(albumName),
    album_artist: String(albumArtist || ""),
    artist_id: artistID,
    artist_url: artistURL,
    album_id: albumID,
    album_url: albumURL,
    external_urls: trackURL,
    external_links: { deezer: trackURL },
    duration_ms: Number(trackData.duration || 0) * 1000,
    preview_url: String(trackData.preview || ""),
    cover_url: coverURL,
    images: coverURL,
    release_date: normalizeDate(releaseDate),
    track_number: trackNumber,
    total_tracks: Number(totalTracks || 0),
    disc_number: discNumber,
    total_discs: Number(context.totalDiscs || 0),
    isrc: String(trackData.isrc || (gatewayTrack && gatewayTrack.ISRC) || ""),
    provider_id: "deezer",
    item_type: "track",
    album_type: albumTypeFromRecordType(context.albumType || (albumData && albumData.record_type)),
    upc: String((albumData && albumData.upc) || ""),
    label: String((albumData && albumData.label) || (gatewayAlbum && gatewayAlbum.LABEL_NAME) || ""),
    copyright: String((albumData && albumData.copyright) || (gatewayAlbum && gatewayAlbum.COPYRIGHT) || ""),
    genre: String(context.genre || ""),
    composer: composerNames(trackData, gatewayTrack),
    comment: albumURL,
    explicit: isExplicit,
    audio_quality: trackAudioQuality(trackData, gatewayTrack)
  };
}

function formatAlbum(albumData, context) {
  if (!albumData || !albumData.id) return null;
  context = context || {};

  var coverURL = coverFromAlbum(albumData);
  var gatewayAlbum = context.gatewayAlbum || null;
  var albumURL = String(albumData.link || directURL("album", albumData.id));
  return {
    id: withPrefix(albumData.id),
    name: String(albumData.title || ""),
    artists: String((albumData.artist && albumData.artist.name) || ""),
    artist_id: albumData.artist && albumData.artist.id ? withPrefix(albumData.artist.id) : "",
    artist_url: albumData.artist && albumData.artist.id ? directURL("artist", albumData.artist.id) : "",
    external_urls: albumURL,
    external_links: { deezer: albumURL },
    cover_url: coverURL,
    images: coverURL,
    release_date: normalizeDate(albumData.release_date || (gatewayAlbum &&
      (gatewayAlbum.PHYSICAL_RELEASE_DATE || gatewayAlbum.DIGITAL_RELEASE_DATE || gatewayAlbum.ORIGINAL_RELEASE_DATE))),
    total_tracks: Number(albumData.nb_tracks || (gatewayAlbum && gatewayAlbum.NUMBER_TRACK) || 0),
    total_discs: numberValue(context.totalDiscs || (gatewayAlbum && gatewayAlbum.NUMBER_DISK)),
    album_type: albumTypeFromRecordType(albumData.record_type),
    provider_id: "deezer",
    item_type: "album",
    upc: String(albumData.upc || ""),
    label: String(albumData.label || (gatewayAlbum && gatewayAlbum.LABEL_NAME) || ""),
    copyright: String(albumData.copyright || (gatewayAlbum && gatewayAlbum.COPYRIGHT) || ""),
    genre: extractGenres(albumData),
    explicit: !!(albumData.explicit_lyrics || isTruthyMetadata(gatewayAlbum && gatewayAlbum.EXPLICIT_ALBUM_CONTENT &&
      gatewayAlbum.EXPLICIT_ALBUM_CONTENT.EXPLICIT_LYRICS_STATUS)),
    audio_traits: ["lossless"]
  };
}

function formatArtist(artistData) {
  if (!artistData || !artistData.id) return null;

  var imageURL = coverFromArtist(artistData);
  var artistURL = String(artistData.link || directURL("artist", artistData.id));
  return {
    id: withPrefix(artistData.id),
    name: String(artistData.name || ""),
    image_url: imageURL,
    images: imageURL,
    header_image: imageURL,
    external_urls: artistURL,
    external_links: { deezer: artistURL },
    listeners: Number(artistData.nb_fan || 0),
    provider_id: "deezer",
    item_type: "artist"
  };
}

function extractGenres(albumData) {
  if (!albumData || !albumData.genres || !albumData.genres.data || !albumData.genres.data.length) {
    return "";
  }
  return uniqueValues(albumData.genres.data.map(function(genre) {
    return genre && genre.name;
  })).join("; ");
}

function fetchArtist(artistID) {
  var rawID = parseArtistID(artistID);
  if (!rawID) throw new Error("invalid Deezer artist ID");

  var artistData = fetchArtistData(rawID);
  var artistInfo = formatArtist(artistData);
  var albumItems = fetchArtistAlbums(rawID);
  var topTrackItems = fetchArtistTopTracks(rawID);
  var albums = [];
  var topTracks = [];

  for (var i = 0; i < albumItems.length; i++) {
    var albumInfo = formatAlbum(albumItems[i]);
    if (albumInfo) albums.push(albumInfo);
  }

  for (var j = 0; j < topTrackItems.length; j++) {
    var trackInfo = formatTrack(topTrackItems[j], {
      artist: artistData,
      artistID: artistInfo.id,
      coverURL: coverFromAlbum(topTrackItems[j].album),
      albumID: topTrackItems[j].album && topTrackItems[j].album.id ? withPrefix(topTrackItems[j].album.id) : "",
      albumName: topTrackItems[j].album && topTrackItems[j].album.title ? topTrackItems[j].album.title : "",
      albumArtist: artistInfo.name
    });
    if (trackInfo) topTracks.push(trackInfo);
  }

  artistInfo.albums = albums;
  artistInfo.top_tracks = topTracks;
  return artistInfo;
}

function getArtist(artistID) {
  try {
    return fetchArtist(artistID);
  } catch (e) {
    log.error("[DeezerExt] getArtist failed:", e.message);
    return null;
  }
}

function trackAudioQuality(trackData, gatewayTrack) {
  var measured = cacheGet("audio-quality:" + String(trackData && trackData.id || ""));
  if (measured) return measured;
  var source = gatewayTrack || trackData || {};
  if (Number(source.FILESIZE_FLAC_24 || 0) > 0) return "24-bit FLAC";
  // Catalog metadata does not normally expose the source sample rate.
  return "FLAC";
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
