// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/genie-music/index.js
// Inactive source import: no app integration or update trust policy is installed.

var PROVIDER_ID = "genie-music";

var TOP200_CACHE = [];

var TOP200_CACHE_TIME = 0;

var ALBUM_CACHE = {};

var ARTIST_CACHE = {};

var TRACK_CACHE = {};

var FEED_CACHE = {};

var CHART_CACHE = {};

var DJ_CACHE = {};

var CACHE_TTL_MS = 5 * 60 * 1000;

function initialize() {
  return {
    success: true
  };
}

function cleanup() {
  TOP200_CACHE = [];
  TOP200_CACHE_TIME = 0;
  ALBUM_CACHE = {};
  ARTIST_CACHE = {};
  TRACK_CACHE = {};
  FEED_CACHE = {};
  CHART_CACHE = {};
  DJ_CACHE = {};
  return {
    success: true
  };
}

function cleanText(value) {
  if (!value) {
    return "";
  }

  return String(value)
    .replace(/<!--[\s\S]*?-->/g, "")
    .replace(/<(?:span|em|strong)\b[^>]*class=["'][^"']*\b(?:icon|hide|blind|badge)\b[^"']*["'][^>]*>[\s\S]*?<\/(?:span|em|strong)>/gi, "")
    .replace(/<[^>]*>/g, "")
    .replace(/&nbsp;/gi, " ")
    .replace(/&amp;/gi, "&")
    .replace(/&quot;/gi, '"')
    .replace(/&#39;/gi, "'")
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
    .replace(/&#(x[0-9a-f]+|\d+);/gi, function(_, code) {
      var number = code.charAt(0).toLowerCase() === "x" ? parseInt(code.slice(1), 16) : parseInt(code, 10);
      return number > 0 && number <= 0x10ffff ? String.fromCodePoint(number) : "";
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
    return url.replace(/^http:\/\/((?:www\.)?genie\.co\.kr|image\.genie\.co\.kr)(?=\/)/i, "https://$1");
  }

  if (url.indexOf("/") === 0) {
    return "https://www.genie.co.kr" + url;
  }

  return "https://www.genie.co.kr/" + url;
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
  return firstMatch(row, [/href=["'][^"']*songInfo[^"']*[?&]xgnm=(\d+)/i,/data-song-no\s*=\s*["'](\d+)["']/i,/data-songid\s*=\s*["'](\d+)["']/i,/songId\s*[=:]\s*["']?(\d+)/i,/songid\s*[=:]\s*["']?(\d+)/i,/xgnm\s*[=:]\s*["']?(\d+)/i]);
}

function getTrackName(row) {
  return firstMatch(row, [
    /<a[^>]*class=["'][^"']*\btitle\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i,
    /<a[^>]*href=["'][^"']*songInfo[^"']*["'][^>]*>([\s\S]*?)<\/a>/i
  ]);
}

function getArtistName(row) {
  return firstMatch(row, [
    /<a[^>]*class=["'][^"']*artist[^"']*["'][^>]*>([\s\S]*?)<\/a>/i,/<a[^>]*class=["'][^"']*(?:artist|artistName)[^"']*["'][^>]*>([\s\S]*?)<\/a>/i,/<span[^>]*class=["'][^"']*(?:artist|artistName)[^"']*["'][^>]*>([\s\S]*?)<\/span>/i]);
}

function getAlbumId(row) {
  return firstMatch(row, [
    /href=["'][^"']*albumInfo[^"']*[?&]axnm=(\d+)/i,
    /fnViewAlbumLayer\s*\(\s*["']?(\d+)/i,
    /fnGoMore\s*\(\s*["']albumInfo["']\s*,\s*["']?(\d+)/i,
    /data-album-no\s*=\s*["'](\d+)["']/i,
    /data-album-id\s*=\s*["'](\d+)["']/i,
    /(?:albumInfo|albumView)[^"']*(?:axnm|albumId|albumNo|albnm)[=\\"]+(\d+)/i,
    /(?:axnm|albumId|albumNo|albnm)\s*[=:]\s*["']?(\d+)/i,
    /[?&](?:axnm|albumId|albumNo|albnm)=(\d+)/i,
    /goAlbum(?:Detail)?\s*\([^)]*?(\d{4,})/i,
    /(?:albumInfo|albumView|\/album\/)[^>]{0,500}?(?:axnm|albumId|albumNo|albnm)\s*[=:]\s*["']?(\d{4,})/i,
    /(?:data-)?(?:album|al)\s*(?:no|id)\s*=\s*["'](\d{4,})["']/i,
    /href=["'][^"']*\/album\/(\d{4,})[^"']*["']/i
  ]);
}

function getAlbumName(row) {
  return firstMatch(row, [
    /<a[^>]*class=["'][^"']*\balbumtitle\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i,
    /<a[^>]*class=["'][^"']*\balbum\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i,
    /class=["'][^"']*albumName[^"']*["'][^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i,
    /class=["'][^"']*album[^"']*["'][^>]*>([\s\S]*?)<\/span>/i
  ]);
}

function normalizeCoverUrl(url) {
  if (!url) return "";
  url = absoluteUrl(url).replace(/\?[^#]*$/, "");
  if (/^https:\/\/image\.genie\.co\.kr\//i.test(url)) {
    url = url.replace(/\/dims\/.*$/i, "").replace(/_\d+x\d+(\.\w+)$/i, "_600x600$1");
  }
  return url;
}

function getCoverUrl(row) {
  var urls = [];
  var re = /(?:data-original|data-src|data-lazy-src|data-image|src|content)=["\']([^"\']+)["\']/ig;
  var m;
  while ((m = re.exec(row)) !== null) {
    var u = String(m[1] || "").replace(/&amp;/gi, "&").trim();
    if (u && !/^data:image/i.test(u) && !/blank|transparent|noimage|default/i.test(u)) urls.push(u);
  }
  var bg = row.match(/background-image\s*:\s*url\(["\']?([^"\')]+)["\']?\)/i);
  if (bg) urls.push(bg[1]);
  for (var i=0;i<urls.length;i++) {
    if (/image\.genie\.co\.kr/i.test(urls[i])) return normalizeCoverUrl(urls[i]);
  }
  return urls.length ? normalizeCoverUrl(urls[0]) : "";
}

function getDurationMs(row) {
  var clock = row.match(/(?:재생시간|재생 시간|txt_8\.png)[\s\S]{0,200}?(\d{1,2}:\d{2}(?::\d{2})?)/i);
  if (clock) {
    return clock[1].split(":").reduce(function(seconds, part) { return seconds * 60 + Number(part); }, 0) * 1000;
  }
  var explicitMs = row.match(/(?:data-duration-ms|duration_ms)\s*[=:]\s*["']?(\d+)/i);
  if (explicitMs) return Number(explicitMs[1]);
  var value = firstMatch(row, [
    /data-duration\s*=\s*["'](\d+)["']/i,
    /duration\s*[=:]\s*["']?(\d{2,6})/i
  ]);
  if (!value) return 0;
  if (String(value).indexOf(":") >= 0) {
    var parts = String(value).split(":");
    return (parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10)) * 1000;
  }
  return parseInt(value, 10) * 1000;
}

function getArtistId(row) {
  return firstMatch(row, [
    /fnViewArtist\s*\(\s*["']?(\d+)/i,
    /fnGoMore\s*\(\s*["']artistInfo["']\s*,\s*["']?(\d+)/i,
    /artistInfo[^"']*[?&]xxnm=(\d+)/i
  ]);
}

function getIsrc(row) {
  return firstMatch(row, [
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

  if (!name || !artists) return null;

  return {
    id: String(id),
    name: name,
    artists: artists,
    album_name: albumName,
    album_id: albumId,
    artist_id: getArtistId(row),
    cover_url: coverUrl,
    duration_ms: getDurationMs(row),
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
    uri: "genie-music:track:" + String(track.id),
    type: "track",
    name: track.name || "",
    artists: track.artists || "",
    album_name: track.album_name || "",
    album_id: track.album_id || "",
    album_url: track.album_id ? "https://www.genie.co.kr/detail/albumInfo?axnm=" + track.album_id : "",
    artist_id: track.artist_id || "",
    artist_url: track.artist_id ? "https://www.genie.co.kr/detail/artistInfo?xxnm=" + track.artist_id : "",
    cover_url: track.cover_url || "",
    images: track.cover_url || "",
    item_type: "track",
    duration_ms: Number(track.duration_ms || 0),
    isrc: track.isrc || "",
    release_date: track.release_date || "",
    track_number: Number(track.track_number || 0),
    genre: track.genre || "",
    composer: track.composer || "",
    external_urls: "https://www.genie.co.kr/detail/songInfo?xgnm=" + String(track.id),
    external_links: { genie: "https://www.genie.co.kr/detail/songInfo?xgnm=" + String(track.id), source: "https://www.genie.co.kr/detail/songInfo?xgnm=" + String(track.id) },
    provider_id: PROVIDER_ID
  };
}

function fetchHtml(url) {
  var response = http.get(url, {
    "User-Agent": "Mozilla/5.0",
    "Accept": "text/html,application/xhtml+xml"
  });
  if (response && response.error) throw new Error("Genie request failed: " + response.error + ": " + url);
  if (!response || !response.ok) {
    throw new Error("Genie HTTP " + (response ? response.status : "unavailable") + ": " + url);
  }
  var body = response.body || "";
  if (!body || !/<(?:html|table|div)\b/i.test(body)) throw new Error("Genie returned no HTML: " + url);
  return body;
}

function mainInfo(html, className) {
  var start = html.search(new RegExp("<div[^>]*class=[\"'][^\"']*\\b" + className + "\\b", "i"));
  if (start < 0) throw new Error("Genie " + className + " metadata is unavailable");
  var end = html.indexOf("<!-- E. info-zone", start);
  if (end < 0) end = html.indexOf('class="song-list"', start);
  return html.slice(start, end < 0 ? start + 18000 : end);
}

function primaryTrackTable(html) {
  var table = html.match(/<table[^>]*class=["'][^"']*\blist-wrap\b[^"']*["'][^>]*>[\s\S]*?<\/table>/i);
  return table ? table[0] : "";
}

function detailName(html) {
  return firstMatch(html, [/<h2[^>]*class=["'][^"']*\bname\b[^"']*["'][^>]*>([\s\S]*?)<\/h2>/i]);
}

function cacheStore(cache, id, value) {
  var now = Date.now();
  Object.keys(cache).forEach(function(key) {
    if (now - cache[key].time >= CACHE_TTL_MS) delete cache[key];
  });
  var keys = Object.keys(cache);
  if (!cache[id] && keys.length >= 64) {
    keys.sort(function(a, b) { return cache[a].time - cache[b].time; });
    delete cache[keys[0]];
  }
  cache[id] = value;
}

function parseArtistAlbums(html, artistId, artistName) {
  var rows = html.match(/<li[^>]*class=["'][^"']*\blist-album\b[^"']*["'][^>]*>[\s\S]*?<\/dl>/gi) || [];
  var seen = {};
  var albums = [];
  rows.forEach(function(row) {
    var id = getAlbumId(row);
    var name = firstMatch(row, [/<dt[^>]*>[\s\S]*?<a[^>]*>([\s\S]*?)<\/a>/i]);
    if (!id || !name || seen[id]) return;
    seen[id] = true;
    albums.push({
      id: id,
      uri: PROVIDER_ID + ":album:" + id,
      name: name,
      artists: getArtistName(row) || artistName,
      artist_id: artistId,
      release_date: firstMatch(row, [/<dd[^>]*class=["']desc["'][^>]*>\s*(\d{4}\.\d{2}\.\d{2})/i]).replace(/\./g, "-"),
      total_tracks: Number(firstMatch(row, [/<dd[^>]*class=["']desc["'][^>]*>[\s\S]*?(\d+)곡/i])) || 0,
      album_type: /싱글\/EP/.test(row) ? "single" : /컴필레이션/.test(row) ? "compilation" : "album",
      cover_url: getCoverUrl(row),
      provider_id: PROVIDER_ID,
      item_type: "album",
      type: "album",
      tracks: []
    });
  });
  return albums;
}

function getArtist(artistId) {
  var value = String(artistId || "").replace(PROVIDER_ID + ":artist:", "").trim();
  var match = value.match(/^(\d+)(?::albums:(\d+))?$/);
  if (!match) throw new Error("Invalid Genie artist ID");
  var id = match[1], page = Number(match[2] || "1");
  // Keep the ten-item offset within JavaScript's exact integer range.
  if (page < 1 || page > 900719925474099) throw new Error("Invalid Genie album page");
  var main = "", artistHtml = "";
  var identity = ARTIST_CACHE[id];
  if (page === 1 || !identity || Date.now() - identity.time >= CACHE_TTL_MS) {
    artistHtml = fetchHtml("https://www.genie.co.kr/detail/artistInfo?xxnm=" + id);
    main = mainInfo(artistHtml, "artist-main-infos");
    var artistName = detailName(main);
    if (!artistName) throw new Error("Genie artist metadata is incomplete: " + id);
    identity = { time: Date.now(), name: artistName, image_url: getCoverUrl(main) };
    cacheStore(ARTIST_CACHE, id, identity);
  }
  var html = fetchHtml(page === 1 ? "https://www.genie.co.kr/detail/artistAlbum?xxnm=" + id
    : "https://www.genie.co.kr/detail/bArtistAlbumList?xxnm=" + id + "&pg=" + page + "&pgsize=10&otype=newest&atype=ALL");
  var albums = parseArtistAlbums(html, id, identity.name);
  var totalText = firstMatch(html, [/전체\s*<strong>\s*([\d,]+)\s*<\/strong>/i]).replace(/,/g, "");
  var total = totalText ? Number(totalText) : albums.length;
  if (!albums.length && totalText !== "0") {
    throw new Error("Genie artist album list is unavailable: " + id);
  }
  return {
    id: id, uri: PROVIDER_ID + ":artist:" + id, type: "artist",
    name: identity.name, provider_id: PROVIDER_ID,
    image_url: identity.image_url, albums: albums,
    albums_next: page * 10 < total && albums.length ? id + ":albums:" + (page + 1) : "",
    top_tracks: page === 1 ? parseTracks(primaryTrackTable(artistHtml)).map(makeTrackResult) : []
  };
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
