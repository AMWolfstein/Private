// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/melon-music/index.js
// Inactive source import: no app integration or update trust policy is installed.

var BASE_URL = "https://www.melon.com";

var MOBILE_WEB_URL = "https://m.app.melon.com";

var MOBILE_USER_AGENT = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148";

var PROVIDER_ID = "melon-music";

var FEED_CACHE = {};

var TRACK_CACHE = {};

var ALBUM_CACHE = {};

function initialize() {
  return {
    success: true
  };
}

function cleanup() {
  FEED_CACHE = {};
  TRACK_CACHE = {};
  ALBUM_CACHE = {};
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
    .replace(/&#(x[0-9a-f]+|\d+);/gi, function (_, value) {
      var code = value.charAt(0).toLowerCase() === "x" ? parseInt(value.slice(1), 16) : parseInt(value, 10);
      return code > 0 && code <= 0x10ffff ? String.fromCodePoint(code) : "";
    })
    .replace(/&lt;/gi, "<")
    .replace(/&gt;/gi, ">")
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
  return firstMatch(row, [/data-song-no\s*=\s*["'](\d+)["']/i, /goSongDetail\(\s*["']?(\d+)/i, /playSong\(\s*["']?\d+["']?\s*,\s*["']?(\d+)/i]);
}

function getTrackName(row) {
  return firstMatch(row, [
    /<a\b[^>]*href=["'][^>]*playSong\([^>]*>([\s\S]*?)<\/a>/i,
    // Songs Melon cannot stream, such as CD-only demos, show an unlinked title.
    /<div\b[^>]*class=["'][^"']*\bwrap_song_info\b[^"']*["'][^>]*>[\s\S]*?<span\b[^>]*class=["']disabled["'][^>]*>([\s\S]*?)<\/span>/i
  ]);
}

function getArtistName(row) {
  return artistInfo(row).name;
}

function artistInfo(html) {
  var names = [], ids = [], seen = {};
  var re = /<a\b[^>]*href=["'][^>]*(?:goArtistDetail\(\s*["']?|\/artist\/(?:detail|timeline)\.htm\?artistId=)(\d+)[^>]*>([\s\S]*?)<\/a>/gi, match;
  while ((match = re.exec(html)) !== null) {
    var name = cleanText(match[2]);
    if (name && !seen[match[1]]) {
      seen[match[1]] = true;
      names.push(name);
      ids.push(match[1]);
    }
  }
  return { name: names.join(", "), id: ids[0] || "" };
}

function pageMeta(html, name) {
  return firstMatch(html, [new RegExp("<meta\\b[^>]*property=[\\\"']" + name + "[\\\"'][^>]*content=[\\\"']([^\\\"']+)[\\\"']", "i")]);
}

function resourceId(value, type) {
  var id = String(value || "").replace(new RegExp("^" + PROVIDER_ID + ":" + type + ":"), "").trim();
  if (!/^\d+$/.test(id)) throw new Error("Melon " + type + " ID must be numeric");
  return id;
}

function getAlbumId(row) {
  return firstMatch(row, [
    /data-album-id\s*=\s*["'](\d+)["']/i,
    /href\s*=\s*["'][^"']*album\/detail\.htm\?[^"']*albumId=(\d+)/i,
    /href\s*=\s*["'][^"']*[?&]albumId=(\d+)[^"']*["']/i,
    /albumId(?:=|\s*[=:])\s*["']?(\d+)/i,
    /albumNo(?:=|\s*[=:])\s*["']?(\d+)/i,
    /goAlbumDetail\((?:\s*["']?)(\d+)/i,
    /albumId["']?\s*[:=]\s*["']?(\d+)/i,
    /albnm\s*[=:]\s*["']?(\d+)/i
  ]);
}

function getAlbumName(row) {
  var anchors = /<a\b[^>]*href=["'][^>]*(?:goAlbumDetail\(|\/album\/detail\.htm\?albumId=)[^>]*>([\s\S]*?)<\/a>/gi, match;
  while ((match = anchors.exec(row)) !== null) {
    var name = cleanText(match[1]);
    if (name) return name;
  }
  return "";
}

function normalizeCoverUrl(url) {
  if (!url) return "";
  url = absoluteUrl(url).replace(/^http:/i, "https:");
  // Strip Melon's transformation query to preserve the original 500px asset.
  return url.replace(/\?[^#]*$/, "").replace(/\/melon\/resize\/[^#]*$/, "");
}

function getCoverUrl(row) {
  var patterns = [
    /<a[^>]*class=["'][^"']*thumbnail[^"']*["'][^>]*>[\s\S]*?<img[^>]*src=["']([^"']+)["']/i,
    /<a[^>]*class=["'][^"']*thumbnail[^"']*["'][^>]*>[\s\S]*?<img[^>]*data-original=["']([^"']+)["']/i,
    /<img[^>]*data-original=["']([^"']+)["']/i,
    /<img[^>]*data-src=["']([^"']+)["']/i,
    /<img[^>]*data-lazy-src=["']([^"']+)["']/i,
    /<img[^>]*srcset=["']([^"']+)["']/i,
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
  var millis = firstMatch(row, [/data-duration-ms\s*=\s*["'](\d+)["']/i, /duration_ms\s*[=:]\s*["']?(\d+)/i]);
  if (millis) return Number(millis);
  var seconds = firstMatch(row, [/data-duration\s*=\s*["'](\d+)["']/i]);
  if (seconds) return Number(seconds) * 1000;
  var clock = row.match(/(?:재생시간|재생 시간)[^0-9]{0,80}(\d{1,3}):(\d{2})/i);
  if (clock) return (Number(clock[1]) * 60 + Number(clock[2])) * 1000;
  return 0;
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
    artist_id: artistInfo(row).id,
    album_name: albumName,
    album_id: albumId,
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

  if (tracks.length === 0) {
    var listItems = html.match(
      /<li[^>]*>[\s\S]*?<\/li>/gi
    ) || [];

    for (var j = 0; j < listItems.length; j++) {
      var listTrack = parseTrackRow(listItems[j]);

      if (!listTrack || !listTrack.id) {
        continue;
      }

      if (seen[listTrack.id]) {
        continue;
      }

      seen[listTrack.id] = true;
      tracks.push(listTrack);
    }
  }

  if (tracks.length === 0) {
    var divBlocks = html.match(
      /<div[^>]*>[\s\S]*?<\/div>/gi
    ) || [];

    for (var k = 0; k < divBlocks.length; k++) {
      var divTrack = parseTrackRow(divBlocks[k]);

      if (!divTrack || !divTrack.id) {
        continue;
      }

      if (seen[divTrack.id]) {
        continue;
      }

      seen[divTrack.id] = true;
      tracks.push(divTrack);
    }
  }

  return tracks;
}

function makeTrackResult(track) {
  return {
    id: String(track.id),
    uri: PROVIDER_ID + ":track:" + String(track.id),
    type: "track",
    name: track.name || "",
    artists: track.artists || "",
    artist_id: track.artist_id || "",
    artist_url: track.artist_id ? BASE_URL + "/artist/timeline.htm?artistId=" + track.artist_id : "",
    album_artist: track.album_artist || track.artists || "",
    album_name: track.album_name || "",
    album_id: track.album_id || "",
    album_url: track.album_id ? BASE_URL + "/album/detail.htm?albumId=" + track.album_id : "",
    album_uri: track.album_id ? "melon-music:album:" + String(track.album_id) : "",
    album: {
      id: String(track.album_id || ""),
      uri: track.album_id ? "melon-music:album:" + String(track.album_id) : "",
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
    release_date: track.release_date || "",
    track_number: Number(track.track_number || 0),
    disc_number: Number(track.disc_number || 0),
    total_tracks: Number(track.total_tracks || 0),
    genre: track.genre || "",
    composer: track.composer || "",
    label: track.label || "",
    external_urls: BASE_URL + "/song/detail.htm?songId=" + String(track.id),
    external_links: { melon: "https://www.melon.com/song/detail.htm?songId=" + String(track.id), source: "https://www.melon.com/song/detail.htm?songId=" + String(track.id) },
    provider_id: PROVIDER_ID
  };
}

function fetchHtml(url) {
  var response = http.get(url, {
    "User-Agent": "Mozilla/5.0",
    "Accept": "text/html,application/xhtml+xml"
  });
  if (!response || !response.ok) {
    throw new Error("Melon HTTP " + (response ? response.status : "no response") + ": " + url);
  }
  return response.body || "";
}

function safeTracks(url) {
  var html = fetchHtml(url);
  var tracks = parseTracks(html);
  if (!tracks.length) throw new Error("Melon song list was empty or unrecognized: " + url);
  return tracks;
}

function fillSearchCovers(tracks, query) {
  if (!tracks.some(function (track) { return !track.cover_url; })) return;
  try {
    var response = http.get(MOBILE_WEB_URL + "/search/mobile4web/searchsong_list.htm?keyword=" +
      encodeURIComponent(query) + "&startIndex=1&pageSize=" + tracks.length, {
      "User-Agent": MOBILE_USER_AGENT,
      "Accept": "text/html,application/xhtml+xml"
    });
    if (!response || !response.ok) return;
    var bySong = {}, byAlbum = {};
    (String(response.body || "").match(/<li\b[^>]*\bd-songId=["']\d+["'][^>]*>/gi) || []).forEach(function (tag) {
      var cover = normalizeCoverUrl(firstMatch(tag, [/\bd-albumImage=["']([^"']+)["']/i]));
      if (!cover) return;
      bySong[firstMatch(tag, [/\bd-songId=["'](\d+)["']/i])] = cover;
      byAlbum[firstMatch(tag, [/\bd-albumId=["'](\d+)["']/i])] = cover;
    });
    tracks.forEach(function (track) {
      track.cover_url = track.cover_url || bySong[track.id] || byAlbum[track.album_id] || "";
    });
  } catch (error) {
    log.warn("Melon search artwork unavailable: " + String(error.message || error));
  }
}

function getArtist(artistId) {
  var id = resourceId(artistId, "artist");
  var html = fetchHtml(BASE_URL + "/artist/timeline.htm?artistId=" + id);
  var name = pageMeta(html, "og:title");
  var actualId = firstMatch(pageMeta(html, "og:url"), [/artistId=(\d+)/i]);
  if (!name || (actualId && actualId !== id)) throw new Error("Melon artist metadata was unrecognized: " + id);
  var songs = safeTracks(BASE_URL + "/artist/song.htm?artistId=" + id + "&orderBy=POPULAR_SONG_LIST").slice(0, 50);
  var albumHtml = fetchHtml(BASE_URL + "/artist/album.htm?artistId=" + id);
  var items = albumHtml.match(/<li\b[^>]*class=["'][^"']*\balbum11_li\b[^"']*["'][^>]*>[\s\S]*?<\/li>/gi) || [];
  var albums = [], seen = {};
  for (var i = 0; i < items.length; i++) {
    var albumId = getAlbumId(items[i]);
    var title = firstMatch(items[i], [/<a\b[^>]*goAlbumDetail\([^>]*class=["'][^"']*\bellipsis\b[^"']*["'][^>]*>([\s\S]*?)<\/a>/i]);
    if (!albumId || !title || seen[albumId]) continue;
    seen[albumId] = true;
    var cover = getCoverUrl(items[i]);
    albums.push({ id: albumId, name: title, artists: name, artist_id: id, cover_url: cover, images: cover,
      release_date: firstMatch(items[i], [/<span\b[^>]*class=["']cnt_view["'][^>]*>([\s\S]*?)<\/span>/i]).replace(/\./g, "-"),
      total_tracks: 0, tracks: [], provider_id: PROVIDER_ID, item_type: "album" });
  }
  // Popular song rows have no artwork; reuse the covers of this artist's albums,
  // then the mobile search results for songs from older albums.
  var albumCovers = {};
  albums.forEach(function (album) { if (album.cover_url) albumCovers[album.id] = album.cover_url; });
  songs.forEach(function (song) { song.cover_url = song.cover_url || albumCovers[song.album_id] || ""; });
  if (songs.length) fillSearchCovers(songs, name);
  return { id: id, name: name, uri: PROVIDER_ID + ":artist:" + id, type: "artist", provider_id: PROVIDER_ID,
    image_url: normalizeCoverUrl(pageMeta(html, "og:image")), top_tracks: songs.map(makeTrackResult), albums: albums };
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
