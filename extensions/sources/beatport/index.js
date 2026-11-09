// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/beatport/index.js
// Inactive source import: no app integration or update trust policy is installed.

var PROVIDER = "beatport", resolved = {};

function id(value) {
    var raw = String(value || "").trim().replace(/^beatport:/, "");
    if (!/^[1-9]\d{0,14}$/.test(raw)) throw new Error("Invalid Beatport ID");
    return raw;
  }

function pref(value) { return value ? "beatport:" + id(value) : ""; }

function names(list) { return (list || []).map(function (a) { return String(a.name || ""); }).filter(Boolean).join(", "); }

function fail(response) {
    var data = {}; try { data = JSON.parse(response.body || "{}"); } catch (_) {}
    var verify = response.needsVerification || data.code === "VERIFICATION_REQUIRED";
    var error = new Error(verify ? "Verification required" : data.error || response.error || "Beatport request failed");
    error.needsVerification = !!verify;
    error.code = String(data.code || response.code || "");
    error.status = response.statusCode || response.status || 0;
    error.retryAfterSeconds = Math.max(0, Number(data.retry_after_seconds || response.retryAfterSeconds || 0));
    error.retryable = !!(data.retryable || response.retryable);
    throw error;
  }

function request(method, path, body, headers) {
    if (typeof session === "undefined" || typeof session.signedFetch !== "function") throw new Error("Mornye 5.3.0 or newer is required");
    var r = session.signedFetch(method, path, body || null, headers || {});
    if (!r || r.error || r.needsVerification || r.statusCode !== 200) fail(r || {});
    return JSON.parse(r.body || "{}");
  }

function get(path) {
    var parts = path.split("?"), route = parts[0].split("/"), body = {};
    if (route[0] === "search") body.action = "search";
    else {
      body.action = { tracks: "track", artists: "artist", releases: "release" }[route[0]];
      body.id = id(route[1]);
      if (route[2]) body.action = "artist-" + route[2];
    }
    if (parts[1]) parts[1].split("&").forEach(function (pair) {
      var i = pair.indexOf("="), key = pair.slice(0, i), value = decodeURIComponent(pair.slice(i + 1));
      if (["q", "type", "limit", "page"].indexOf(key) >= 0) body[key] = key === "limit" || key === "page" ? Number(value) : value;
    });
    return request("POST", "/btp/catalog", body);
  }

function track(t) {
    var title = String(t.title || "").trim(), mix = String(t.mix_name || "").trim();
    if (mix && title.toLowerCase().indexOf(mix.toLowerCase()) < 0) title += " (" + mix + ")";
    return { id: pref(t.id), name: title, artists: names(t.artists), album_name: t.album || "",
      album_artist: names(t.artists), artist_id: t.artists && t.artists.length ? pref(t.artists[0].id) : "",
      album_id: t.album_id ? pref(t.album_id) : "", album_url: t.album_id ? "https://www.beatport.com/release/release/" + t.album_id : "",
      duration_ms: Number(t.duration_ms) || 0, cover_url: t.cover || "", images: t.cover || "",
      release_date: t.release_date || "", track_number: Number(t.track_number) || 0, disc_number: 1,
      total_discs: 1, total_tracks: Number(t.total_tracks) || 0, isrc: t.isrc || "", upc: t.upc || "",
      explicit: t.explicit === true, provider_id: PROVIDER, item_type: "track", external_urls: t.url || "",
      external_links: { beatport: t.url || "" }, genre: t.genre || "", label: t.label || "",
      comment: [t.bpm ? "BPM: " + t.bpm : "", t.key ? "Key: " + t.key : "", t.camelot ? "Camelot: " + t.camelot : ""].filter(Boolean).join("; ") };
  }

function album(r) {
    var result = { id: pref(r.id), name: r.name || "", artists: names(r.artists), album_artist: names(r.artists),
      artist_id: r.artists && r.artists.length ? pref(r.artists[0].id) : "", cover_url: r.cover || "", images: r.cover || "",
      release_date: r.release_date || "", total_tracks: Number(r.total_tracks) || 0, album_type: "album",
      label: r.label || "", upc: r.upc || "", explicit: r.explicit === true, description: r.description || "",
      provider_id: PROVIDER, item_type: "album", external_urls: r.url || "", album_url: r.url || "" };
    result.tracks = (r.tracks || []).map(function (t) {
      var v = track(t); v.total_tracks = result.total_tracks; v.album_artist = result.artists || v.artists;
      v.upc = result.upc; return v;
    });
    return result;
  }

function artist(a) {
    return { id: pref(a.id), name: a.name || "", image_url: a.image || "", images: a.image || "", cover_url: a.image || "",
      provider_id: PROVIDER, item_type: "artist", external_urls: a.url || "", description: a.description || "" };
  }

function getArtist(value) {
    var cursor = /^artist-albums:([1-9]\d{0,14}):([1-9]\d{0,2})$/.exec(String(value));
    var aid = cursor ? id(cursor[1]) : id(value), page = cursor ? Number(cursor[2]) : 1;
    var releases = get("artists/" + aid + "/releases?limit=20&page=" + page);
    var result = cursor ? { id: pref(aid), provider_id: PROVIDER, item_type: "artist" } : artist(get("artists/" + aid));
    result.albums = (releases.releases || []).map(album);
    result.albums_next = releases.has_more && page < 100 ? "artist-albums:" + aid + ":" + (page + 1) : "";
    if (!cursor) result.top_tracks = (get("artists/" + aid + "/tracks?limit=20&page=1").tracks || []).map(track);
    return result;
  }

var __upstream_initialize = function () { return { success: true }; };
var __upstream_cleanup = function () { resolved = {}; };
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
