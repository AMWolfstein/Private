// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/amazon/index.js
// Inactive source import: no app integration or update trust policy is installed.

var CONFIG = {
  maxAttempts: 5,
  baseBackoffMs: 250,
  maxBackoffMs: 4000,
  cacheTtlMs: 180000,
  cacheMaxEntries: 500,
  resourceCacheMaxEntries: 500,
  maxResults: 15,
  skillBaseURL: "https://na.mesk.skill.music.a2z.com/api",
  musicBaseURL: "https://music.amazon.com",
  deviceType: "A16ZV8BU3SN1N3",
  appVersion: "1.0.9678.0",
  deviceFamily: "WebPlayer",
  deviceModel: "WEBPLAYER",
  musicTerritory: "US"
};

var EXTENSION_VERSION = "2.3.19";

var USER_AGENTS = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Safari/537.36"
];

function getRandomUA() {
  if (utils && typeof utils.randomUserAgent === "function") {
    var ua = String(utils.randomUserAgent() || "").trim();
    if (ua) return ua;
  }
  return USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)];
}

function L(level) {
  try {
    if (typeof log !== "undefined" && typeof log[level] === "function") {
      var args = Array.prototype.slice.call(arguments, 1);
      log[level].apply(log, args);
    }
  } catch (e) {}
}

function sleep(ms) {
  if (utils && typeof utils.sleep === "function") {
    return utils.sleep(Math.max(0, Math.round(Number(ms || 0))));
  }
  // Older runtimes do not expose a cancellation-aware sleep. Skipping the
  // delay is safer than blocking the complete JavaScript runtime in a spin.
  return true;
}

var _cache = new Map();

function cacheGet(k) {
  var entry = _cache.get(k);
  if (!entry) return null;
  if (Date.now() - entry.createdAt > CONFIG.cacheTtlMs) {
    _cache.delete(k);
    return null;
  }
  _cache.delete(k);
  _cache.set(k, entry);
  return entry.value;
}

function cacheSet(k, v) {
  if (_cache.has(k)) _cache.delete(k);
  _cache.set(k, { value: v, createdAt: Date.now() });
  while (_cache.size > CONFIG.cacheMaxEntries) {
    _cache.delete(_cache.keys().next().value);
  }
  return v;
}

function isAmazonUnavailable(error) {
  if (error && error.retryable === true) return false;
  var code = String(error && error.code || "").toUpperCase();
  if (code) return /^(TRACK_NOT_FOUND|TRACK_UNAVAILABLE|TRACK_NOT_AVAILABLE|QUALITY_UNAVAILABLE|QUALITY_NOT_AVAILABLE|CODEC_UNAVAILABLE)$/.test(code);
  var message = String(error && error.message || error || "").replace(/^Error: /, "").trim();
  return /^(?:requested )?(?:track|quality|codec)(?: is)? (?:not available|unavailable|not found)(?:[.!]|$)/i.test(message);
}

function amazonCancelledError() {
  var error = new Error("download cancelled");
  error.code = "CANCELLED";
  return error;
}

function requireAmazonResolutionBudget(delayMs, retryAfterMs) {
  if (utils && typeof utils.getResolutionRemainingMs === "function" &&
      Number(utils.getResolutionRemainingMs()) <= Number(delayMs || 0)) {
    var error = new Error("stream resolution timeout");
    error.code = "RESOLUTION_TIMEOUT";
    error.retryAfterMs = Number(retryAfterMs || 0);
    throw error;
  }
}

function fetchWithRetry(requestFn, preserveErrors) {
  var lastError = null;
  var delay = CONFIG.baseBackoffMs;
  var retryAfterMs = 0;
  for (var attempt = 0; attempt < CONFIG.maxAttempts; attempt++) {
    if (utils && typeof utils.isDownloadCancelled === "function" && utils.isDownloadCancelled()) {
      if (preserveErrors) throw amazonCancelledError();
      return null;
    }
    if (preserveErrors) requireAmazonResolutionBudget(0, retryAfterMs);
    if (attempt > 0) {
      var jitteredDelay = Math.max(delay, retryAfterMs) + Math.floor(Math.random() * Math.max(25, Math.floor(delay / 4)));
      L("info", "[Amazon] Retry " + (attempt + 1) + "/" + CONFIG.maxAttempts + " after " + jitteredDelay + "ms");
      if (preserveErrors) requireAmazonResolutionBudget(jitteredDelay, retryAfterMs);
      if (!sleep(jitteredDelay)) {
        if (preserveErrors) throw amazonCancelledError();
        return null;
      }
      delay = Math.min(delay * 2, CONFIG.maxBackoffMs);
    }
    try {
      var result = requestFn();
      if (result) return result;
      lastError = new Error("request returned no result");
      retryAfterMs = 0;
    } catch (e) {
      lastError = e;
      var lower = String(e && e.message || e).toLowerCase();
      var mode = String(e && e.retryMode || "");
      var hasContract = !!(e && (e.code || mode || typeof e.retryable === "boolean"));
      // The host owns same_operation retries. Never mint a new operation for
      // that mode, an unknown mode, or an explicitly terminal contract.
      var retryable = hasContract
        ? e.retryable === true && (mode === "new_ticket" || mode === "poll_existing")
        : /timeout|reset|refused|eof|(?:status|http) 5\d\d|429/.test(lower);
      if ((e && e.needsVerification) || isAmazonUnavailable(e) || !retryable) {
        L("warn", "[Amazon] Non-retryable error:", lower);
        if (preserveErrors) throw e;
        return null;
      }
      retryAfterMs = Math.max(0, Number(e && e.retryAfterMs || 0));
    }
    L("warn", "[Amazon] Attempt " + (attempt + 1) + " failed:", String(lastError));
  }
  L("error", "[Amazon] All attempts failed:", String(lastError));
  if (preserveErrors && lastError) throw lastError;
  return null;
}

var ASIN_REGEX = /^B[0-9A-Z]{9}$/;

var AMAZON_MUSIC_HOST_REGEX = /^music\.amazon\.(?:com(?:\.(?:br|mx|au))?|co(?:\.(?:uk|jp))?|de|fr|it|es|in|ca)$/;

function normalizeASIN(candidate) {
  if (!candidate || typeof candidate !== "string") return null;
  var s = candidate.trim();
  if (!s) return null;
  try { s = decodeURIComponent(s); } catch (e) {}
  s = s.toUpperCase();
  var cut = s.search(/[?#&\/]/);
  if (cut >= 0) s = s.substring(0, cut);
  if (ASIN_REGEX.test(s)) return s;
  return null;
}

var _session = {
  deviceId: null,
  sessionId: null,
  csrfToken: null,
  csrfTs: null,
  csrfRnd: null,
  appVersion: null,
  displayLanguage: null,
  musicTerritory: null,
  baseURL: null,
  initialized: false
};

var _currentContext = {
  musicBaseURL: CONFIG.musicBaseURL,
  host: "music.amazon.com",
  timeZone: "UTC"
};

var _resourceContexts = new Map();

var _resourceHints = new Map();

var _homeCountry = "US";

function boundedMapGet(map, key) {
  if (!map.has(key)) return null;
  var entry = map.get(key);
  if (!entry || Date.now() >= entry.expiresAt) {
    map.delete(key);
    return null;
  }
  map.delete(key);
  map.set(key, entry);
  return entry.value;
}

function boundedMapSet(map, key, value) {
  if (map.has(key)) map.delete(key);
  map.set(key, {
    value: value,
    expiresAt: Date.now() + CONFIG.cacheTtlMs
  });
  while (map.size > CONFIG.resourceCacheMaxEntries) {
    map.delete(map.keys().next().value);
  }
  return value;
}

function guessTimeZone() {
  try {
    if (typeof Intl !== "undefined" && Intl.DateTimeFormat) {
      return Intl.DateTimeFormat().resolvedOptions().timeZone || "UTC";
    }
  } catch (e) {}
  return "UTC";
}

function defaultCurrencyForHost(host) {
  host = String(host || "").toLowerCase();
  if (host.indexOf(".co.jp") >= 0) return "JPY";
  if (host.indexOf(".co.uk") >= 0) return "GBP";
  if (host.indexOf(".de") >= 0 || host.indexOf(".fr") >= 0 || host.indexOf(".it") >= 0 || host.indexOf(".es") >= 0) return "EUR";
  if (host.indexOf(".in") >= 0) return "INR";
  if (host.indexOf(".com.br") >= 0) return "BRL";
  if (host.indexOf(".com.mx") >= 0) return "MXN";
  if (host.indexOf(".com.au") >= 0) return "AUD";
  return "USD";
}

function createAmazonContext(rawURL) {
  var base = CONFIG.musicBaseURL;
  var host = "music.amazon.com";

  if (rawURL) {
    try {
      var parsed = new URL(rawURL);
      host = parsed.hostname.toLowerCase() || host;
      base = parsed.protocol + "//" + host;
    } catch (e) {
      try {
        var parsedBase = new URL(base);
        host = parsedBase.hostname.toLowerCase();
      } catch (e2) {}
    }
  } else {
    try {
      var defaultParsed = new URL(base);
      host = defaultParsed.hostname.toLowerCase();
    } catch (e3) {}
  }

  // Resolve shared regional links in the same catalog used for downloads.
  // Keep their resource IDs until Amazon returns the corresponding IDs.
  if (AMAZON_MUSIC_HOST_REGEX.test(host)) {
    host = "music.amazon.com";
    base = "https://" + host;
  }

  return {
    musicBaseURL: base,
    host: host,
    timeZone: guessTimeZone(),
    currency: defaultCurrencyForHost(host)
  };
}

function contextKey(type, id) {
  return String(type || "") + ":" + String(id || "");
}

function rememberResourceContext(type, id, context) {
  if (!type || !id || !context) return;
  boundedMapSet(_resourceContexts, contextKey(type, id), {
    musicBaseURL: context.musicBaseURL,
    host: context.host,
    timeZone: context.timeZone,
    currency: context.currency
  });
}

function rememberResourceHint(type, id, hint) {
  if (!type || !id || !hint) return;
  var key = contextKey(type, id);
  var rememberedHint = boundedMapGet(_resourceHints, key) || {};
  var keys = Object.keys(hint);
  for (var i = 0; i < keys.length; i++) {
    if (hint[keys[i]] !== undefined && hint[keys[i]] !== null && hint[keys[i]] !== "") {
      rememberedHint[keys[i]] = hint[keys[i]];
    }
  }
  boundedMapSet(_resourceHints, key, rememberedHint);
}

function getResourceContext(type, id, fallback) {
  var remembered = boundedMapGet(_resourceContexts, contextKey(type, id));
  if (remembered) return remembered;
  if (fallback) return fallback;
  return _currentContext || createAmazonContext(CONFIG.musicBaseURL);
}

function getResourceHint(type, id, key) {
  var hint = boundedMapGet(_resourceHints, contextKey(type, id));
  return hint ? hint[key] : "";
}

function slugToName(slug) {
  if (!slug) return "";
  var cleaned = String(slug).replace(/[-_]+/g, " ").replace(/\s+/g, " ").trim();
  if (!cleaned) return "";
  return cleaned.replace(/\b\w/g, function(ch) { return ch.toUpperCase(); });
}

function looksLikeURL(value) {
  if (!value || typeof value !== "string") return false;
  var s = value.trim();
  return /^https?:\/\//i.test(s) || s.indexOf("music.amazon.") >= 0;
}

function sanitizeDisplayText(value) {
  var text = textValue(value);
  if (!text) return "";
  if (looksLikeURL(text)) return "";
  return text.trim();
}

function initSession(context) {
  var ctx = context || _currentContext || createAmazonContext(CONFIG.musicBaseURL);
  if (_session.initialized && _session.baseURL === ctx.musicBaseURL) return;
  _currentContext = ctx;

  // POST issues CSRF credentials; GET returns configuration without a token.
  L("info", "[Amazon] Fetching config.json for session...");
  try {
    var configUrl = ctx.musicBaseURL + "/config.json?skipToken=false&clientApplication=skyfire";
    var res = fetch(configUrl, {
      method: "POST",
      headers: {
        "User-Agent": getRandomUA(),
        "Accept": "application/json"
      }
    });
    L("info", "[Amazon] initSession config.json status:", res ? res.status : "null");

    if (res && res.ok) {
      var config = res.json();
      if (config) {
        _session.deviceId = config.deviceId || "";
        _session.sessionId = config.sessionId || "";
        _session.appVersion = config.version || CONFIG.appVersion;
        _session.displayLanguage = config.displayLanguage || "en_US";
        _session.musicTerritory = config.musicTerritory || CONFIG.musicTerritory;
        _session.baseURL = ctx.musicBaseURL;

        if (config.csrf) {
          _session.csrfToken = config.csrf.token || "";
          _session.csrfTs = config.csrf.ts || String(Math.floor(Date.now() / 1000));
          _session.csrfRnd = config.csrf.rnd || String(Math.floor(Math.random() * 2000000000));
        }

        _session.initialized = true;
        L("info", "[Amazon] Session initialized, deviceId:", _session.deviceId);
        return;
      }
    }
  } catch (e) {
    L("warn", "[Amazon] config.json fetch failed:", String(e));
  }

  // Fallback: generate random session (may get 429)
  L("warn", "[Amazon] Using fallback random session");
  _session.deviceId = String(Math.floor(Math.random() * 99999999999999999));
  _session.sessionId = Math.floor(Math.random() * 999) + "-" +
    Math.floor(Math.random() * 9999999) + "-" +
    Math.floor(Math.random() * 9999999);
  _session.csrfToken = "";
  _session.csrfTs = String(Math.floor(Date.now() / 1000));
  _session.csrfRnd = String(Math.floor(Math.random() * 2000000000));
  _session.appVersion = CONFIG.appVersion;
  _session.displayLanguage = "en_US";
  _session.musicTerritory = CONFIG.musicTerritory;
  _session.baseURL = ctx.musicBaseURL;
  _session.initialized = true;
}

function refreshSession(withNewCookies) {
  // Amazon ties a session to its cookies, so a renewal that keeps them gets
  // the same session back.
  if (withNewCookies && typeof http !== "undefined" && http &&
      typeof http.clearCookies === "function") {
    try {
      http.clearCookies();
    } catch (e) {
      L("warn", "[Amazon] Clearing cookies failed:", String(e));
    }
  }
  // Force re-fetch config.json if getting 429s
  _session.initialized = false;
  initSession();
}

function buildHeaders(context, pageUrl) {
  var ctx = context || _currentContext || createAmazonContext(pageUrl || CONFIG.musicBaseURL);
  var csrf = JSON.stringify({
    "interface": "CSRFInterface.v1_0.CSRFHeaderElement",
    "token": _session.csrfToken || "",
    "timestamp": _session.csrfTs || String(Math.floor(Date.now() / 1000)),
    "rndNonce": _session.csrfRnd || String(Math.floor(Math.random() * 2000000000))
  });
  var auth = JSON.stringify({
    "interface": "ClientAuthenticationInterface.v1_0.ClientTokenElement",
    "accessToken": ""
  });
  return JSON.stringify({
    "x-amzn-authentication": auth,
    "x-amzn-device-model": CONFIG.deviceModel,
    "x-amzn-device-width": "1920",
    "x-amzn-device-family": CONFIG.deviceFamily,
    "x-amzn-device-id": _session.deviceId,
    "x-amzn-user-agent": getRandomUA(),
    "x-amzn-session-id": _session.sessionId,
    "x-amzn-device-height": "1080",
    "x-amzn-request-id": Math.random().toString(36).substring(2) + "-" + Date.now(),
    "x-amzn-device-language": _session.displayLanguage || "en_US",
    "x-amzn-currency-of-preference": ctx.currency || defaultCurrencyForHost(ctx.host),
    "x-amzn-os-version": "1.0",
    "x-amzn-application-version": _session.appVersion || CONFIG.appVersion,
    "x-amzn-device-time-zone": ctx.timeZone || "UTC",
    "x-amzn-timestamp": String(Date.now()),
    "x-amzn-csrf": csrf,
    "x-amzn-music-domain": ctx.host || "music.amazon.com",
    "x-amzn-referer": "",
    "x-amzn-affiliate-tags": "",
    "x-amzn-ref-marker": "",
    "x-amzn-page-url": pageUrl || ctx.musicBaseURL || CONFIG.musicBaseURL,
    "x-amzn-weblab-id-overrides": "",
    "x-amzn-video-player-token": "",
    "x-amzn-feature-flags": "",
    "x-amzn-has-profile-id": "",
    "x-amzn-age-band": ""
  });
}

function _doShowHome(apiBaseURL, deeplink, pageUrl, body, context) {
  var ctx = context || _currentContext || createAmazonContext(pageUrl || CONFIG.musicBaseURL);
  var res;
  try {
    L("info", "[Amazon] showHome fetching:", apiBaseURL + "/showHome");
    res = fetch(apiBaseURL + "/showHome", {
      method: "POST",
      headers: {
        "Content-Type": "text/plain;charset=UTF-8",
        "User-Agent": getRandomUA(),
        "Origin": ctx.musicBaseURL,
        "Referer": pageUrl
      },
      body: body
    });
  } catch (e) {
    L("error", "[Amazon] showHome fetch exception:", String(e));
    return null;
  }
  L("info", "[Amazon] showHome response:", res ? res.status : "null");
  if (!res || !res.ok) return null;
  try {
    // Get raw text first (free - Go already has it), then parse JSON
    var rawText = res.text();
    var parsed = JSON.parse(rawText);
    L("info", "[Amazon] showHome OK, methods:", parsed && parsed.methods ? parsed.methods.length : 0);
    return { data: parsed, rawText: rawText };
  } catch (e) {
    L("error", "[Amazon] showHome JSON parse failed:", String(e));
    return null;
  }
}

function callShowHome(deeplink, context, _retried) {
  var ctx = context || _currentContext || createAmazonContext(CONFIG.musicBaseURL + deeplink);
  _currentContext = ctx;
  initSession(ctx);
  var pageUrl = ctx.musicBaseURL + deeplink;
  L("info", "[Amazon] callShowHome:", deeplink);

  var body = JSON.stringify({
    deeplink: JSON.stringify({
      "interface": "DeeplinkInterface.v1_0.DeeplinkClientInformation",
      "deeplink": deeplink
    }),
    headers: buildHeaders(ctx, pageUrl)
  });

  var result = _doShowHome(CONFIG.skillBaseURL, deeplink, pageUrl, body, ctx);
  if (result) return result;

  // If failed, refresh session and retry once
  if (!_retried) {
    L("info", "[Amazon] showHome failed, refreshing session and retrying...");
    refreshSession();
    sleep(CONFIG.baseBackoffMs);
    return callShowHome(deeplink, ctx, true);
  }

  L("error", "[Amazon] callShowHome failed for:", deeplink);
  return null;
}

function callShowCatalogArtist(artistId, slug, context, _retried) {
  var ctx = context || _currentContext || createAmazonContext(CONFIG.musicBaseURL);
  _currentContext = ctx;
  initSession(ctx);
  // pageUrl uses only /artists/{id} (no slug) for showCatalogArtist
  var pageUrl = ctx.musicBaseURL + "/artists/" + artistId;
  L("info", "[Amazon] callShowCatalogArtist:", artistId);

  var body = JSON.stringify({
    id: artistId,
    userHash: JSON.stringify({ "level": "LIBRARY_MEMBER" }),
    headers: buildHeaders(ctx, pageUrl)
  });

  var apiUrl = CONFIG.skillBaseURL.replace(/\/api$/, "") + "/api/explore/v1/showCatalogArtist";
  var res;
  try {
    L("info", "[Amazon] showCatalogArtist fetching:", apiUrl);
    res = fetch(apiUrl, {
      method: "POST",
      headers: {
        "Content-Type": "text/plain;charset=UTF-8",
        "User-Agent": getRandomUA(),
        "Origin": ctx.musicBaseURL,
        "Referer": ctx.musicBaseURL + "/"
      },
      body: body
    });
  } catch (e) {
    L("error", "[Amazon] showCatalogArtist fetch exception:", String(e));
    return null;
  }
  L("info", "[Amazon] showCatalogArtist response:", res ? res.status : "null");
  if (!res || !res.ok) {
    if (!_retried) {
      L("info", "[Amazon] showCatalogArtist failed, refreshing session and retrying...");
      refreshSession();
      sleep(CONFIG.baseBackoffMs);
      return callShowCatalogArtist(artistId, slug, ctx, true);
    }
    return null;
  }
  try {
    var rawText = res.text();
    var parsed = JSON.parse(rawText);
    L("info", "[Amazon] showCatalogArtist OK, methods:", parsed && parsed.methods ? parsed.methods.length : 0);
    return { data: parsed, rawText: rawText };
  } catch (e) {
    L("error", "[Amazon] showCatalogArtist JSON parse failed:", String(e));
    return null;
  }
}

function _doShowSearch(apiBaseURL, keyword, pageUrl, body, context) {
  var ctx = context || _currentContext || createAmazonContext(pageUrl || CONFIG.musicBaseURL);
  var res;
  try {
    L("info", "[Amazon] showSearch fetching:", apiBaseURL + "/showSearch");
    res = fetch(apiBaseURL + "/showSearch", {
      method: "POST",
      headers: {
        "Content-Type": "text/plain;charset=UTF-8",
        "User-Agent": getRandomUA(),
        "Origin": ctx.musicBaseURL,
        "Referer": pageUrl
      },
      body: body
    });
  } catch (e) {
    L("error", "[Amazon] showSearch fetch exception:", String(e));
    return null;
  }
  L("info", "[Amazon] showSearch response:", res ? res.status : "null");
  if (!res || !res.ok) return null;
  var data;
  try {
    data = res.json();
  } catch (e) {
    L("error", "[Amazon] showSearch JSON parse failed:", String(e));
    return null;
  }
  if (isServiceErrorDialog(data)) {
    L("warn", "[Amazon] showSearch returned a service error instead of results");
    return SEARCH_SERVICE_ERROR;
  }
  return data;
}

var SEARCH_SERVICE_ERROR = { serviceError: true };

function isServiceErrorDialog(data) {
  var methods = data && data.methods;
  if (!methods || !methods.length) return false;
  var dialog = false;
  for (var i = 0; i < methods.length; i++) {
    var template = methods[i] && methods[i].template;
    var name = String((template && template.interface) || "");
    if (/SearchTemplate$/.test(name)) return false;
    if (/DialogTemplate$/.test(name)) dialog = true;
  }
  return dialog;
}

function callShowSearch(keyword, context, _retried) {
  var ctx = context || _currentContext || createAmazonContext(CONFIG.musicBaseURL);
  _currentContext = ctx;
  initSession(ctx);
  var pageUrl = ctx.musicBaseURL + "/search/" + encodeURIComponent(keyword);
  L("info", "[Amazon] callShowSearch:", keyword);

  var body = JSON.stringify({
    filter: JSON.stringify({ "IsLibrary": ["false"] }),
    keyword: JSON.stringify({
      "interface": "Web.TemplatesInterface.v1_0.Touch.SearchTemplateInterface.SearchKeywordClientInformation",
      "keyword": keyword
    }),
    suggestedKeyword: keyword,
    userHash: JSON.stringify({ "level": "LIBRARY_MEMBER" }),
    headers: buildHeaders(ctx, pageUrl)
  });

  var result = _doShowSearch(CONFIG.skillBaseURL, keyword, pageUrl, body, ctx);
  if (result === SEARCH_SERVICE_ERROR) {
    if (!_retried) {
      L("info", "[Amazon] showSearch service error, starting a new session and retrying...");
      refreshSession(true);
      sleep(CONFIG.baseBackoffMs);
      return callShowSearch(keyword, ctx, true);
    }
    // Refused again with a new session: more attempts only add delay. Some
    // regions get this for every search while album and artist links work.
    L("warn", "[Amazon] Search refused for:", keyword);
    var refused = new Error("amazon_search_refused");
    refused.code = "search_refused";
    refused.retryable = false;
    throw refused;
  }
  if (result) return result;

  if (!_retried) {
    L("info", "[Amazon] showSearch failed, refreshing session and retrying...");
    refreshSession();
    sleep(CONFIG.baseBackoffMs);
    return callShowSearch(keyword, ctx, true);
  }

  L("error", "[Amazon] callShowSearch failed for:", keyword);
  return null;
}

function deepStringify(obj) {
  try { return JSON.stringify(obj); } catch (e) { return ""; }
}

function findAllByInterface(obj, targetInterface, results, depth) {
  if (!obj || depth > 20) return;
  if (!results) results = [];
  if (!depth) depth = 0;

  if (typeof obj !== "object") return results;

  if (obj["interface"] === targetInterface) {
    results.push(obj);
  }

  var keys = Object.keys(obj);
  for (var i = 0; i < keys.length; i++) {
    var val = obj[keys[i]];
    if (typeof val === "object" && val !== null) {
      findAllByInterface(val, targetInterface, results, depth + 1);
    }
  }
  return results;
}

function findFirst(obj, key, depth) {
  if (!obj || depth > 20) return undefined;
  if (!depth) depth = 0;
  if (typeof obj !== "object") return undefined;

  if (obj[key] !== undefined) return obj[key];

  var keys = Object.keys(obj);
  for (var i = 0; i < keys.length; i++) {
    var val = obj[keys[i]];
    if (typeof val === "object" && val !== null) {
      var found = findFirst(val, key, depth + 1);
      if (found !== undefined) return found;
    }
  }
  return undefined;
}

function amazonItemIsExplicit(item) {
  // Amazon marks explicit tracks with a tag array containing "E" and an
  // "explicitAriaLabel" ("Explicit Content") on the row element. Clean tracks
  // carry an empty tags array, so presence of "E"/explicitAriaLabel is reliable.
  if (!item || typeof item !== "object") return false;
  var title = textValue(item.primaryText || item.title || item.name);
  if (/\[explicit\]/i.test(title)) return true;
  var tags = findFirst(item, "tags", 0);
  if (tags && Object.prototype.toString.call(tags) === "[object Array]") {
    for (var i = 0; i < tags.length; i++) {
      if (String(tags[i]).toUpperCase() === "E") return true;
    }
  }
  var aria = findFirst(item, "explicitAriaLabel", 0);
  if (aria && String(aria).toLowerCase().indexOf("explicit") >= 0) return true;
  return false;
}

function textValue(value) {
  if (value === null || value === undefined) return "";
  if (typeof value === "string") return value;
  if (typeof value === "number") return String(value);
  if (typeof value === "object") {
    if (typeof value.text === "string" && value.text) return value.text;
    if (value.defaultValue) {
      var nestedDefault = textValue(value.defaultValue);
      if (nestedDefault) return nestedDefault;
    }
    if (value.observer && value.observer.defaultValue) {
      var nestedObserver = textValue(value.observer.defaultValue);
      if (nestedObserver) return nestedObserver;
    }
  }
  return "";
}

function extractAmazonDeeplinkInfo(deeplink) {
  if (!deeplink) return null;
  try {
    var parsed = new URL(deeplink, (_currentContext && _currentContext.musicBaseURL) || CONFIG.musicBaseURL);
    var pathname = parsed.pathname.replace(/^\/|\/$/g, "");
    var segments = pathname ? pathname.split("/") : [];
    if (!segments.length) return null;
    var kind = segments[0].toLowerCase();
    var rawID = segments.length > 1 ? segments[1] : "";
    if (kind === "albums" && parsed.searchParams.get("trackAsin")) {
      return {
        type: "track",
        id: normalizeASIN(parsed.searchParams.get("trackAsin")) || parsed.searchParams.get("trackAsin"),
        albumId: normalizeASIN(rawID) || rawID
      };
    }
    return {
      type: kind,
      id: normalizeASIN(rawID) || rawID
    };
  } catch (e) {
    return null;
  }
}

function extractDeeplinkId(deeplink) {
  var info = extractAmazonDeeplinkInfo(deeplink);
  return info ? info.id : null;
}

function fixImageUrl(url, size) {
  if (!url) return "";
  // Amazon's unsized CDN URL serves the source asset. Adding _SL1000_ caps
  // masters that Amazon exposes at 1400-1800px (and sometimes larger).
  var cleaned = url.replace(/\._[^.]+_\./, ".");
  return cleaned;
}

function ensureHighResCoverUrl(url) {
  return fixImageUrl(url);
}

function normalizeAmazonDate(value) {
  var text = String(value || "").trim();
  if (!text) return "";
  var match = text.match(/(\d{4})-(\d{2})-(\d{2})/);
  return match ? match[1] + "-" + match[2] + "-" + match[3] : text;
}

function amazonAlbumURL(albumId) {
  var id = normalizeASIN(String(albumId || "")) || String(albumId || "").trim();
  return id ? ((_currentContext && _currentContext.musicBaseURL) || CONFIG.musicBaseURL) + "/albums/" + id : "";
}

function amazonTrackURL(trackId) {
  var id = normalizeASIN(String(trackId || "")) || String(trackId || "").trim();
  return id ? ((_currentContext && _currentContext.musicBaseURL) || CONFIG.musicBaseURL) + "/tracks/" + id : "";
}

function amazonArtistURL(artistId) {
  var id = normalizeASIN(String(artistId || "")) || String(artistId || "").trim();
  return id ? ((_currentContext && _currentContext.musicBaseURL) || CONFIG.musicBaseURL) + "/artists/" + id : "";
}

function parseDurationMMSS(mmss) {
  // Parse "03:24" -> 204 seconds
  mmss = textValue(mmss);
  if (!mmss) return 0;
  var parts = mmss.split(":");
  if (parts.length === 2) {
    return parseInt(parts[0], 10) * 60 + parseInt(parts[1], 10);
  }
  if (parts.length === 3) {
    return parseInt(parts[0], 10) * 3600 + parseInt(parts[1], 10) * 60 + parseInt(parts[2], 10);
  }
  return 0;
}

function _extractSchemaAtPosition(responseStr, idx) {
  var innerStart = responseStr.lastIndexOf('"innerHTML"', idx);
  if (innerStart === -1) return null;

  var colonIdx = responseStr.indexOf(":", innerStart);
  if (colonIdx === -1) return null;

  var quoteStart = responseStr.indexOf('"', colonIdx + 1);
  if (quoteStart === -1) return null;

  var content = "";
  var pos = quoteStart + 1;
  while (pos < responseStr.length) {
    if (responseStr[pos] === '"' && responseStr[pos - 1] !== '\\') break;
    content += responseStr[pos];
    pos++;
  }

  try {
    content = content.replace(/\\\\/g, "\\");
    content = content.replace(/\\"/g, '"');
    return JSON.parse(content);
  } catch (e) {
    return null;
  }
}

function extractSchemaOrg(responseStr, schemaType) {
  var searchStr = '"@type\\":\\"' + schemaType + '\\"';
  var idx = responseStr.indexOf(searchStr);
  if (idx === -1) return null;

  // For MusicAlbum, prefer the album-level schema (has numTracks/track array)
  // over per-track schemas embedded in MusicRecording entries.
  if (schemaType === "MusicAlbum") {
    var firstResult = null;
    var currentIdx = idx;
    while (currentIdx !== -1) {
      var extracted = _extractSchemaAtPosition(responseStr, currentIdx);
      if (extracted) {
        if (extracted.numTracks || extracted.track) {
          return extracted; // Found the album-level schema
        }
        if (!firstResult) firstResult = extracted;
      }
      currentIdx = responseStr.indexOf(searchStr, currentIdx + 1);
    }
    return firstResult; // Fallback to first found
  }

  return _extractSchemaAtPosition(responseStr, idx);
}

function parseDescriptiveRows(data) {
  var rows = findAllByInterface(data,
    "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.DescriptiveRowItemElement", [], 0);
  var tracks = [];

  for (var i = 0; i < rows.length; i++) {
    var row = rows[i];
    var name = textValue(row.primaryText);
    var deeplink = "";
    var duration = 0;
    var trackId = "";
    var albumId = "";

    if (row.primaryTextLink && row.primaryTextLink.deeplink) {
      deeplink = row.primaryTextLink.deeplink;
      var deeplinkInfo = extractAmazonDeeplinkInfo(deeplink);
      trackId = deeplinkInfo ? deeplinkInfo.id || "" : "";
      albumId = deeplinkInfo ? deeplinkInfo.albumId || "" : "";
    }
    if (row.primaryLink && row.primaryLink.deeplink) {
      var primaryLinkInfo = extractAmazonDeeplinkInfo(row.primaryLink.deeplink);
      if (!trackId && primaryLinkInfo) trackId = primaryLinkInfo.id || "";
      if (!albumId && primaryLinkInfo) albumId = primaryLinkInfo.albumId || "";
    }

    if (row.secondaryText3) {
      duration = parseDurationMMSS(row.secondaryText3);
    }

    // Artist: secondaryText1 > secondaryText2 (VA albums) > secondaryText
    var artist = "";
    if (row.secondaryText1) {
      artist = textValue(row.secondaryText1);
    }
    if (!artist && row.secondaryText2) {
      artist = textValue(row.secondaryText2);
    }
    if (!artist && row.secondaryText) {
      artist = textValue(row.secondaryText);
    }

    var image = "";
    if (row.image) {
      image = ensureHighResCoverUrl(row.image);
    }

    if (name && trackId) {
      tracks.push({
        id: trackId,
        title: name,
        artist: artist,
        duration: duration,
        duration_ms: duration * 1000,
        cover_art: image,
        deeplink: deeplink,
        track_number: i + 1,
        album_id: albumId,
        external_url: amazonTrackURL(trackId),
        explicit: amazonItemIsExplicit(row),
        audio_modes: amazonTrackAudioModes(row)
      });
    }
  }
  return tracks;
}

function amazonTrackAudioModes(track) {
  if (!track || typeof track !== "object") return "";
  var scopes = [track, track.metadata, track.attributes, track.audio, track.trackMetadata];
  for (var s = 0; s < scopes.length; s++) {
    var value = scopes[s];
    if (!value || typeof value !== "object") continue;
    var fields = [
      value.audioQualities, value.audio_qualities, value.audioModes,
      value.audio_modes, value.audioMode, value.audio_mode,
      value.audioTraits, value.audio_traits
    ];
    for (var j = 0; j < fields.length; j++) {
      var candidates = Array.isArray(fields[j]) ? fields[j] : [fields[j]];
      for (var k = 0; k < candidates.length; k++) {
        if (typeof candidates[k] !== "string") continue;
        var values = candidates[k].split(/[,;|]/);
        for (var m = 0; m < values.length; m++) {
          var normalized = values[m].trim().toUpperCase().replace(/[ -]/g, "_");
          if (normalized === "ATMOS" || normalized === "DOLBY_ATMOS") {
            return "DOLBY_ATMOS";
          }
        }
      }
    }
  }
  return "";
}

function formatAmazonTrackMetadata(track, album, fallbackTrackNumber) {
  track = track || {};
  album = album || {};
  var albumId = track.album_id || album.id || "";
  var artistId = track.artist_id || album.artist_id || "";
  var albumURL = track.album_url || album.album_url || amazonAlbumURL(albumId);
  var trackURL = track.external_url || amazonTrackURL(track.id);
  var totalTracks = Number(track.total_tracks || album.track_count || album.total_tracks || 0);
  var totalDiscs = Number(track.total_discs || album.total_discs || (albumId ? 1 : 0));
  return {
    id: track.id || "",
    name: track.name || track.title || "",
    artists: track.artists || track.artist || album.artist || "",
    album_name: track.album_name || track.album || album.title || "",
    album_artist: track.album_artist || album.artist || "",
    artist_id: artistId,
    artist_url: track.artist_url || album.artist_url || amazonArtistURL(artistId),
    album_id: albumId,
    album_url: albumURL,
    duration_ms: Number(track.duration_ms || (track.duration ? track.duration * 1000 : 0)),
    cover_url: ensureHighResCoverUrl(track.cover_url || track.cover_art || album.cover_art || ""),
    release_date: normalizeAmazonDate(track.release_date || album.release_date || album.year || ""),
    track_number: Number(track.track_number || fallbackTrackNumber || 0),
    total_tracks: totalTracks,
    disc_number: Number(track.disc_number || (albumId ? 1 : 0)),
    total_discs: totalDiscs,
    isrc: String(track.isrc || ""),
    genre: String(track.genre || album.genre || ""),
    label: String(track.label || album.label || ""),
    copyright: String(track.copyright || album.copyright || ""),
    composer: String(track.composer || ""),
    comment: albumURL,
    explicit: track.explicit === true,
    external_urls: trackURL,
    external_links: {
      amazon_track: trackURL,
      amazon_album: albumURL
    },
    spotify_id: String(track.spotify_id || ""),
    deezer_id: String(track.deezer_id || ""),
    provider_id: "amazon",
    item_type: "track",
    album_type: String(track.album_type || album.type || "album"),
    audio_quality: String(track.audio_quality || ""),
    audio_modes: amazonTrackAudioModes(track)
  };
}

function parseArtistCollectionItem(item, fallbackArtistName) {
  if (!item) return null;

  var deeplink = "";
  if (item.primaryLink && item.primaryLink.deeplink) {
    deeplink = item.primaryLink.deeplink;
  } else if (item.primaryTextLink && item.primaryTextLink.deeplink) {
    deeplink = item.primaryTextLink.deeplink;
  }
  if (!deeplink || deeplink.indexOf("/albums/") < 0) return null;

  var albumInfo = extractAmazonDeeplinkInfo(deeplink);
  if (!albumInfo || albumInfo.type !== "albums" || !albumInfo.id) return null;

  var albumName = textValue(item.primaryText);
  if (!albumName) return null;

  // Strip ranking prefix like "1. " or "12. " from Top Albums names
  albumName = albumName.replace(/^\d+\.\s+/, "");

  // secondaryText is like "Single • 2026" or "Album • 2025"
  var secondary = textValue(item.secondaryText) || "";
  var albumType = "album";
  var releaseDate = "";
  if (secondary) {
    var lower = secondary.toLowerCase();
    if (lower.indexOf("single") >= 0) albumType = "single";
    else if (lower.indexOf("ep") >= 0) albumType = "ep";
    else if (lower.indexOf("compilation") >= 0) albumType = "compilation";
    var yearMatch = secondary.match(/(\d{4})/);
    if (yearMatch) releaseDate = yearMatch[1];
  }

  return {
    id: albumInfo.id,
    name: albumName,
    cover_url: item.image ? ensureHighResCoverUrl(item.image) : "",
    artist: fallbackArtistName || "",
    release_date: releaseDate,
    type: albumType,
    album_type: albumType
  };
}

function pushUniqueArtistCollection(target, item) {
  if (!item || !item.id) return;
  for (var i = 0; i < target.length; i++) {
    if (target[i].id === item.id) return;
  }
  target.push(item);
}

function parseArtistFromResponse(data, responseStr, artistId) {
  var result = {
    id: artistId,
    name: "",
    image: "",
    albums: [],
    releases: [],
    top_tracks: [],
    type: "artist"
  };

  if (responseStr) {
    var schema = extractSchemaOrg(responseStr, "MusicGroup");
    if (schema) {
      result.name = schema.name || "";
      if (schema.image) result.image = ensureHighResCoverUrl(schema.image);
    }
  }

  // Direct extraction from showCatalogArtist DetailTemplate format
  // (template.headerText is the artist name, backgroundImage is the artist image)
  // This is more reliable than schema.org for API responses, so it overrides.
  if (data && data.methods) {
    for (var mi = 0; mi < data.methods.length; mi++) {
      var tmpl = data.methods[mi] && data.methods[mi].template;
      if (tmpl) {
        if (tmpl.headerText) {
          var directName = textValue(tmpl.headerText);
          if (directName) { result.name = directName; break; }
        }
      }
    }
  }
  if (data && data.methods) {
    for (var mi2 = 0; mi2 < data.methods.length; mi2++) {
      var tmpl2 = data.methods[mi2] && data.methods[mi2].template;
      if (tmpl2 && !result.image && tmpl2.backgroundImage && typeof tmpl2.backgroundImage === "string" && tmpl2.backgroundImage.indexOf("images/I/") >= 0) {
        result.image = ensureHighResCoverUrl(tmpl2.backgroundImage);
        break;
      }
    }
  }

  if (data && data.methods) {
    for (var i = 0; i < data.methods.length; i++) {
      var method = data.methods[i];

      // Get artist name from headerText (fallback DFS search)
      var headerLabel = findFirst(method, "headerLabel", 0);
      if (headerLabel !== undefined) {
        // Try headerText
        if (!result.name) {
          var headerText = findFirst(method, "headerText", 0);
          result.name = sanitizeDisplayText(headerText);
        }
        // Try primaryText
        if (!result.name) {
          var primaryText = findFirst(method, "primaryText", 0);
          result.name = sanitizeDisplayText(primaryText);
        }
        // Try seoTitle
        if (!result.name) {
          var seoTitle = findFirst(method, "title", 0);
          if (seoTitle && typeof seoTitle === "string") {
            // "Listen to Artist on Amazon Music"
            var listenMatch = seoTitle.match(/^(?:Listen to|Play)\s+(.+?)\s+on\s+/);
            if (listenMatch) {
              result.name = listenMatch[1];
            } else if (seoTitle.indexOf("Amazon") === -1) {
              result.name = seoTitle;
            }
          }
        }
        var bgImage = findFirst(method, "backgroundImage", 0);
        if (bgImage && typeof bgImage === "string" && bgImage.indexOf("images/I/") >= 0) {
          if (!result.image) result.image = ensureHighResCoverUrl(bgImage);
        }
      }
    }
  }

  if (data) {
    var shovelers = findAllByInterface(data,
      "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.VisualShovelerWidgetElement", [], 0);
    var featuredShovelers = findAllByInterface(data,
      "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.FeaturedShovelerWidgetElement", [], 0);
    var descriptiveShowcases = findAllByInterface(data,
      "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.DescriptiveShowcaseWidgetElement", [], 0);
    for (var fs = 0; fs < featuredShovelers.length; fs++) shovelers.push(featuredShovelers[fs]);
    for (var ds = 0; ds < descriptiveShowcases.length; ds++) shovelers.push(descriptiveShowcases[ds]);

    for (var s = 0; s < shovelers.length; s++) {
      var shoveler = shovelers[s];
      if (!shoveler.items) continue;
      var headerStr = typeof shoveler.header === "string" ? shoveler.header : "";
      var isReleaseSection = headerStr === "Releases" || headerStr === "Latest Releases";
      var isAlbumSection = headerStr === "Albums" || headerStr === "Top Albums" || headerStr === "Popular Albums";
      if (!isReleaseSection && !isAlbumSection) {
        // Fallback: stringify the whole shoveler to find section identifiers
        var shovelerStr = deepStringify(shoveler);
        isReleaseSection = shovelerStr.indexOf('"Releases"') >= 0 || shovelerStr.indexOf('"Latest Releases"') >= 0;
        isAlbumSection = shovelerStr.indexOf('"Albums"') >= 0 || shovelerStr.indexOf('"Top Albums"') >= 0 || shovelerStr.indexOf('"Popular Albums"') >= 0;
      }
      if (!isReleaseSection && !isAlbumSection) continue;

      for (var i = 0; i < shoveler.items.length; i++) {
        var parsedCollection = parseArtistCollectionItem(shoveler.items[i], result.name);
        if (!parsedCollection) continue;
        if (isReleaseSection) {
          pushUniqueArtistCollection(result.releases, parsedCollection);
        } else {
          pushUniqueArtistCollection(result.albums, parsedCollection);
        }
      }
    }

    if (!result.albums.length) {
      var squares = findAllByInterface(data,
        "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.SquareVerticalItemElement", [], 0);
      for (var k = 0; k < squares.length; k++) {
        var parsedAlbum = parseArtistCollectionItem(squares[k], result.name);
        if (parsedAlbum) {
          pushUniqueArtistCollection(result.albums, parsedAlbum);
        }
      }
    }

    result.top_tracks = parseDescriptiveRows(data);

    // If no tracks from DescriptiveRowItems, try SquareHorizontalItems inside
    // DescriptiveShovelerWidgets (showCatalogArtist uses this for "Top Songs")
    if (!result.top_tracks.length) {
      var descriptiveShovelers = findAllByInterface(data,
        "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.DescriptiveShovelerWidgetElement", [], 0);
      for (var dsi = 0; dsi < descriptiveShovelers.length; dsi++) {
        var dWidget = descriptiveShovelers[dsi];
        if (!dWidget.items || !dWidget.header) continue;
        var dHeader = typeof dWidget.header === "string" ? dWidget.header : "";
        if (dHeader !== "Top Songs" && dHeader !== "Songs") continue;
        for (var di = 0; di < dWidget.items.length; di++) {
          var trackItem = dWidget.items[di];
          var trackName = textValue(trackItem.primaryText);
          if (!trackName) continue;
          trackName = trackName.replace(/^\d+\.\s+/, "");
          var trackDeeplink = "";
          if (trackItem.primaryLink && trackItem.primaryLink.deeplink) {
            trackDeeplink = trackItem.primaryLink.deeplink;
          } else if (trackItem.primaryTextLink && trackItem.primaryTextLink.deeplink) {
            trackDeeplink = trackItem.primaryTextLink.deeplink;
          }
          if (!trackDeeplink || trackDeeplink.indexOf("trackAsin") < 0) continue;
          var trackInfo = extractAmazonDeeplinkInfo(trackDeeplink);
          if (!trackInfo || !trackInfo.id) continue;
          var trackArtist = textValue(trackItem.secondaryText) || result.name || "";
          var trackImage = trackItem.image ? ensureHighResCoverUrl(trackItem.image) : "";
          result.top_tracks.push({
            id: trackInfo.id,
            title: trackName,
            artist: trackArtist,
            duration: 0,
            duration_ms: 0,
            cover_art: trackImage,
            deeplink: trackDeeplink,
            track_number: di + 1,
            album_id: trackInfo.albumId || ""
          });
        }
        break;
      }
    }

    for (var t = 0; t < result.top_tracks.length; t++) {
      result.top_tracks[t].artist = result.name;
      result.top_tracks[t].artist_id = artistId;
    }
  }

  return result;
}

function buildArtistFromSearch(artistId, query, context) {
  if (!query) return null;
  var results = customSearchSync(query, { context: context });
  if (!results || !results.length) return null;
  var songResults = customSearchSync(query, { filter: "songs", context: context });
  if (!songResults) songResults = [];

  var artistName = "";
  var artistImage = "";
  var albums = [];
  var topTracks = [];

  for (var i = 0; i < results.length; i++) {
    var item = results[i];
    if (!item) continue;
    if (item.item_type === "artist" && (!artistName || item.id === artistId)) {
      artistName = item.name || artistName;
      artistImage = item.cover_url || artistImage;
      if (item.id === artistId) break;
    }
  }

  if (!artistName) artistName = slugToName(query);
  if (!artistName) return null;

  for (var j = 0; j < results.length; j++) {
    var candidate = results[j];
    if (!candidate) continue;
    if (candidate.item_type === "album" && candidate.artists && candidate.artists.toLowerCase() === artistName.toLowerCase()) {
      albums.push({
        id: candidate.id,
        title: candidate.name || "",
        cover_art: candidate.cover_url || "",
        artist: artistName,
        type: "album"
      });
      rememberResourceContext("album", candidate.id, context);
    }
    if (candidate.item_type === "track" && candidate.artists && candidate.artists.toLowerCase().indexOf(artistName.toLowerCase()) >= 0) {
      topTracks.push({
        id: candidate.id,
        title: candidate.name || "",
        artist: artistName,
        artist_id: artistId,
        duration_ms: candidate.duration_ms || 0,
        cover_art: candidate.cover_url || "",
        album_id: candidate.album_id || ""
      });
      rememberResourceContext("track", candidate.id, context);
    }
  }

  for (var s = 0; s < songResults.length; s++) {
    var song = songResults[s];
    if (!song || song.item_type !== "track") continue;
    if (!song.artists || song.artists.toLowerCase().indexOf(artistName.toLowerCase()) < 0) continue;

    var duplicate = false;
    for (var existing = 0; existing < topTracks.length; existing++) {
      if (topTracks[existing].id === song.id) {
        duplicate = true;
        break;
      }
    }
    if (duplicate) continue;

    topTracks.push({
      id: song.id,
      title: song.name || "",
      artist: artistName,
      artist_id: artistId,
      duration_ms: song.duration_ms || 0,
      cover_art: song.cover_url || "",
      album_id: song.album_id || ""
    });
    rememberResourceContext("track", song.id, context);
  }

  rememberResourceHint("artist", artistId, { name: artistName, image: artistImage });

  return {
    id: artistId,
    name: artistName,
    image: artistImage,
    albums: albums,
    releases: [],
    top_tracks: topTracks,
    type: "artist"
  };
}

function mergeArtistFallbackData(artist, fallbackArtist) {
  if (!fallbackArtist) return artist;
  if (!artist.name && fallbackArtist.name) artist.name = fallbackArtist.name;
  if (!artist.image && fallbackArtist.image) artist.image = fallbackArtist.image;
  if ((!artist.albums || !artist.albums.length) && fallbackArtist.albums && fallbackArtist.albums.length) {
    artist.albums = fallbackArtist.albums;
  }
  if ((!artist.releases || !artist.releases.length) && fallbackArtist.releases && fallbackArtist.releases.length) {
    artist.releases = fallbackArtist.releases;
  }
  if ((!artist.top_tracks || !artist.top_tracks.length) && fallbackArtist.top_tracks && fallbackArtist.top_tracks.length) {
    artist.top_tracks = fallbackArtist.top_tracks;
  }
  return artist;
}

function getArtist(artistId) {
  L("info", "[Amazon] getArtist:", artistId);

  var cacheKey = "artist_" + artistId;
  var cached = cacheGet(cacheKey);
  if (cached) return cached;

  var context = getResourceContext("artist", artistId, null);
  var hintedName = getResourceHint("artist", artistId, "name");
  var deeplink = "/artists/" + artistId;
  var slug = hintedName ? hintedName.toLowerCase().replace(/\s+/g, "-") : "";
  if (slug) deeplink += "/" + slug;

  // Try showCatalogArtist first (returns separate Releases + Top Albums sections)
  var result = fetchWithRetry(function() {
    return callShowCatalogArtist(artistId, slug, context);
  });
  if (!result) {
    L("info", "[Amazon] getArtist showCatalogArtist failed, falling back to showHome");
    result = fetchWithRetry(function() {
      return callShowHome(deeplink, context);
    });
  }

  if (!result) {
    var fallbackArtist = buildArtistFromSearch(artistId, hintedName, context);
    if (!fallbackArtist) {
      L("error", "[Amazon] Failed to fetch artist:", artistId);
      return null;
    }
    var fallbackResult = {
      success: true,
      id: artistId,
      name: fallbackArtist.name || hintedName || "",
      image_url: fallbackArtist.image || "",
      header_image: fallbackArtist.image || "",
      albums: fallbackArtist.albums || [],
      releases: fallbackArtist.releases || [],
      top_tracks: fallbackArtist.top_tracks || []
    };
    cacheSet(cacheKey, fallbackResult);
    return fallbackResult;
  }

  var artist = parseArtistFromResponse(result.data, result.rawText, artistId);
  if (!artist.name && hintedName) artist.name = hintedName;
  if (hintedName && (!artist.name || !artist.albums.length || !artist.top_tracks.length)) {
    var parsedFallbackArtist = buildArtistFromSearch(artistId, hintedName, context);
    artist = mergeArtistFallbackData(artist, parsedFallbackArtist);
  }
  rememberResourceContext("artist", artistId, context);
  rememberResourceHint("artist", artistId, { name: artist.name, image: artist.image });

  var albums = [];
  for (var i = 0; i < artist.albums.length; i++) {
      var a = artist.albums[i];
      albums.push({
        id: a.id,
        name: a.name || a.title || "",
        artists: a.artists || a.artist || artist.name || "",
        cover_url: a.cover_url || a.cover_art || "",
        album_type: a.album_type || a.type || "album",
        total_tracks: a.total_tracks || 0,
        release_date: a.release_date || "",
        album_url: amazonAlbumURL(a.id),
        external_urls: amazonAlbumURL(a.id),
        comment: amazonAlbumURL(a.id),
        provider_id: "amazon"
      });
    }

  var releases = [];
  for (var r = 0; r < artist.releases.length; r++) {
      var rel = artist.releases[r];
      releases.push({
        id: rel.id,
        name: rel.name || rel.title || "",
        artists: rel.artists || rel.artist || artist.name || "",
        cover_url: rel.cover_url || rel.cover_art || "",
        album_type: rel.album_type || rel.type || "album",
        total_tracks: rel.total_tracks || 0,
        release_date: rel.release_date || "",
        album_url: amazonAlbumURL(rel.id),
        external_urls: amazonAlbumURL(rel.id),
        comment: amazonAlbumURL(rel.id),
        provider_id: "amazon"
      });
    }

  var topTracks = [];
  for (var j = 0; j < artist.top_tracks.length; j++) {
      var t = artist.top_tracks[j];
      t.artist = t.artists || t.artist || artist.name || "";
      t.artist_id = t.artist_id || artist.id || artistId;
      topTracks.push(formatAmazonTrackMetadata(t, {
        id: t.album_id || "",
        title: t.album_name || "",
        artist: artist.name || "",
        artist_id: artist.id || artistId
      }, t.track_number || 0));
    }

  var result = {
    success: true,
    id: artist.id,
    name: artist.name || "",
    image_url: artist.image || "",
    header_image: artist.image || "",
    albums: albums,
    releases: releases,
    top_tracks: topTracks
  };

  L("info", "[Amazon] Artist parsed:", result.name, "albums:", result.albums.length, "tracks:", result.top_tracks.length);
  cacheSet(cacheKey, result);
  return result;
}

function parseSearchResults(data, filter) {
  var results = [];
  if (!data || !data.methods) return results;

  // Determine which widget types to look for based on filter
  var wantTracks = !filter || filter === "songs";
  var wantAlbums = !filter || filter === "albums";
  var wantArtists = !filter || filter === "artists";
  var wantPlaylists = !filter || filter === "playlists";

  // Find all VisualShovelerWidgetElement - they contain categorized results
  var shovelers = findAllByInterface(data,
    "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.VisualShovelerWidgetElement", [], 0);
  var featuredShovelers = findAllByInterface(data,
    "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.FeaturedShovelerWidgetElement", [], 0);
  var descriptiveShowcases = findAllByInterface(data,
    "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.DescriptiveShowcaseWidgetElement", [], 0);
  for (var fs = 0; fs < featuredShovelers.length; fs++) shovelers.push(featuredShovelers[fs]);
  for (var ds = 0; ds < descriptiveShowcases.length; ds++) shovelers.push(descriptiveShowcases[ds]);

  for (var s = 0; s < shovelers.length; s++) {
    var shoveler = shovelers[s];
    if (!shoveler.items) continue;

    // Check header to determine category
    var shovelerStr = deepStringify(shoveler);
    var isTrackSection = shovelerStr.indexOf('"Songs"') >= 0 || shovelerStr.indexOf('"Top Result"') >= 0;
    var isAlbumSection = shovelerStr.indexOf('"Albums"') >= 0;
    var isArtistSection = shovelerStr.indexOf('"Artists"') >= 0;
    var isPlaylistSection = shovelerStr.indexOf('"Playlists"') >= 0;

    for (var i = 0; i < shoveler.items.length && results.length < CONFIG.maxResults; i++) {
      var item = shoveler.items[i];
      var iface = item["interface"] || "";

      // Track items inside shoveler
      if (wantTracks && (iface.indexOf("DescriptiveRowItemElement") >= 0 || iface.indexOf("SquareHorizontalItemElement") >= 0)) {
        var trackName = textValue(item.primaryText);
        var trackDeeplink = "";
        var trackDuration = 0;
        var trackArtist = "";
        var trackImage = "";
        var trackAlbumId = "";

        if (item.primaryTextLink && item.primaryTextLink.deeplink) {
          trackDeeplink = item.primaryTextLink.deeplink;
        }
        if (!trackDeeplink && item.primaryLink && item.primaryLink.deeplink) {
          trackDeeplink = item.primaryLink.deeplink;
        }
        if (item.secondaryText3) {
          trackDuration = parseDurationMMSS(item.secondaryText3);
        }
        if (!trackDuration && item.duration) {
          trackDuration = parseDurationMMSS(item.duration);
        }
        if (item.secondaryText1) {
          trackArtist = textValue(item.secondaryText1);
        }
        if (!trackArtist) {
          trackArtist = textValue(item.secondaryText);
        }
        if (item.image) trackImage = ensureHighResCoverUrl(item.image);

        var trackInfo = extractAmazonDeeplinkInfo(trackDeeplink);
        var tId = trackInfo ? trackInfo.id : null;
        if (trackInfo) trackAlbumId = trackInfo.albumId || "";
        if (!trackAlbumId && item.primaryLink && item.primaryLink.deeplink) {
          var albumLinkInfo = extractAmazonDeeplinkInfo(item.primaryLink.deeplink);
          if (albumLinkInfo) trackAlbumId = albumLinkInfo.albumId || "";
        }
        if (trackName && tId && trackInfo && trackInfo.type === "track") {
          results.push({
            item_type: "track",
            id: tId,
            name: trackName,
            artists: trackArtist,
            duration_ms: trackDuration * 1000,
            cover_url: trackImage,
            album_id: trackAlbumId,
            album_url: amazonAlbumURL(trackAlbumId),
            comment: amazonAlbumURL(trackAlbumId),
            external_urls: amazonTrackURL(tId),
            provider_id: "amazon",
            explicit: amazonItemIsExplicit(item),
            audio_modes: amazonTrackAudioModes(item)
          });
          rememberResourceContext("track", tId, _currentContext);
          if (trackAlbumId) rememberResourceContext("album", trackAlbumId, _currentContext);
        }
      }

      // Album items with /albums/ deeplink and no trackAsin
      if (wantAlbums && (iface.indexOf("SquareVerticalItemElement") >= 0 || iface.indexOf("SquareHorizontalItemElement") >= 0)) {
        var albumDeeplink = "";
        if (item.primaryLink && item.primaryLink.deeplink) {
          albumDeeplink = item.primaryLink.deeplink;
        }

        var albumInfo = extractAmazonDeeplinkInfo(albumDeeplink);
        if (albumInfo && albumInfo.type === "albums") {
          var aId = albumInfo.id;
          var albumTitle = textValue(item.primaryText);
          var albumArtist = textValue(item.secondaryText);
          var albumImage = item.image ? ensureHighResCoverUrl(item.image) : "";

          if (albumTitle && aId) {
            results.push({
              item_type: "album",
              id: aId,
              name: albumTitle,
              artists: albumArtist,
              cover_url: albumImage,
              album_url: amazonAlbumURL(aId),
              external_urls: amazonAlbumURL(aId),
              comment: amazonAlbumURL(aId),
              provider_id: "amazon"
            });
            rememberResourceContext("album", aId, _currentContext);
          }
        }
      }

      // Artist items (CircleVerticalItemElement or SquareVerticalItemElement with /artists/)
      if (wantArtists && (iface.indexOf("CircleVerticalItemElement") >= 0 || iface.indexOf("SquareVerticalItemElement") >= 0)) {
        var artistDeeplink = "";
        if (item.primaryLink && item.primaryLink.deeplink) {
          artistDeeplink = item.primaryLink.deeplink;
        }

        if (artistDeeplink.indexOf("/artists/") >= 0) {
          var arId = extractDeeplinkId(artistDeeplink);
          var artistName = textValue(item.primaryText);
          var artistImage = item.image ? ensureHighResCoverUrl(item.image) : "";

          if (artistName && arId) {
            results.push({
              item_type: "artist",
              id: arId,
              name: artistName,
              artists: artistName,
              cover_url: artistImage,
              artist_url: amazonArtistURL(arId),
              external_urls: amazonArtistURL(arId),
              provider_id: "amazon"
            });
            rememberResourceContext("artist", arId, _currentContext);
            rememberResourceHint("artist", arId, { name: artistName, image: artistImage });
          }
        }
      }

      // Playlist items (SquareVerticalItemElement with /playlists/)
      if (wantPlaylists && iface.indexOf("SquareVerticalItemElement") >= 0) {
        var plDeeplink = "";
        if (item.primaryLink && item.primaryLink.deeplink) {
          plDeeplink = item.primaryLink.deeplink;
        }

        if (plDeeplink.indexOf("/playlists/") >= 0) {
          var plId = extractDeeplinkId(plDeeplink);
          var plTitle = textValue(item.primaryText);
          var plImage = item.image ? ensureHighResCoverUrl(item.image) : "";

          if (plTitle && plId) {
            results.push({
              item_type: "playlist",
              id: plId,
              name: plTitle,
              cover_url: plImage,
              external_urls: ((_currentContext && _currentContext.musicBaseURL) || CONFIG.musicBaseURL) + "/playlists/" + plId,
              provider_id: "amazon"
            });
            rememberResourceContext("playlist", plId, _currentContext);
            rememberResourceHint("playlist", plId, { name: plTitle, cover_art: plImage });
          }
        }
      }
    }
  }

  // Also check DescriptiveTableWidgetElement for track results not in shovelers
  if (wantTracks && results.length < CONFIG.maxResults) {
    var tables = findAllByInterface(data,
      "Web.TemplatesInterface.v1_0.Touch.WidgetsInterface.DescriptiveTableWidgetElement", [], 0);
    for (var tb = 0; tb < tables.length; tb++) {
      if (!tables[tb].items) continue;
      for (var ti = 0; ti < tables[tb].items.length && results.length < CONFIG.maxResults; ti++) {
        var tItem = tables[tb].items[ti];
        if (!tItem.primaryText) continue;
        var tName = textValue(tItem.primaryText);
        var tDl = (tItem.primaryTextLink && tItem.primaryTextLink.deeplink) ? tItem.primaryTextLink.deeplink : "";
        var tDur = tItem.secondaryText3 ? parseDurationMMSS(tItem.secondaryText3) : 0;
        var tArt = "";
        if (tItem.secondaryText1) {
          tArt = textValue(tItem.secondaryText1);
        }
        var tImg = tItem.image ? ensureHighResCoverUrl(tItem.image) : "";
        var tInfo = extractAmazonDeeplinkInfo(tDl);
        var tTrackId = tInfo ? tInfo.id : null;

        if (tName && tTrackId) {
          // Check for duplicates
          var dup = false;
          for (var d = 0; d < results.length; d++) {
            if (results[d].id === tTrackId) { dup = true; break; }
          }
          if (!dup) {
            results.push({
              item_type: "track",
              id: tTrackId,
              name: tName,
              artists: tArt,
              duration_ms: tDur * 1000,
              cover_url: tImg,
              album_id: tInfo ? tInfo.albumId || "" : "",
              album_url: amazonAlbumURL(tInfo ? tInfo.albumId || "" : ""),
              comment: amazonAlbumURL(tInfo ? tInfo.albumId || "" : ""),
              external_urls: amazonTrackURL(tTrackId),
              provider_id: "amazon",
              explicit: amazonItemIsExplicit(tItem),
              audio_modes: amazonTrackAudioModes(tItem)
            });
            rememberResourceContext("track", tTrackId, _currentContext);
          }
        }
      }
    }
  }

  return results;
}

function customSearchSync(query, options) {
  L("info", "[Amazon] customSearch:", query);

  var filter = null;
  var context = _currentContext;
  if (options && options.filter) filter = options.filter;
  if (options && options.context) context = options.context;

  var cacheRegion = String((context && (context.host || context.musicTerritory)) || CONFIG.musicTerritory || "US").toLowerCase();
  var cacheKey = "search_" + cacheRegion + "_" + query + "_" + (filter || "all");
  var cached = cacheGet(cacheKey);
  if (cached) return cached;

  var data = fetchWithRetry(function() {
    return callShowSearch(query, context);
  });

  if (!data) {
    L("error", "[Amazon] Search failed for:", query);
    return [];
  }

  var results = parseSearchResults(data, filter);
  L("info", "[Amazon] Search returned", results.length, "results");

  cacheSet(cacheKey, results);
  return results;
}

var __upstream_initialize = function(config) {
    var settings = config && config.settings ? config.settings : (config || {});
    _homeCountry = String(settings.homeCountry || "US").trim().toUpperCase();
    L("info", "[Amazon] Extension v" + EXTENSION_VERSION + " init");
    initSession();
    return true;
  };
var __upstream_cleanup = function() {
    L("info", "[Amazon] Extension cleanup");
    _cache = new Map();
    _resourceContexts = new Map();
    _resourceHints = new Map();
    _currentContext = createAmazonContext(CONFIG.musicBaseURL);
    _session.initialized = false;
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
