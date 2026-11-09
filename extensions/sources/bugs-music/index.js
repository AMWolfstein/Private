// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/bugs-music/index.js
// Inactive source import: no app integration or update trust policy is installed.

var BASE_URL = "https://music.bugs.co.kr";

var PROVIDER_ID = "bugs-music";

var TOP100_CACHE = [];

var TOP100_CACHE_TIME = 0;

var FEED_CACHE = {};

var TRACK_CACHE = {};

var ALBUM_CACHE = {};

var CHART_CACHE = {};

function initialize() {
  return {
    success: true
  };
}

function cleanup() {
  TOP100_CACHE = [];
  TOP100_CACHE_TIME = 0;
  FEED_CACHE = {};
  TRACK_CACHE = {};
  ALBUM_CACHE = {};
  CHART_CACHE = {};
  return {
    success: true
  };
}

function cleanText(value) {
  if (!value) {
    return "";
  }

  return String(value)
    .replace(/<[^>]*>/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#(x[0-9a-f]+|\d+);/gi, function(match, value) {
      var code = value.charAt(0).toLowerCase() === "x" ? parseInt(value.slice(1), 16) : parseInt(value, 10);
      if (!isFinite(code) || code < 0 || code > 0x10ffff) return match;
      if (code <= 0xffff) return String.fromCharCode(code);
      code -= 0x10000;
      return String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff));
    })
    .replace(/\s+/g, " ")
    .trim();
}

function absoluteUrl(url) {
  if (!url) {
    return "";
  }

  url = String(url)
    .replace(/&amp;/gi, "&")
    .trim();

  if (url.indexOf("//") === 0) {
    return "https:" + url;
  }

  if (
    url.indexOf("http://") === 0 ||
    url.indexOf("https://") === 0
  ) {
    return url;
  }

  if (url.indexOf("/") === 0) {
    return BASE_URL + url;
  }

  return BASE_URL + "/" + url;
}

function firstMatch(text, patterns) {
  for (var i = 0; i < patterns.length; i++) {
    var match = text.match(patterns[i]);

    if (match && match[1]) {
      return cleanText(match[1]);
    }
  }

  return "";
}

function getTrackId(row) {
  return firstMatch(row, [
    /href=["'][^"']*\/track\/(\d+)[^"']*["']/i,
    /data-track-id\s*=\s*["'](\d+)["']/i,
    /data-trackid\s*=\s*["'](\d+)["']/i,
    /trackId\s*=\s*["']?(\d+)/i,
    /trackid\s*=\s*["']?(\d+)/i,
    /trackNo\s*=\s*["']?(\d+)/i
  ]);
}

function getTrackName(row) {
  return firstMatch(row, [
    /<p[^>]*class=["'][^"']*\btitle\b[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i,
    /<a[^>]*class=["'][^"']*\btitle\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i,
    /class=["'][^"']*trackTitle[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i,
    /class=["'][^"']*title[^"']*["'][^>]*>([\s\S]*?)<\/span>/i,
    /title\s*=\s*["']([^"']+)["']/i
  ]);
}

function getArtistName(row) {
  var artistCell = row.match(/<p[^>]*class=["'][^"']*\bartist\b[^"']*["'][^>]*>([\s\S]*?)<\/p>/i);
  if (artistCell) return multiArtistNames(artistCell[1]) || linkNames(artistCell[1], "artist");
  return firstMatch(row, [
    /<p[^>]*class=["'][^"']*\bartist\b[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i,
    /<p[^>]*class=["'][^"']*artistName[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i,
    /class=["'][^"']*artist[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i,
    /class=["'][^"']*artist[^"']*["'][^>]*>([\s\S]*?)<\/span>/i
  ]);
}

function getAlbumId(row) {
  return firstMatch(row, [
    /href=["'][^"']*\/album\/(\d+)[^"']*["']/i,
    /data-album-id\s*=\s*["'](\d+)["']/i,
    /albumId\s*=\s*["']?(\d+)/i
  ]);
}

function getAlbumName(row) {
  return firstMatch(row, [
    /<a[^>]*class=["'][^"']*\balbum\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i,
    /class=["'][^"']*\balbumName\b[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i
  ]);
}

function linkNames(html, kind) {
  var names = [], seen = {};
  var pattern = new RegExp("<a[^>]*href=[\"'][^\"']*/" + kind + "/\\d+[^\"']*[\"'][^>]*>([\\s\\S]*?)</a>", "gi");
  var match;
  while ((match = pattern.exec(html))) {
    var name = cleanText(match[1]);
    if (name && !seen[name]) { names.push(name); seen[name] = true; }
  }
  return names.join(", ");
}

function multiArtistNames(cell) {
  var match = cell.match(/openMultiArtistSearchResultPopLayer\(\s*this\s*,\s*'((?:[^'\\]|\\.)*)'/i);
  if (!match) return "";
  var names = [], seen = {};
  match[1].split(/\\+n/).forEach(function(entry) {
    var name = cleanText(entry.split("||")[0].replace(/\\(.)/g, "$1"));
    if (name && !seen[name]) { names.push(name); seen[name] = true; }
  });
  return names.length > 1 ? names.join(", ") : "";
}

function getArtistId(html) {
  return firstMatch(html, [
    /artistId\s*=\s*["'](\d+)["']/i,
    /href=["'][^"']*\/artist\/(\d+)[^"']*["']/i
  ]);
}

function getInfoCell(html, label) {
  var match = html.match(new RegExp("<th[^>]*>\\s*" + label + "\\s*</th>\\s*<td[^>]*>([\\s\\S]*?)</td>", "i"));
  return match ? match[1] : "";
}

function pageTitle(html) {
  return firstMatch(html, [
    /<header[^>]*class=["'][^"']*\bpgTitle\b[^"']*["'][^>]*>[\s\S]*?<h1[^>]*>([\s\S]*?)<\/h1>/i,
    /<meta[^>]*property=["']og:title["'][^>]*content=["']([^"']+)["']/i
  ]).replace(/\s*-\s*벅스\s*$/, "");
}

function structuredData(html, type) {
  var scripts = html.match(/<script[^>]*type=["']application\/ld\+json["'][^>]*>[\s\S]*?<\/script>/gi) || [];
  function find(value) {
    if (!value || typeof value !== "object") return null;
    if (Array.isArray(value)) {
      for (var j = 0; j < value.length; j++) { var item = find(value[j]); if (item) return item; }
    } else {
      if (value["@type"] === type || (Array.isArray(value["@type"]) && value["@type"].indexOf(type) >= 0)) return value;
      if (value["@graph"]) return find(value["@graph"]);
    }
    return null;
  }
  for (var i = 0; i < scripts.length; i++) {
    try {
      var data = find(JSON.parse(scripts[i].replace(/^[\s\S]*?>/, "").replace(/<\/script>[\s\S]*$/i, "")));
      if (data) return data;
    } catch (error) {}
  }
  return {};
}

function normalizeId(value, kind) {
  var id = String(value || "").replace(new RegExp("^bugs:" + kind + ":"), "").trim();
  if (!/^\d+$/.test(id)) throw new Error("Invalid Bugs " + kind + " ID");
  return id;
}

function normalizeCoverUrl(url) {
  if (!url) return "";
  url = absoluteUrl(url).replace(/\?[^#]*$/, "");
  // Bugs serves the same cover in 50/60/100/130/148/200/500/1000 sizes.
  // Prefer the largest album image while preserving the album folder and id.
  url = url.replace(/\/album\/images\/(?:50|60|100|130|148|170|200|500)\//i, "/album/images/1000/");
  url = url.replace(/\/essential\/images\/(?:50|60|100|120|130|200|500)\//i, "/essential/images/500/");
  return url;
}

function getCoverUrl(row) {
  var patterns = [
    /<a[^>]*class=["'][^"']*thumbnail[^"']*["'][^>]*>[\s\S]*?<img[^>]*src=["']([^"']+)["']/i,
    /<a[^>]*class=["'][^"']*thumbnail[^"']*["'][^>]*>[\s\S]*?<img[^>]*data-original=["']([^"']+)["']/i,
    /<img[^>]*data-original=["']([^"']+)["']/i,
    /<img[^>]*data-src=["']([^"']+)["']/i,
    /<img[^>]*src=["']([^"']+)["']/i,
    /background-image\s*:\s*url\(["']?([^"')]+)["']?\)/i
  ];

  for (var i = 0; i < patterns.length; i++) {
    var match = row.match(patterns[i]);

    if (!match || !match[1]) {
      continue;
    }

    var url = match[1]
      .replace(/&amp;/gi, "&")
      .split(",")[0]
      .trim()
      .split(" ")[0];

    if (!url) {
      continue;
    }

    if (
      url.indexOf("data:image") === 0 ||
      url.indexOf("blank.gif") >= 0 ||
      url.indexOf("transparent") >= 0
    ) {
      continue;
    }

    return normalizeCoverUrl(url);
  }

  return "";
}

function getDurationMs(row) {
  var ms = firstMatch(row, [/data-duration-ms\s*=\s*["'](\d+)["']/i]);
  if (ms) return Number(ms);
  var seconds = firstMatch(row, [/data-duration\s*=\s*["'](\d+)["']/i]);
  if (seconds) return Number(seconds) * 1000;
  return durationMs(cleanText(getInfoCell(row, "재생\\s*시간")));
}

function durationMs(value) {
  var iso = String(value || "").match(/^PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+(?:\.\d+)?)S)?$/i);
  if (iso) return Math.round((Number(iso[1] || 0) * 3600 + Number(iso[2] || 0) * 60 + Number(iso[3] || 0)) * 1000);
  var parts = String(value || "").match(/^(?:(\d+):)?(\d+):(\d{2})$/);
  return parts ? (Number(parts[1] || 0) * 3600 + Number(parts[2]) * 60 + Number(parts[3])) * 1000 : 0;
}

function getIsrc(row) {
  return firstMatch(row, [
    /^\s*([A-Z]{2}[A-Z0-9]{3}\d{7})\s*$/i,
    /\bISRC\b[^A-Z0-9]{0,30}([A-Z]{2}[A-Z0-9]{3}\d{7})/i,
    /isrc\s*[=:]\s*["']([^"']+)["']/i
  ]).toUpperCase();
}

function parseTrackRow(row) {
  var id = getTrackId(row);

  if (!id) {
    return null;
  }

  var name = getTrackName(row);
  var artists = getArtistName(row);
  var albumName = getAlbumName(row);
  var albumId = getAlbumId(row);
  var coverUrl = getCoverUrl(row);

  if (!name) return null;

  return {
    id: String(id),
    name: name,
    artists: artists,
    artist_id: getArtistId(row),
    album_name: albumName,
    album_id: albumId,
    cover_url: coverUrl,
    duration_ms: getDurationMs(row),
    track_number: Number(firstMatch(row, [/<p[^>]*class=["'][^"']*\btrackIndex\b[^"']*["'][^>]*>[\s\S]*?<em[^>]*>(\d+)<\/em>/i]) || 0),
    disc_number: Number(firstMatch(row, [/disc_id=["'](\d+)["']/i]) || 0),
    explicit: /adult_yn=["']Y["']/i.test(row),
    isrc: getIsrc(row)
  };
}

function parseTracks(html) {
  var tracks = [];
  var seen = {};

  if (!html) {
    return tracks;
  }

  var rows = html.match(
    /<tr[^>]*>[\s\S]*?<\/tr>/gi
  ) || [];

  for (var i = 0; i < rows.length; i++) {
    var track = parseTrackRow(rows[i]);

    if (!track || !track.id) {
      continue;
    }

    if (seen[track.id]) {
      continue;
    }

    seen[track.id] = true;
    tracks.push(track);
  }

  return tracks;
}

function makeTrackResult(track) {
  return {
    id: String(track.id),
    uri: "bugs:track:" + String(track.id),
    type: "track",
    name: track.name || "",
    artists: track.artists || "",
    artist_id: track.artist_id || "",
    artist_url: track.artist_id ? BASE_URL + "/artist/" + track.artist_id : "",
    album_name: track.album_name || "",
    album_id: track.album_id || "",
    album_url: track.album_id ? BASE_URL + "/album/" + track.album_id : "",
    album_artist: track.album_artist || "",
    external_urls: BASE_URL + "/track/" + String(track.id),
    release_date: track.release_date || "",
    track_number: Number(track.track_number || 0),
    disc_number: Number(track.disc_number || 0),
    total_tracks: Number(track.total_tracks || 0),
    explicit: Boolean(track.explicit),
    album_uri: track.album_id ? "bugs:album:" + String(track.album_id) : "",
    album: {
      id: String(track.album_id || ""),
      uri: track.album_id ? "bugs:album:" + String(track.album_id) : "",
      type: "album",
      name: track.album_name || "",
      cover_url: track.cover_url || "",
      images: track.cover_url || "",
      item_type: "album",
      provider_id: PROVIDER_ID
    },
    cover_url: track.cover_url || "",
    images: track.cover_url || "",
    item_type: "track",
    duration_ms: Number(track.duration_ms || 0),
    isrc: track.isrc || "",
    external_links: { bugs: "https://music.bugs.co.kr/track/" + String(track.id) },
    provider_id: PROVIDER_ID
  };
}

function fetchHtml(url) {
  var response = http.get(url, {
    "User-Agent": "Mozilla/5.0",
    "Accept": "text/html,application/xhtml+xml"
  });
  if (!response || !response.ok) {
    throw new Error("Bugs HTTP error " + (response ? response.status : "unavailable") + ": " + url);
  }
  return response.body || "";
}

function getArtist(artistId) {
  var id = normalizeId(artistId, "artist");
  var html = fetchHtml(BASE_URL + "/artist/" + id);
  var data = structuredData(html, "MusicGroup");
  var name = pageTitle(html) || cleanText(data.name);
  if (!name) throw new Error("Bugs artist metadata not found: " + id);
  var albums = [], seen = {};
  var figures = html.match(/<figure[^>]*class=["'][^"']*\balbumInfo\b[^"']*["'][^>]*>[\s\S]*?<\/figure>/gi) || [];
  for (var i = 0; i < figures.length; i++) {
    var albumId = getAlbumId(figures[i]);
    if (!albumId || seen[albumId]) continue;
    var title = firstMatch(figures[i], [/<div[^>]*class=["'][^"']*\balbumTitle\b[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i]);
    if (!title) continue;
    seen[albumId] = true;
    var albumArtists = linkNames(figures[i], "artist") || name;
    var albumType = firstMatch(figures[i], [/<span[^>]*class=["'][^"']*\balbumType\b[^"']*["'][^>]*>([\s\S]*?)<\/span>/i]);
    albums.push({ id: albumId, name: title, artists: albumArtists, artist_id: getArtistId(figures[i]) || id, cover_url: getCoverUrl(figures[i]),
      release_date: firstMatch(figures[i], [/<time[^>]*>([\s\S]*?)<\/time>/i]).replace(/\./g, "-"),
      album_type: albumType.indexOf("싱글") >= 0 ? "single" : albumType.indexOf("EP") >= 0 ? "ep" : "album",
      item_type: "album", provider_id: PROVIDER_ID, total_tracks: 0, tracks: [] });
  }
  return { id: id, name: name, image_url: absoluteUrl(data.image || firstMatch(html, [/<meta[^>]*property=["']og:image["'][^>]*content=["']([^"']+)["']/i])),
    albums: albums, top_tracks: parseTracks(html).map(makeTrackResult), provider_id: PROVIDER_ID };
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
