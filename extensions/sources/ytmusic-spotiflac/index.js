// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/ytmusic-spotiflac/index.js
// Inactive source import: no app integration or update trust policy is installed.

const CONFIG = {
  fetchTimeoutMs: 15000,
  maxRetries: 2,
  baseBackoffMs: 250,
  cacheTtlMs: 120000,
  cacheMaxEntries: 500,
  poTokenCacheMaxEntries: 200,
  thumbnailSize: 512,
  clientVersion: "1.20240801.01.00",
  debugRawJsonHead: 1200,
  maxResults: 12,
  allowlistHosts: [],
  yt1dResultsURL: "https://yt1d.io/results/",
  yt1dAjaxURL: "https://yt1d.io/wp-admin/admin-ajax.php",
  cobaltAudioURL: "https://api.zarz.moe/v1/dl/cobalt",
  youtubeWatchURL: "https://www.youtube.com/watch?v=",
  poTokenMode: "off",
  poTokenProviderURL: "",
  manualGvsPoToken: "",
  logLevel: "warn",
  homeCountry: "ID",
  poTokenFallbackTtlMs: 6 * 60 * 60 * 1000,
  // InnerTube ANDROID client config
  innerTubeApiKey: "AIzaSyA8eiZmM1FaDVjRy-df2KTyQ_vz_yYM39w",
  innerTubeClientVersion: "21.02.35",
  innerTubeUserAgent:
    "com.google.android.youtube/21.02.35 (Linux; U; Android 11) gzip",
  directAudioChunkSize: 1024 * 1024,
};

const USER_AGENTS = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.0",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:121.0) Gecko/20100101 Firefox/121.0",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.0",
  "Mozilla/5.0 (iPhone; CPU iPhone OS 17_2 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1",
  "Mozilla/5.0 (Linux; Android 14; SM-S918B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.6099.144 Mobile Safari/537.36",
];

function getRandomUserAgent() {
  return USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)];
}

function readSetting(settings, key, fallback) {
  if (!settings || typeof settings !== "object") return fallback;
  var value = settings[key];
  if (value === undefined || value === null) return fallback;
  return value;
}

const LOG_LEVELS = { debug: 10, info: 20, warn: 30, error: 40 };

function normalizeLogLevel(value) {
  var normalized = String(value || "")
    .trim()
    .toLowerCase();
  return Object.prototype.hasOwnProperty.call(LOG_LEVELS, normalized)
    ? normalized
    : "warn";
}

function L(level, ...args) {
  try {
    var normalizedLevel = normalizeLogLevel(level);
    if (LOG_LEVELS[normalizedLevel] < LOG_LEVELS[CONFIG.logLevel]) return;
    if (
      typeof log !== "undefined" &&
      typeof log[normalizedLevel] === "function"
    ) {
      log[normalizedLevel](...args);
    }
  } catch {}
}

function now() {
  return Date.now();
}

const _cache = new Map();

function cacheSet(k, v) {
  if (_cache.has(k)) _cache.delete(k);
  _cache.set(k, { v, t: now() });
  while (_cache.size > CONFIG.cacheMaxEntries) {
    var oldestKey = _cache.keys().next().value;
    _cache.delete(oldestKey);
  }
}

const _poTokenCache = new Map();

const _inflight = new Map();

function isString(v) {
  return typeof v === "string";
}

function normalizeUrl(u) {
  if (!isString(u)) return null;
  var s = u.trim();
  if (!s) return null;
  if (!/^https?:\/\//i.test(s)) return null;
  try {
    var parsed = new URL(s);
    if (
      Array.isArray(CONFIG.allowlistHosts) &&
      CONFIG.allowlistHosts.length > 0
    ) {
      if (
        CONFIG.allowlistHosts.indexOf(parsed.hostname) === -1 &&
        !/^https?:\/\//i.test(parsed.protocol + "//")
      ) {
        // no-op, primary check already ensures http(s)
      }
    }
    return parsed.toString();
  } catch (e) {
    return null;
  }
}

function normalizePoTokenProviderURL(value) {
  var raw = String(value || "").trim();
  if (!raw) return "";
  try {
    var parsed = new URL(raw);
    if (parsed.protocol !== "http:" && parsed.protocol !== "https:") return "";
    var text = parsed.toString().replace(/\/+$/, "");
    if (!/\/get_pot$/i.test(text)) text += "/get_pot";
    return text;
  } catch (e) {
    return "";
  }
}

function makeSquareThumb(url) {
  var u = normalizeUrl(url);
  if (!u) return null;
  try {
    var replaced = u
      .replace(
        /=w\d+-h\d+/g,
        "=w" + CONFIG.thumbnailSize + "-h" + CONFIG.thumbnailSize,
      )
      .replace(/\/s\d+-c/g, "/s" + CONFIG.thumbnailSize + "-c");
    return normalizeUrl(replaced);
  } catch (e) {
    return null;
  }
}

function parseDurationText(t) {
  if (!t) return 0;
  var m = String(t).match(/(\d{1,2}:)?\d{1,2}:\d{2}|\d{1,2}:\d{2}/);
  if (!m) return 0;
  var parts = m[0].split(":").map(function (x) {
    return parseInt(x, 10);
  });
  if (
    parts.some(function (p) {
      return isNaN(p);
    })
  )
    return 0;
  var s = 0;
  for (var i = 0; i < parts.length; i++) s = s * 60 + parts[i];
  return s;
}

function extractVideoIdFromEndpoint(ep) {
  try {
    if (!ep) return null;
    if (ep.watchEndpoint && ep.watchEndpoint.videoId)
      return ep.watchEndpoint.videoId;
    if (
      ep.commandMetadata &&
      ep.commandMetadata.webCommandMetadata &&
      ep.commandMetadata.webCommandMetadata.url
    ) {
      var m = String(ep.commandMetadata.webCommandMetadata.url).match(
        /v=([^&]+)/,
      );
      if (m) return m[1];
    }
    if (ep.browseEndpoint && ep.browseEndpoint.browseId)
      return ep.browseEndpoint.browseId;
    return null;
  } catch (e) {
    return null;
  }
}

function extractBrowseInfoFromEndpoint(ep) {
  try {
    if (!ep) return null;
    if (ep.browseEndpoint && ep.browseEndpoint.browseId) {
      var browseId = ep.browseEndpoint.browseId;
      var type = "unknown";
      if (browseId.startsWith("MPREb_")) type = "album";
      else if (
        browseId.startsWith("VLPL") ||
        browseId.startsWith("VL") ||
        browseId.startsWith("PL")
      )
        type = "playlist";
      else if (browseId.startsWith("VLRDCLAK5uy_")) type = "playlist";
      else if (browseId.startsWith("UC")) type = "artist";
      return { browseId: browseId, type: type };
    }
    return null;
  } catch (e) {
    return null;
  }
}

function normalizeCandidate(info) {
  if (!info) return null;
  if (info.musicResponsiveListItemRenderer)
    return info.musicResponsiveListItemRenderer;
  if (info.musicTwoRowItemRenderer) return info.musicTwoRowItemRenderer;
  if (info.musicCardRenderer) return info.musicCardRenderer;
  if (info.videoRenderer) return info.videoRenderer;
  if (info.richItemRenderer && info.richItemRenderer.content)
    return info.richItemRenderer.content;
  if (info.playlistPanelVideoRenderer) return info.playlistPanelVideoRenderer;
  return info;
}

function pickLastThumbnailUrl(thumbnailObj) {
  try {
    if (!thumbnailObj) return null;
    if (Array.isArray(thumbnailObj)) {
      if (thumbnailObj.length === 0) return null;
      var last = thumbnailObj[thumbnailObj.length - 1];
      return last && last.url ? last.url : null;
    }
    if (
      thumbnailObj.thumbnails &&
      Array.isArray(thumbnailObj.thumbnails) &&
      thumbnailObj.thumbnails.length
    ) {
      var l = thumbnailObj.thumbnails[thumbnailObj.thumbnails.length - 1];
      return l && l.url ? l.url : null;
    }
    return null;
  } catch (e) {
    return null;
  }
}

function runsText(runs, separator) {
  if (!Array.isArray(runs)) return "";
  return runs
    .map(function (run) {
      return run && run.text ? String(run.text) : "";
    })
    .join(separator === undefined ? "" : separator)
    .trim();
}

function uniqueStrings(values) {
  var seen = {};
  var out = [];
  for (var i = 0; i < values.length; i++) {
    var value = String(values[i] || "").trim();
    var key = value.toLowerCase();
    if (!value || seen[key]) continue;
    seen[key] = true;
    out.push(value);
  }
  return out;
}

function browsePageType(endpoint) {
  try {
    return String(
      endpoint.browseEndpointContextSupportedConfigs
        .browseEndpointContextMusicConfig.pageType || "",
    );
  } catch (e) {
    return "";
  }
}

function collectTrackReferences(node) {
  var result = {
    artists: [],
    album_id: "",
    album_name: "",
    credits_id: "",
  };
  var seenArtists = {};

  function visit(value, depth) {
    if (!value || typeof value !== "object" || depth > 14) return;
    if (value.browseEndpoint && value.browseEndpoint.browseId) {
      var endpoint = value.browseEndpoint;
      var browseId = String(endpoint.browseId);
      var pageType = browsePageType(endpoint);
      var text = value.__runText || "";
      if (
        (browseId.startsWith("UC") || pageType === "MUSIC_PAGE_TYPE_ARTIST") &&
        text
      ) {
        if (!seenArtists[browseId]) {
          seenArtists[browseId] = true;
          result.artists.push({ id: browseId, name: text });
        }
      } else if (
        (browseId.startsWith("MPREb_") ||
          pageType === "MUSIC_PAGE_TYPE_ALBUM") &&
        !result.album_id
      ) {
        result.album_id = browseId;
        result.album_name = text;
      } else if (
        (browseId.startsWith("MPTC") ||
          pageType === "MUSIC_PAGE_TYPE_TRACK_CREDITS") &&
        !result.credits_id
      ) {
        result.credits_id = browseId;
      }
    }

    if (Array.isArray(value)) {
      for (var i = 0; i < value.length; i++) visit(value[i], depth + 1);
      return;
    }
    for (var key in value) {
      if (!Object.prototype.hasOwnProperty.call(value, key)) continue;
      var child = value[key];
      if (key === "navigationEndpoint" && child && typeof child === "object") {
        var decorated = Object.assign({}, child);
        if (typeof value.text === "string")
          decorated.__runText = value.text.trim();
        visit(decorated, depth + 1);
      } else if (key !== "trackingParams" && key !== "clickTrackingParams") {
        visit(child, depth + 1);
      }
    }
  }

  visit(node, 0);
  return result;
}

function hasExplicitBadge(node) {
  try {
    var badges = node && node.badges;
    if (!Array.isArray(badges)) return false;
    for (var i = 0; i < badges.length; i++) {
      var badge = badges[i] || {};
      var inline = badge.musicInlineBadgeRenderer || {};
      var metadata = badge.metadataBadgeRenderer || {};
      var iconType =
        (inline.icon && inline.icon.iconType) ||
        (metadata.icon && metadata.icon.iconType) ||
        "";
      var label =
        (inline.accessibilityData &&
          inline.accessibilityData.accessibilityData &&
          inline.accessibilityData.accessibilityData.label) ||
        metadata.label ||
        "";
      if (
        String(iconType).toUpperCase().indexOf("EXPLICIT") >= 0 ||
        String(label).toLowerCase() === "explicit"
      ) {
        return true;
      }
    }
  } catch (e) {}
  return false;
}

function parseItemExtended(info) {
  try {
    if (!info) return null;
    var c = normalizeCandidate(info);
    if (!c) return null;
    var references = collectTrackReferences(c);

    var title = null;
    if (c.flexColumns && Array.isArray(c.flexColumns)) {
      for (var fi = 0; fi < c.flexColumns.length; fi++) {
        var fc = c.flexColumns[fi];
        if (fc && fc.musicResponsiveListItemFlexColumnRenderer) {
          var fcr = fc.musicResponsiveListItemFlexColumnRenderer;
          if (fcr.text && fcr.text.runs && fcr.text.runs[0]) {
            if (!title) title = fcr.text.runs[0].text;
          }
        }
      }
    }

    if (
      !title &&
      c.title &&
      c.title.runs &&
      c.title.runs[0] &&
      c.title.runs[0].text
    )
      title = c.title.runs[0].text;
    if (!title && c.title && c.title.simpleText) title = c.title.simpleText;
    if (
      !title &&
      c.titleText &&
      c.titleText.runs &&
      c.titleText.runs[0] &&
      c.titleText.runs[0].text
    )
      title = c.titleText.runs[0].text;
    if (!title && c.name && c.name.simpleText) title = c.name.simpleText;
    if (!title && c.video && c.video.title) title = c.video.title;
    if (!title && c.header && c.header.title && c.header.title.runs)
      title = c.header.title.runs
        .map(function (r) {
          return r.text;
        })
        .join(" ");

    var artist = "";
    if (
      c.flexColumns &&
      Array.isArray(c.flexColumns) &&
      c.flexColumns.length > 1
    ) {
      var fc2 = c.flexColumns[1];
      if (fc2 && fc2.musicResponsiveListItemFlexColumnRenderer) {
        var fcr2 = fc2.musicResponsiveListItemFlexColumnRenderer;
        if (fcr2.text && fcr2.text.runs) {
          var artistParts = [];
          for (var ri = 0; ri < fcr2.text.runs.length; ri++) {
            var run = fcr2.text.runs[ri];
            if (run && run.text) {
              var txt = run.text.trim();
              if (txt === "•" || txt === " • " || txt === "," || txt === " & ")
                continue;
              var lowerTxt = txt.toLowerCase();
              if (
                lowerTxt === "single" ||
                lowerTxt === "album" ||
                lowerTxt === "ep" ||
                lowerTxt === "playlist" ||
                lowerTxt === "video" ||
                lowerTxt === "song"
              )
                continue;
              if (/^\d{4}$/.test(txt)) continue;
              if (
                /^\d+(\.\d+)?[KMB]?\s*(views|plays|listeners|subscribers|monthly audience)/i.test(
                  txt,
                )
              )
                continue;
              if (/^\d{1,2}:\d{2}(:\d{2})?$/.test(txt)) continue;
              if (
                run.navigationEndpoint &&
                run.navigationEndpoint.browseEndpoint
              ) {
                var artistBrowse = run.navigationEndpoint.browseEndpoint;
                if (
                  String(artistBrowse.browseId || "").startsWith("UC") ||
                  browsePageType(artistBrowse) === "MUSIC_PAGE_TYPE_ARTIST"
                ) {
                  artistParts.push(txt);
                }
              } else if (!run.navigationEndpoint) {
                if (txt.length > 1) artistParts.push(txt);
              }
            }
          }
          artist = artistParts.join(", ");
        }
      }
    }

    if (!artist && c.subtitle && c.subtitle.runs) {
      var subtitleParts = [];
      for (var si = 0; si < c.subtitle.runs.length; si++) {
        var srun = c.subtitle.runs[si];
        if (srun && srun.text) {
          var stxt = srun.text.trim();
          if (stxt === "•" || stxt === " • " || stxt === "," || stxt === " & ")
            continue;
          var lowerStxt = stxt.toLowerCase();
          if (
            lowerStxt === "single" ||
            lowerStxt === "album" ||
            lowerStxt === "ep" ||
            lowerStxt === "playlist" ||
            lowerStxt === "video" ||
            lowerStxt === "song"
          )
            continue;
          if (/^\d{4}$/.test(stxt)) continue;
          // Skip view/play counts (e.g., "159M views", "1.1B plays", "241M plays")
          if (
            /^\d+(\.\d+)?[KMB]?\s*(views|plays|listeners|subscribers|monthly audience)/i.test(
              stxt,
            )
          )
            continue;
          // Skip duration format (e.g., "3:06", "10:45", "1:23:45")
          if (/^\d{1,2}:\d{2}(:\d{2})?$/.test(stxt)) continue;
          if (
            srun.navigationEndpoint &&
            srun.navigationEndpoint.browseEndpoint
          ) {
            var subtitleBrowse = srun.navigationEndpoint.browseEndpoint;
            if (
              String(subtitleBrowse.browseId || "").startsWith("UC") ||
              browsePageType(subtitleBrowse) === "MUSIC_PAGE_TYPE_ARTIST"
            ) {
              subtitleParts.push(stxt);
            }
          } else if (stxt.length > 1) {
            subtitleParts.push(stxt);
          }
        }
      }
      artist = subtitleParts.join(", ");
    }
    if (!artist && c.longBylineText && c.longBylineText.runs)
      artist = c.longBylineText.runs
        .map(function (r) {
          return r.text;
        })
        .join(" ");
    if (!artist && c.ownerText && c.ownerText.runs)
      artist = c.ownerText.runs
        .map(function (r) {
          return r.text;
        })
        .join(" ");
    if (references.artists.length > 0) {
      artist = uniqueStrings(
        references.artists.map(function (item) {
          return item.name;
        }),
      ).join(", ");
    }

    if (!artist) {
      L("debug", "parseItemExtended: no artist found for", title);
    }

    var album = "";
    if (
      c.flexColumns &&
      Array.isArray(c.flexColumns) &&
      c.flexColumns.length > 1
    ) {
      var fc2 = c.flexColumns[1];
      if (fc2 && fc2.musicResponsiveListItemFlexColumnRenderer) {
        var fcr2 = fc2.musicResponsiveListItemFlexColumnRenderer;
        if (fcr2.text && fcr2.text.runs) {
          for (var ri = 0; ri < fcr2.text.runs.length; ri++) {
            var run = fcr2.text.runs[ri];
            if (
              run &&
              run.text &&
              run.navigationEndpoint &&
              run.navigationEndpoint.browseEndpoint
            ) {
              var browseId =
                run.navigationEndpoint.browseEndpoint.browseId || "";
              if (browseId.startsWith("MPREb_")) {
                album = run.text.trim();
                L(
                  "debug",
                  "parseItemExtended: found album from flexColumns",
                  album,
                );
                break;
              }
            }
          }
        }
      }
    }

    if (!album && c.subtitle && c.subtitle.runs) {
      for (var si = 0; si < c.subtitle.runs.length; si++) {
        var srun = c.subtitle.runs[si];
        if (
          srun &&
          srun.text &&
          srun.navigationEndpoint &&
          srun.navigationEndpoint.browseEndpoint
        ) {
          var sBrowseId = srun.navigationEndpoint.browseEndpoint.browseId || "";
          if (sBrowseId.startsWith("MPREb_")) {
            album = srun.text.trim();
            L("debug", "parseItemExtended: found album from subtitle", album);
            break;
          }
        }
      }
    }
    if (references.album_name) album = references.album_name;

    var videoId = null;
    if (c.playlistItemData && c.playlistItemData.videoId)
      videoId = c.playlistItemData.videoId;
    if (!videoId && c.videoId) videoId = c.videoId;
    if (
      !videoId &&
      c.overlay &&
      c.overlay.musicItemThumbnailOverlayRenderer &&
      c.overlay.musicItemThumbnailOverlayRenderer.content &&
      c.overlay.musicItemThumbnailOverlayRenderer.content
        .musicPlayButtonRenderer
    ) {
      var mpbr =
        c.overlay.musicItemThumbnailOverlayRenderer.content
          .musicPlayButtonRenderer;
      if (mpbr.playNavigationEndpoint)
        videoId = extractVideoIdFromEndpoint(mpbr.playNavigationEndpoint);
    }
    if (!videoId && c.navigationEndpoint)
      videoId = extractVideoIdFromEndpoint(c.navigationEndpoint);
    if (
      !videoId &&
      c.thumbnail &&
      c.thumbnail.musicThumbnailRenderer &&
      c.thumbnail.musicThumbnailRenderer.navigationEndpoint
    )
      videoId = extractVideoIdFromEndpoint(
        c.thumbnail.musicThumbnailRenderer.navigationEndpoint,
      );
    if (!videoId && c.video && c.video.videoId) videoId = c.video.videoId;

    if (!title || !videoId) {
      if (Math.random() < 0.1)
        L("debug", "parseItemExtended failed", {
          hasTitle: !!title,
          hasVideoId: !!videoId,
          keys: Object.keys(c).slice(0, 5),
        });
      return null;
    }
    var durationText = "";
    if (c.lengthText && c.lengthText.simpleText)
      durationText = c.lengthText.simpleText;
    // Watch-next queue rows (playlistPanelVideoRenderer) carry runs instead.
    if (!durationText && c.lengthText && c.lengthText.runs)
      durationText = runsText(c.lengthText.runs, "");
    if (
      !durationText &&
      c.thumbnailOverlays &&
      c.thumbnailOverlays[0] &&
      c.thumbnailOverlays[0].thumbnailOverlayTimeStatusRenderer &&
      c.thumbnailOverlays[0].thumbnailOverlayTimeStatusRenderer.text &&
      c.thumbnailOverlays[0].thumbnailOverlayTimeStatusRenderer.text.simpleText
    ) {
      durationText =
        c.thumbnailOverlays[0].thumbnailOverlayTimeStatusRenderer.text
          .simpleText;
    }
    if (!durationText && c.badges && c.badges.length) {
      for (var bi = 0; bi < c.badges.length; bi++) {
        var b = c.badges[bi];
        if (b && b.metadataBadgeRenderer && b.metadataBadgeRenderer.label) {
          durationText = String(b.metadataBadgeRenderer.label);
          break;
        }
      }
    }
    if (!durationText && c.fixedColumns && Array.isArray(c.fixedColumns)) {
      for (var dfi = 0; dfi < c.fixedColumns.length; dfi++) {
        var dfc = c.fixedColumns[dfi];
        if (dfc && dfc.musicResponsiveListItemFixedColumnRenderer) {
          var dfcr = dfc.musicResponsiveListItemFixedColumnRenderer;
          if (
            dfcr.text &&
            dfcr.text.runs &&
            dfcr.text.runs[0] &&
            dfcr.text.runs[0].text
          ) {
            var possibleDuration = dfcr.text.runs[0].text.trim();
            if (/^\d{1,2}:\d{2}(:\d{2})?$/.test(possibleDuration)) {
              durationText = possibleDuration;
              L(
                "debug",
                "parseItemExtended: found duration from fixedColumns",
                durationText,
              );
              break;
            }
          }
          if (!durationText && dfcr.text && dfcr.text.simpleText) {
            var possibleDuration2 = dfcr.text.simpleText.trim();
            if (/^\d{1,2}:\d{2}(:\d{2})?$/.test(possibleDuration2)) {
              durationText = possibleDuration2;
              L(
                "debug",
                "parseItemExtended: found duration from fixedColumns simpleText",
                durationText,
              );
              break;
            }
          }
        }
      }
    }
    if (
      !durationText &&
      c.flexColumns &&
      Array.isArray(c.flexColumns) &&
      c.flexColumns.length > 1
    ) {
      var fc3 = c.flexColumns[1];
      if (fc3 && fc3.musicResponsiveListItemFlexColumnRenderer) {
        var fcr3 = fc3.musicResponsiveListItemFlexColumnRenderer;
        if (fcr3.text && fcr3.text.runs) {
          for (var dri = 0; dri < fcr3.text.runs.length; dri++) {
            var drun = fcr3.text.runs[dri];
            if (drun && drun.text) {
              var dtxt = drun.text.trim();
              if (/^\d{1,2}:\d{2}(:\d{2})?$/.test(dtxt)) {
                durationText = dtxt;
                L(
                  "debug",
                  "parseItemExtended: found duration from flexColumns",
                  durationText,
                );
                break;
              }
            }
          }
        }
      }
    }
    var duration = parseDurationText(durationText);
    var thumbRaw = null;
    thumbRaw =
      thumbRaw ||
      pickLastThumbnailUrl(
        (c.thumbnail &&
          c.thumbnail.musicThumbnailRenderer &&
          c.thumbnail.musicThumbnailRenderer.thumbnail &&
          c.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails) ||
          null,
      );
    thumbRaw =
      thumbRaw ||
      pickLastThumbnailUrl((c.thumbnail && c.thumbnail.thumbnails) || null);
    thumbRaw =
      thumbRaw ||
      pickLastThumbnailUrl(
        (c.video && c.video.thumbnail && c.video.thumbnail.thumbnails) || null,
      );
    thumbRaw =
      thumbRaw ||
      pickLastThumbnailUrl(
        (c.thumbnail &&
          c.thumbnail.thumbnail &&
          c.thumbnail.thumbnail.thumbnails) ||
          null,
      );
    thumbRaw =
      thumbRaw ||
      pickLastThumbnailUrl(
        (c.thumbnail && c.thumbnail.thumbnails && c.thumbnail.thumbnails) ||
          null,
      );
    if (!thumbRaw && c.fixedColumns) {
      for (var fi = 0; fi < c.fixedColumns.length; fi++) {
        var fc = c.fixedColumns[fi];
        if (
          fc &&
          fc.musicResponsiveListItemFixedColumnRenderer &&
          fc.musicResponsiveListItemFixedColumnRenderer.thumbnail
        ) {
          thumbRaw = pickLastThumbnailUrl(
            fc.musicResponsiveListItemFixedColumnRenderer.thumbnail.thumbnails,
          );
          if (thumbRaw) break;
        }
      }
    }
    var thumb = makeSquareThumb(thumbRaw);
    thumb = normalizeUrl(thumb) || null;
    return {
      id: String(videoId),
      title: String(title),
      artist: String(artist || ""),
      album: String(album || ""),
      album_artist: "",
      artist_id: references.artists.length ? references.artists[0].id : "",
      artist_url: references.artists.length
        ? "https://music.youtube.com/channel/" + references.artists[0].id
        : "",
      album_id: references.album_id,
      album_url: references.album_id
        ? "https://music.youtube.com/browse/" + references.album_id
        : "",
      external_urls: "https://music.youtube.com/watch?v=" + String(videoId),
      external_links: {
        youtube: "https://music.youtube.com/watch?v=" + String(videoId),
      },
      duration: Number(duration || 0),
      thumbnail: thumb,
      explicit: hasExplicitBadge(c),
      credits_id: references.credits_id || "MPTC" + String(videoId),
      source: "youtube",
      item_type: "track",
    };
  } catch (e) {
    L("warn", "parseItemExtended error", String(e));
    return null;
  }
}

function parseCollectionItem(info) {
  try {
    if (!info) return null;
    var c = normalizeCandidate(info);
    if (!c) return null;

    var browseInfo = null;
    if (c.navigationEndpoint) {
      browseInfo = extractBrowseInfoFromEndpoint(c.navigationEndpoint);
    }
    if (
      !browseInfo &&
      c.overlay &&
      c.overlay.musicItemThumbnailOverlayRenderer
    ) {
      var overlay = c.overlay.musicItemThumbnailOverlayRenderer;
      if (
        overlay.content &&
        overlay.content.musicPlayButtonRenderer &&
        overlay.content.musicPlayButtonRenderer.playNavigationEndpoint
      ) {
        browseInfo = extractBrowseInfoFromEndpoint(
          overlay.content.musicPlayButtonRenderer.playNavigationEndpoint,
        );
      }
    }

    // Only process albums, playlists, and artists
    if (
      !browseInfo ||
      (browseInfo.type !== "album" &&
        browseInfo.type !== "playlist" &&
        browseInfo.type !== "artist")
    ) {
      return null;
    }

    // Extract title
    var title = null;
    if (c.flexColumns && Array.isArray(c.flexColumns)) {
      for (var fi = 0; fi < c.flexColumns.length; fi++) {
        var fc = c.flexColumns[fi];
        if (fc && fc.musicResponsiveListItemFlexColumnRenderer) {
          var fcr = fc.musicResponsiveListItemFlexColumnRenderer;
          if (fcr.text && fcr.text.runs && fcr.text.runs[0]) {
            if (!title) title = fcr.text.runs[0].text;
          }
        }
      }
    }
    if (!title && c.title && c.title.runs && c.title.runs[0])
      title = c.title.runs[0].text;
    if (!title && c.title && c.title.simpleText) title = c.title.simpleText;

    var subtitle = "";
    var albumType = browseInfo.type === "album" ? "album" : "playlist";
    var year = "";
    var artist = "";

    if (
      c.flexColumns &&
      Array.isArray(c.flexColumns) &&
      c.flexColumns.length > 1
    ) {
      var fc2 = c.flexColumns[1];
      if (fc2 && fc2.musicResponsiveListItemFlexColumnRenderer) {
        var fcr2 = fc2.musicResponsiveListItemFlexColumnRenderer;
        if (fcr2.text && fcr2.text.runs) {
          subtitle = fcr2.text.runs
            .map(function (r) {
              return r.text;
            })
            .join("");
        }
      }
    }
    if (!subtitle && c.subtitle && c.subtitle.runs) {
      subtitle = c.subtitle.runs
        .map(function (r) {
          return r.text;
        })
        .join("");
    }

    if (subtitle) {
      var parts = subtitle.split(" • ");
      if (parts.length >= 1) {
        var typeStr = parts[0].toLowerCase().trim();
        if (typeStr === "album" || typeStr === "single" || typeStr === "ep") {
          albumType = typeStr === "ep" ? "ep" : typeStr;
        } else if (typeStr === "playlist") {
          albumType = "playlist";
        }
      }
      if (parts.length >= 2) {
        artist = parts[1].trim();
      }
      if (parts.length >= 3) {
        var maybeYear = parts[2].trim();
        if (/^\d{4}$/.test(maybeYear)) {
          year = maybeYear;
        }
      }
    }

    var thumbRaw = null;
    thumbRaw =
      thumbRaw ||
      pickLastThumbnailUrl(
        (c.thumbnail &&
          c.thumbnail.musicThumbnailRenderer &&
          c.thumbnail.musicThumbnailRenderer.thumbnail &&
          c.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails) ||
          null,
      );
    thumbRaw =
      thumbRaw ||
      pickLastThumbnailUrl((c.thumbnail && c.thumbnail.thumbnails) || null);
    thumbRaw =
      thumbRaw ||
      pickLastThumbnailUrl(
        (c.thumbnailRenderer &&
          c.thumbnailRenderer.musicThumbnailRenderer &&
          c.thumbnailRenderer.musicThumbnailRenderer.thumbnail &&
          c.thumbnailRenderer.musicThumbnailRenderer.thumbnail.thumbnails) ||
          null,
      );
    if (!thumbRaw && c.thumbnail && c.thumbnail.musicThumbnailRenderer) {
      var mtr = c.thumbnail.musicThumbnailRenderer;
      if (mtr.thumbnail && mtr.thumbnail.thumbnails) {
        thumbRaw = pickLastThumbnailUrl(mtr.thumbnail.thumbnails);
      }
    }
    var thumb = makeSquareThumb(thumbRaw);
    thumb = normalizeUrl(thumb) || null;
    L("debug", "parseCollectionItem thumbnail", {
      id: browseInfo ? browseInfo.browseId : "null",
      thumbRaw: thumbRaw,
      thumb: thumb,
    });

    if (!title || !browseInfo.browseId) {
      return null;
    }

    // Determine item_type
    var itemType = "album";
    if (browseInfo.type === "playlist") itemType = "playlist";
    else if (browseInfo.type === "artist") itemType = "artist";

    L("info", "parseCollectionItem returning", {
      id: browseInfo.browseId,
      title: title,
      item_type: itemType,
      browseType: browseInfo.type,
    });

    return {
      id: browseInfo.browseId,
      title: String(title),
      artist: String(artist || ""),
      album_type: browseInfo.type === "artist" ? "artist" : albumType,
      year: year,
      thumbnail: thumb,
      item_type: itemType,
      source: "youtube",
    };
  } catch (e) {
    L("warn", "parseCollectionItem error", String(e));
    return null;
  }
}

var COLLECT_ITEMS_MAX = 5000;

function collectItemsFromNode(node, out, depth) {
  depth = depth || 0;
  // Prevent infinite recursion - max depth 20
  if (depth > 20) return;
  // Safety exit with high cap (was 100, now 5000)
  if (out.length >= COLLECT_ITEMS_MAX) return;

  if (!node || typeof node !== "object") return;
  if (Array.isArray(node)) {
    for (var i = 0; i < node.length && out.length < COLLECT_ITEMS_MAX; i++)
      collectItemsFromNode(node[i], out, depth + 1);
    return;
  }
  if (
    node.videoRenderer ||
    node.musicResponsiveListItemRenderer ||
    node.musicTwoRowItemRenderer ||
    node.musicCardRenderer ||
    (node.richItemRenderer && node.richItemRenderer.content) ||
    node.playlistPanelVideoRenderer ||
    node.musicCardShelfRenderer
  ) {
    out.push(node);
  }
  for (var k in node) {
    if (!Object.prototype.hasOwnProperty.call(node, k)) continue;
    if (out.length >= COLLECT_ITEMS_MAX) break;
    var v = node[k];
    if (!v) continue;
    if (Array.isArray(v)) {
      for (var ai = 0; ai < v.length && out.length < COLLECT_ITEMS_MAX; ai++)
        collectItemsFromNode(v[ai], out, depth + 1);
    } else if (typeof v === "object") {
      collectItemsFromNode(v, out, depth + 1);
    }
  }
}

function sanitizeTrackBeforeReturn(t) {
  if (!t || typeof t !== "object") return null;
  var id = t.id ? String(t.id).trim() : "";
  if (!id) return null;

  // If this is a collection (album/playlist/artist), use different sanitization
  if (
    t.item_type === "album" ||
    t.item_type === "playlist" ||
    t.item_type === "artist"
  ) {
    return sanitizeCollectionBeforeReturn(t);
  }

  var title = t.title ? String(t.title).trim() : "Unknown title";
  var artist = t.artist ? String(t.artist).trim() : "";
  var thumbCandidate = t.thumbnail || t.coverUrl || null;
  var thumb = normalizeUrl(thumbCandidate) || null;

  var sanitized = {
    id: id,
    name: title, // Mornye expects 'name' not 'title'
    artists: artist, // Mornye expects 'artists' not 'artist'
    album_name: t.album ? String(t.album).trim() : "",
    album_artist: String(t.album_artist || "").trim(),
    artist_id: String(t.artist_id || "").trim(),
    artist_url: String(t.artist_url || "").trim(),
    album_id: String(t.album_id || "").trim(),
    album_url: String(t.album_url || "").trim(),
    external_urls: String(
      t.external_urls || "https://music.youtube.com/watch?v=" + id,
    ).trim(),
    external_links: Object.assign(
      { youtube: "https://music.youtube.com/watch?v=" + id },
      t.external_links || {},
    ),
    duration_ms: (Number(t.duration || 0) || 0) * 1000, // Convert seconds to ms
    cover_url: thumb, // Mornye expects 'cover_url' not 'thumbnail'
    track_number: Number(t.track_number || 0) || 0,
    total_tracks: Number(t.total_tracks || 0) || 0,
    disc_number: Number(t.disc_number || 0) || 0,
    total_discs: Number(t.total_discs || 0) || 0,
    release_date: String(t.release_date || "").trim(),
    album_type: String(t.album_type || "").trim(),
    isrc: String(t.isrc || "").trim(),
    upc: String(t.upc || "").trim(),
    label: String(t.label || "").trim(),
    copyright: String(t.copyright || "").trim(),
    genre: String(t.genre || "").trim(),
    composer: String(t.composer || "").trim(),
    preview_url: String(t.preview_url || "").trim(),
    explicit: t.explicit === true,
    provider_id: "ytmusic-spotiflac",
    item_type: "track",
  };
  cacheSet("yt:video:" + id, sanitized);
  return sanitized;
}

function sanitizeCollectionBeforeReturn(t) {
  if (!t || typeof t !== "object") return null;
  var id = t.id ? String(t.id).trim() : "";
  if (!id) return null;

  var title = t.title ? String(t.title).trim() : "Unknown";
  var artist = t.artist ? String(t.artist).trim() : "";
  var thumbCandidate = t.thumbnail || t.coverUrl || null;
  var thumb = normalizeUrl(thumbCandidate) || null;

  var finalItemType = t.item_type || "album";
  L("info", "sanitizeCollectionBeforeReturn", {
    id: id,
    name: title,
    input_item_type: t.item_type,
    final_item_type: finalItemType,
  });

  return {
    id: id,
    name: title,
    artists: artist,
    album_name: title,
    album_type:
      t.album_type || (t.item_type === "playlist" ? "playlist" : "album"),
    release_date: t.year || "",
    cover_url: thumb,
    provider_id: "ytmusic-spotiflac",
    item_type: finalItemType,
  };
}

function getArtist(artistId) {
  L("info", "getArtist called", artistId);
  try {
    var url = "https://music.youtube.com/youtubei/v1/browse?alt=json";
    var body = JSON.stringify({
      context: {
        client: {
          clientName: "WEB_REMIX",
          clientVersion: CONFIG.clientVersion,
        },
      },
      browseId: artistId,
    });

    var res = fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "User-Agent": getRandomUserAgent(),
        "x-youtube-client-name": "WEB_REMIX",
        "x-youtube-client-version": CONFIG.clientVersion,
      },
      body: body,
    });

    if (!res || !res.ok) {
      L("error", "getArtist fetch failed", res ? res.status : "no response");
      return null;
    }

    var data = res.json();
    if (!data) {
      L("error", "getArtist json parse failed");
      return null;
    }

    var artistName = "";
    var artistImage = null;
    var headerImage = null;
    var monthlyListeners = null;

    if (data.header) {
      var header =
        data.header.musicImmersiveHeaderRenderer ||
        data.header.musicVisualHeaderRenderer ||
        data.header.musicDetailHeaderRenderer;
      if (header) {
        if (header.title && header.title.runs) {
          artistName = header.title.runs
            .map(function (r) {
              return r.text;
            })
            .join("");
        }
        if (
          header.thumbnail &&
          header.thumbnail.musicThumbnailRenderer &&
          header.thumbnail.musicThumbnailRenderer.thumbnail
        ) {
          var thumbUrl = pickLastThumbnailUrl(
            header.thumbnail.musicThumbnailRenderer.thumbnail.thumbnails,
          );
          artistImage = makeSquareThumb(thumbUrl);
        }
        if (
          !artistImage &&
          header.foregroundThumbnail &&
          header.foregroundThumbnail.musicThumbnailRenderer
        ) {
          var thumbUrl2 = pickLastThumbnailUrl(
            header.foregroundThumbnail.musicThumbnailRenderer.thumbnail
              .thumbnails,
          );
          artistImage = makeSquareThumb(thumbUrl2);
        }
        if (
          header.subscriptionButton &&
          header.subscriptionButton.subscribeButtonRenderer
        ) {
          var subButton = header.subscriptionButton.subscribeButtonRenderer;
          if (
            subButton.subscriberCountText &&
            subButton.subscriberCountText.runs
          ) {
            var subText = subButton.subscriberCountText.runs
              .map(function (r) {
                return r.text;
              })
              .join("");
            var subMatch = subText.match(/^([\d.]+)([KMB])?/i);
            if (subMatch) {
              var num = parseFloat(subMatch[1]);
              var mult = subMatch[2] ? subMatch[2].toUpperCase() : "";
              if (mult === "K") num *= 1000;
              else if (mult === "M") num *= 1000000;
              else if (mult === "B") num *= 1000000000;
              monthlyListeners = Math.round(num);
            }
          }
        }
      }
    }

    var topTracks = [];
    var albums = [];

    if (data.contents) {
      var sectionList = findSectionList(data.contents);
      if (sectionList && sectionList.contents) {
        for (var si = 0; si < sectionList.contents.length; si++) {
          var section = sectionList.contents[si];

          if (section.musicShelfRenderer) {
            var shelf = section.musicShelfRenderer;
            var shelfTitle = "";
            if (shelf.title && shelf.title.runs) {
              shelfTitle = shelf.title.runs
                .map(function (r) {
                  return r.text;
                })
                .join("")
                .toLowerCase();
            }

            if (
              shelfTitle.indexOf("song") !== -1 ||
              shelfTitle.indexOf("top") !== -1 ||
              shelfTitle.indexOf("popular") !== -1
            ) {
              L("info", "getArtist found songs section:", shelfTitle);
              if (shelf.contents) {
                for (
                  var ti = 0;
                  ti < shelf.contents.length && topTracks.length < 10;
                  ti++
                ) {
                  var trackNode = shelf.contents[ti];
                  var parsed = parseItemExtended(trackNode);
                  if (parsed && parsed.id) {
                    var sanitized = sanitizeTrackBeforeReturn(parsed);
                    if (sanitized) {
                      // Add artist name if missing
                      if (!sanitized.artists) {
                        sanitized.artists = artistName;
                      }
                      topTracks.push(sanitized);
                    }
                  }
                }
              }
              L("info", "getArtist found top tracks", topTracks.length);
            }
          }

          if (section.musicCarouselShelfRenderer) {
            var carousel = section.musicCarouselShelfRenderer;
            if (carousel.contents) {
              for (var ci = 0; ci < carousel.contents.length; ci++) {
                var node = carousel.contents[ci];
                var parsed = parseCollectionItem(node);
                if (
                  parsed &&
                  (parsed.item_type === "album" ||
                    parsed.item_type === "playlist")
                ) {
                  var sanitized = sanitizeCollectionBeforeReturn(parsed);
                  if (sanitized) {
                    albums.push({
                      id: sanitized.id,
                      name: sanitized.name,
                      artists: sanitized.artists || artistName,
                      cover_url: sanitized.cover_url,
                      release_date: sanitized.release_date || "",
                      total_tracks: 0,
                      album_type: sanitized.album_type || "album",
                      provider_id: "ytmusic-spotiflac",
                    });
                  }
                }
              }
            }
          }
        }
      }

      if (albums.length === 0) {
        var candidates = [];
        collectItemsFromNode(data.contents, candidates, 0);

        for (var i = 0; i < candidates.length; i++) {
          var node = candidates[i];
          var parsed = parseCollectionItem(node);
          if (
            parsed &&
            (parsed.item_type === "album" || parsed.item_type === "playlist")
          ) {
            var sanitized = sanitizeCollectionBeforeReturn(parsed);
            if (sanitized) {
              albums.push({
                id: sanitized.id,
                name: sanitized.name,
                artists: sanitized.artists || artistName,
                cover_url: sanitized.cover_url,
                release_date: sanitized.release_date || "",
                total_tracks: 0,
                album_type: sanitized.album_type || "album",
                provider_id: "ytmusic-spotiflac",
              });
            }
          }
        }
      }
    }

    L("info", "getArtist found albums", albums.length);
    L("info", "getArtist found top_tracks", topTracks.length);

    return {
      id: artistId,
      name: artistName,
      image_url: artistImage,
      header_image: headerImage,
      listeners: monthlyListeners,
      albums: albums,
      top_tracks: topTracks,
      provider_id: "ytmusic-spotiflac",
    };
  } catch (e) {
    L("error", "getArtist error", String(e));
    return null;
  }
}

function findSectionList(contents) {
  if (!contents) return null;

  if (contents.sectionListRenderer) {
    return contents.sectionListRenderer;
  }

  if (contents.singleColumnBrowseResultsRenderer) {
    var tabs = contents.singleColumnBrowseResultsRenderer.tabs;
    if (tabs && tabs[0] && tabs[0].tabRenderer && tabs[0].tabRenderer.content) {
      if (tabs[0].tabRenderer.content.sectionListRenderer) {
        return tabs[0].tabRenderer.content.sectionListRenderer;
      }
    }
  }

  if (contents.twoColumnBrowseResultsRenderer) {
    var secondaryContents =
      contents.twoColumnBrowseResultsRenderer.secondaryContents;
    if (secondaryContents && secondaryContents.sectionListRenderer) {
      return secondaryContents.sectionListRenderer;
    }
    var tabs = contents.twoColumnBrowseResultsRenderer.tabs;
    if (tabs && tabs[0] && tabs[0].tabRenderer && tabs[0].tabRenderer.content) {
      if (tabs[0].tabRenderer.content.sectionListRenderer) {
        return tabs[0].tabRenderer.content.sectionListRenderer;
      }
    }
  }

  return null;
}

var __upstream_initialize = function (settings) {
    settings = settings || {};
    var homeCountry = String(readSetting(settings, "homeCountry", "ID"))
      .trim()
      .toUpperCase();
    CONFIG.homeCountry = /^[A-Z]{2}$/.test(homeCountry) ? homeCountry : "ID";
    var poTokenMode = String(
      readSetting(settings, "poTokenMode", CONFIG.poTokenMode) || "",
    )
      .trim()
      .toLowerCase();
    if (
      poTokenMode === "off" ||
      poTokenMode === "auto" ||
      poTokenMode === "external" ||
      poTokenMode === "manual"
    ) {
      CONFIG.poTokenMode = poTokenMode;
    }
    CONFIG.poTokenProviderURL = normalizePoTokenProviderURL(
      readSetting(settings, "poTokenProviderUrl", CONFIG.poTokenProviderURL),
    );
    CONFIG.manualGvsPoToken = String(
      readSetting(settings, "manualGvsPoToken", CONFIG.manualGvsPoToken) || "",
    ).trim();
    CONFIG.logLevel = normalizeLogLevel(
      readSetting(settings, "logLevel", CONFIG.logLevel),
    );
    L("info", "YouTube Music extension init", {
      poTokenMode: CONFIG.poTokenMode,
      hasProvider: !!CONFIG.poTokenProviderURL,
      hasManualToken: !!CONFIG.manualGvsPoToken,
    });
    return true;
  };
var __upstream_cleanup = function () {
    _cache.clear();
    _poTokenCache.clear();
    _inflight.clear();
    L("info", "YouTube Music extension cleanup");
    return true;
  };
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
