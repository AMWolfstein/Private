// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/jiosaavn/index.js
// Inactive source import: no app integration or update trust policy is installed.

var EXT_ID = "jiosaavn";

var API_HOST = 'https://www.jiosaavn.com';

var API_BASE = API_HOST + '/api.php';

var REFERER = API_HOST + '/';

var UA = 'Mozilla/5.0';

var COOKIE_BASE = 'DL=english; geo=19.0760%2C72.8777%2CIN%2CMaharashtra%2CMumbai%2C400001';

var DEFAULT_HEADERS = {
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'en-US,en;q=0.9',
    'X-Requested-With': 'XMLHttpRequest',
    'Referer': REFERER,
    'User-Agent': UA,
};

var API_DEFAULTS = {
    _format: 'json',
    _marker: 0,
    api_version: 4,
    ctx: 'web6dot0'
};

function fetchAPI(url, options) {
    options = options || {};
    var headers = options.headers || {};

    // Build dynamic cookie
    var lang = storage.get("lang") || 'english';
    var cookie = COOKIE_BASE + '; L=' + lang;

    // Add cookie to headers
    headers['Cookie'] = cookie;

    var response;
    // log.debug('[fetchAPI] Request URL: ' + url);

    response = http.get(url, headers);
    if (!response) {
        log.debug('[fetchAPI] No response from server');
        if (options.throwOnError) throw new Error('No response from JioSaavn');
        return null;
    }
    // log.debug('[fetchAPI] Status: ' + response.statusCode + ', OK: ' + response.ok);
    if (!response.ok) {
        log.debug('[fetchAPI] Response body: ' + (response.body || '').substring(0, 200));
        if (options.throwOnError) throw new Error(response.error || ('HTTP ' + response.statusCode + ' from JioSaavn'));
        return null;
    }

    try {
        var parsed = JSON.parse(response.body);
        // log.debug('[fetchAPI] Parsed JSON successfully (keys: ' + Object.keys(parsed).join(', ') + ')');
        return parsed;
    } catch (e) {
        log.debug('[fetchAPI] JSON parse error: ' + e.message);
        log.debug('[fetchAPI] Raw body: ' + (response.body || '').substring(0, 200));
        return null;
    }
}

function callAPI(call, extraParams, options) {
    // Start with defaults
    var params = { __call: call };
    for (var key in API_DEFAULTS) {
        params[key] = API_DEFAULTS[key];
    }
    if (extraParams) {
        for (var key in extraParams) {
            params[key] = extraParams[key];
        }
    }

    // Build query string
    var qParts = [];
    for (var key in params) {
        qParts.push(enc(key) + '=' + enc(params[key]));
    }
    var endpoint = '?' + qParts.join('&');
    var url = API_BASE + endpoint;
    log.debug('[callAPI] Call: ' + call + ', URL: ' + url);

    // Pass DEFAULT_HEADERS (without Cookie) – fetchAPI will add it dynamically
    var result = fetchAPI(url, { headers: DEFAULT_HEADERS, throwOnError: !!(options && options.throwOnError) });
    if (!result) {
        log.debug('[callAPI] fetchAPI returned null for ' + call);
    }

    log.debug('[callAPI] fetchAPI succeeded for ' + call);
    return result;
}

function getArtistById(artistId, category) {
    // log.debug('[getArtistById] artistId: ' + artistId);
    var params = {
        artistId: artistId,
        page: 0, // artist uses page starting from 0
        n_song: 50,
        n_album: 50,
        sub_type: '',
        category: category || 'popular',
        sort_order: category === 'latest' ? 'desc' : 'asc'
    };
    var result = callAPI('artist.getArtistPageDetails', params);
    if (!result) {
        log.debug('[getArtistById] No artist found for id: ' + artistId);
        return null;
    }
    log.debug('[getArtistById] Found artist: ' + (result.name || result.title || 'untitled'));
    return result;
}

function getArtist(token, category) {
    // Artist ID prefix detected
    token = catalogReference(token);
    if (!token) return null;
    var artistId = token.replace(/^artistid_/, '');
    if (/^\d+$/.test(artistId)) {
        return getArtistById(artistId, category);
    }

    // log.debug('[getArtist] Token: ' + token + ', category: ' + category);

    var params = {
        token: token,
        type: 'artist',
        p: 0, // artist uses page starting from 0
        n_song: 50,
        n_album: 50,
        sub_type: '',
        category: category || 'popular',
        sort_order: category === 'latest' ? 'desc' : 'asc'
    };
    var result = callAPI('webapi.get', params);
    if (!result) {
        log.debug('[getArtist] No artist found for token: ' + token);
        return null;
    }
    log.debug('[getArtist] Found artist: ' + (result.name || result.title || 'untitled'));
    return result;
}

var S1 = new Int32Array([
    0x1010400, 0,         0x10000,   0x1010404, 0x1010004, 0x10404,   0x4,       0x10000,   0x400,     0x1010400,
    0x1010404, 0x400,     0x1000404, 0x1010004, 0x1000000, 0x4,       0x404,     0x1000400, 0x1000400, 0x10400,
    0x10400,   0x1010000, 0x1010000, 0x1000404, 0x10004,   0x1000004, 0x1000004, 0x10004,   0,         0x404,
    0x10404,   0x1000000, 0x10000,   0x1010404, 0x4,       0x1010000, 0x1010400, 0x1000000, 0x1000000, 0x400,
    0x1010004, 0x10000,   0x10400,   0x1000004, 0x400,     0x4,       0x1000404, 0x10404,   0x1010404, 0x10004,
    0x1010000, 0x1000404, 0x1000004, 0x404,     0x10404,   0x1010400, 0x404,     0x1000400, 0x1000400, 0,
    0x10004,   0x10400,   0,         0x1010004
]);

var S2 = new Int32Array([
    -0x7FEF7FE0, -0x7FFF8000, 0x8000,      0x108020,    0x100000,    0x20,        -0x7FEFFFE0, -0x7FFF7FE0,
    -0x7FFFFFE0, -0x7FEF7FE0, -0x7FEF8000, -0x80000000, -0x7FFF8000, 0x100000,    0x20,        -0x7FEFFFE0,
    0x108000,    0x100020,    -0x7FFF7FE0, 0,           -0x80000000, 0x8000,      0x108020,    -0x7FF00000,
    0x100020,    -0x7FFFFFE0, 0,           0x108000,    0x8020,      -0x7FEF8000, -0x7FF00000, 0x8020,
    0,           0x108020,    -0x7FEFFFE0, 0x100000,    -0x7FFF7FE0, -0x7FF00000, -0x7FEF8000, 0x8000,
    -0x7FF00000, -0x7FFF8000, 0x20,        -0x7FEF7FE0, 0x108020,    0x20,        0x8000,      -0x80000000,
    0x8020,      -0x7FEF8000, 0x100000,    -0x7FFFFFE0, 0x100020,    -0x7FFF7FE0, -0x7FFFFFE0, 0x100020,
    0x108000,    0,           -0x7FFF8000, 0x8020,      -0x80000000, -0x7FEFFFE0, -0x7FEF7FE0, 0x108000
]);

var S3 = new Int32Array([
    0x208,     0x8020200, 0,         0x8020008, 0x8000200, 0,         0x20208,   0x8000200, 0x20008,   0x8000008,
    0x8000008, 0x20000,   0x8020208, 0x20008,   0x8020000, 0x208,     0x8000000, 0x8,       0x8020200, 0x200,
    0x20200,   0x8020000, 0x8020008, 0x20208,   0x8000208, 0x20200,   0x20000,   0x8000208, 0x8,       0x8020208,
    0x200,     0x8000000, 0x8020200, 0x8000000, 0x20008,   0x208,     0x20000,   0x8020200, 0x8000200, 0,
    0x200,     0x20008,   0x8020208, 0x8000200, 0x8000008, 0x200,     0,         0x8020008, 0x8000208, 0x20000,
    0x8000000, 0x8020208, 0x8,       0x20208,   0x20200,   0x8000008, 0x8020000, 0x8000208, 0x208,     0x8020000,
    0x20208,   0x8,       0x8020008, 0x20200
]);

var S4 = new Int32Array([
    0x802001, 0x2081,   0x2081,   0x80,     0x802080, 0x800081, 0x800001, 0x2001,   0,        0x802000, 0x802000,
    0x802081, 0x81,     0,        0x800080, 0x800001, 0x1,      0x2000,   0x800000, 0x802001, 0x80,     0x800000,
    0x2001,   0x2080,   0x800081, 0x1,      0x2080,   0x800080, 0x2000,   0x802080, 0x802081, 0x81,     0x800080,
    0x800001, 0x802000, 0x802081, 0x81,     0,        0,        0x802000, 0x2080,   0x800080, 0x800081, 0x1,
    0x802001, 0x2081,   0x2081,   0x80,     0x802081, 0x81,     0x1,      0x2000,   0x800001, 0x2001,   0x802080,
    0x800081, 0x2001,   0x2080,   0x800000, 0x802001, 0x80,     0x800000, 0x2000,   0x802080
]);

var S5 = new Int32Array([
    0x100,      0x2080100,  0x2080000,  0x42000100, 0x80000,    0x100,      0x40000000, 0x2080000,
    0x40080100, 0x80000,    0x2000100,  0x40080100, 0x42000100, 0x42080000, 0x80100,    0x40000000,
    0x2000000,  0x40080000, 0x40080000, 0,          0x40000100, 0x42080100, 0x42080100, 0x2000100,
    0x42080000, 0x40000100, 0,          0x42000000, 0x2080100,  0x2000000,  0x42000000, 0x80100,
    0x80000,    0x42000100, 0x100,      0x2000000,  0x40000000, 0x2080000,  0x42000100, 0x40080100,
    0x2000100,  0x40000000, 0x42080000, 0x2080100,  0x40080100, 0x100,      0x2000000,  0x42080000,
    0x42080100, 0x80100,    0x42000000, 0x42080100, 0x2080000,  0,          0x40080000, 0x42000000,
    0x80100,    0x2000100,  0x40000100, 0x80000,    0,          0x40080000, 0x2080100,  0x40000100
]);

var S6 = new Int32Array([
    0x20000010, 0x20400000, 0x4000,     0x20404010, 0x20400000, 0x10,       0x20404010, 0x400000,
    0x20004000, 0x404010,   0x400000,   0x20000010, 0x400010,   0x20004000, 0x20000000, 0x4010,
    0,          0x400010,   0x20004010, 0x4000,     0x404000,   0x20004010, 0x10,       0x20400010,
    0x20400010, 0,          0x404010,   0x20404000, 0x4010,     0x404000,   0x20404000, 0x20000000,
    0x20004000, 0x10,       0x20400010, 0x404000,   0x20404010, 0x400000,   0x4010,     0x20000010,
    0x400000,   0x20004000, 0x20000000, 0x4010,     0x20000010, 0x20404010, 0x404000,   0x20400000,
    0x404010,   0x20404000, 0,          0x20400010, 0x10,       0x4000,     0x20400000, 0x404010,
    0x4000,     0x400010,   0x20004010, 0,          0x20404000, 0x20000000, 0x400010,   0x20004010
]);

var S7 = new Int32Array([
    0x200000,  0x4200002, 0x4000802, 0,         0x800,     0x4000802, 0x200802,  0x4200800, 0x4200802, 0x200000,
    0,         0x4000002, 0x2,       0x4000000, 0x4200002, 0x802,     0x4000800, 0x200802,  0x200002,  0x4000800,
    0x4000002, 0x4200000, 0x4200800, 0x200002,  0x4200000, 0x800,     0x802,     0x4200802, 0x200800,  0x2,
    0x4000000, 0x200800,  0x4000000, 0x200800,  0x200000,  0x4000802, 0x4000802, 0x4200002, 0x4200002, 0x2,
    0x200002,  0x4000000, 0x4000800, 0x200000,  0x4200800, 0x802,     0x200802,  0x4200800, 0x802,     0x4000002,
    0x4200802, 0x4200000, 0x200800,  0,         0x2,       0x4200802, 0,         0x200802,  0x4200000, 0x800,
    0x4000002, 0x4000800, 0x800,     0x200002
]);

var S8 = new Int32Array([
    0x10001040, 0x1000,     0x40000,    0x10041040, 0x10000000, 0x10001040, 0x40,       0x10000000,
    0x40040,    0x10040000, 0x10041040, 0x41000,    0x10041000, 0x41040,    0x1000,     0x40,
    0x10040000, 0x10000040, 0x10001000, 0x1040,     0x41000,    0x40040,    0x10040040, 0x10041000,
    0x1040,     0,          0,          0x10040040, 0x10000040, 0x10001000, 0x41040,    0x40000,
    0x41040,    0x40000,    0x10041000, 0x1000,     0x40,       0x10040040, 0x1000,     0x41040,
    0x10001000, 0x40,       0x10000040, 0x10040000, 0x10040040, 0x10000000, 0x40000,    0x10001040,
    0,          0x10041040, 0x40040,    0x10000040, 0x10040000, 0x10001000, 0x10001040, 0,
    0x10041040, 0x41000,    0x41000,    0x1040,     0x1040,     0x40040,    0x10000000, 0x10041000
]);

function desBlock(message, keys, encrypt) {
    var s1 = S1, s2 = S2, s3 = S3, s4 = S4;
    var s5 = S5, s6 = S6, s7 = S7, s8 = S8;
    if (encrypt) {
        var padLen = 8 - (message.length % 8);
        for (var p = 0; p < padLen; p++) {
            message += String.fromCharCode(padLen);
        }
    }
    var len = message.length;
    var result = '';
    var left, right, temp;
    for (var m = 0; m < len; m += 8) {
        left = (message.charCodeAt(m) << 24) | (message.charCodeAt(m + 1) << 16) | (message.charCodeAt(m + 2) << 8) |
            message.charCodeAt(m + 3);
        right = (message.charCodeAt(m + 4) << 24) | (message.charCodeAt(m + 5) << 16) |
            (message.charCodeAt(m + 6) << 8) | message.charCodeAt(m + 7);
        temp = ((left >>> 4) ^ right) & 0x0F0F0F0F;
        right ^= temp;
        left ^= (temp << 4);
        temp = ((left >>> 16) ^ right) & 0x0000FFFF;
        right ^= temp;
        left ^= (temp << 16);
        temp = ((right >>> 2) ^ left) & 0x33333333;
        left ^= temp;
        right ^= (temp << 2);
        temp = ((right >>> 8) ^ left) & 0x00FF00FF;
        left ^= temp;
        right ^= (temp << 8);
        temp = ((left >>> 1) ^ right) & 0x55555555;
        right ^= temp;
        left ^= (temp << 1);
        left = ((left << 1) | (left >>> 31));
        right = ((right << 1) | (right >>> 31));
        var start = encrypt ? 0 : 30;
        var end = encrypt ? 32 : -2;
        var step = encrypt ? 2 : -2;
        for (var i = start; i !== end; i += step) {
            var right1 = right ^ keys[i];
            var rrot = (right >>> 4) | (right << 28);
            var right2 = rrot ^ keys[i + 1];
            temp = left;
            left = right;
            right = temp ^
                (s2[(right1 >>> 24) & 63] | s4[(right1 >>> 16) & 63] | s6[(right1 >>> 8) & 63] | s8[right1 & 63] |
                 s1[(right2 >>> 24) & 63] | s3[(right2 >>> 16) & 63] | s5[(right2 >>> 8) & 63] | s7[right2 & 63]);
        }
        temp = left;
        left = right;
        right = temp;
        left = ((left >>> 1) | (left << 31));
        right = ((right >>> 1) | (right << 31));
        temp = ((left >>> 1) ^ right) & 0x55555555;
        right ^= temp;
        left ^= (temp << 1);
        temp = ((right >>> 8) ^ left) & 0x00FF00FF;
        left ^= temp;
        right ^= (temp << 8);
        temp = ((right >>> 2) ^ left) & 0x33333333;
        left ^= temp;
        right ^= (temp << 2);
        temp = ((left >>> 16) ^ right) & 0x0000FFFF;
        right ^= temp;
        left ^= (temp << 16);
        temp = ((left >>> 4) ^ right) & 0x0F0F0F0F;
        right ^= temp;
        left ^= (temp << 4);
        result += String.fromCharCode(
            (left >>> 24), ((left >>> 16) & 0xFF), ((left >>> 8) & 0xFF), (left & 0xFF), (right >>> 24),
            ((right >>> 16) & 0xFF), ((right >>> 8) & 0xFF), (right & 0xFF));
    }
    return result;
}

function desDecrypt(message, keys) {
    return desBlock(message, keys, false);
}

var DES_KEY = new Uint32Array([
    36443656, 338827529, 170141697, 338826299, 170272797, 875566612, 170276616, 941097494,
    153487137, 941103620, 154281006, 940128288, 221380890, 688468270, 621941049, 688727305,
    622007300, 151861785, 890309646, 184882698, 874054925, 50799890, 874062625, 117842443,
    805908001, 119942188, 839720978, 102894652, 302780946, 103954180, 302782501, 338829583
]);

function base64ToBinaryString(str) {
    var chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
    str = str.replace(/=+$/, '');
    var binary = '';
    var len = str.length;
    for (var i = 0; i < len; i += 4) {
        var c1 = chars.indexOf(str.charAt(i));
        var c2 = chars.indexOf(str.charAt(i + 1));
        var c3 = chars.indexOf(str.charAt(i + 2));
        var c4 = chars.indexOf(str.charAt(i + 3));
        var byte1 = (c1 << 2) | (c2 >> 4);
        var byte2 = ((c2 & 15) << 4) | (c3 >> 2);
        var byte3 = ((c3 & 3) << 6) | c4;
        binary += String.fromCharCode(byte1);
        if (c3 !== -1 && i + 2 < len) binary += String.fromCharCode(byte2);
        if (c4 !== -1 && i + 3 < len) binary += String.fromCharCode(byte3);
    }
    return binary;
}

function decryptMediaUrl(encrypted) {
    if (typeof encrypted !== 'string' || !encrypted) return '';
    var binary = base64ToBinaryString(encrypted);
    if (!binary.length || binary.length % 8) return '';
    var plain = desDecrypt(binary, DES_KEY);
    // Remove PKCS#7 padding (last byte = pad length)
    var padLen = plain.charCodeAt(plain.length - 1);
    if (padLen > 0 && padLen <= 8) plain = plain.slice(0, plain.length - padLen);
    return mediaUrl(plain);
}

var TRACKING_KEY = "__cache_keys";

function getCache(key) {
    try {
        return storage.get(key);
    } catch (e) {
        log.debug("getCache error:", e.message);
        return null;
    }
}

function setCache(key, value) {
    try {
        storage.set(key, value);
        // Track the key
        var list = getCache(TRACKING_KEY);
        var keys = list ? JSON.parse(list) : [];
        if (keys.indexOf(key) === -1) {
            keys.push(key);
            storage.set(TRACKING_KEY, JSON.stringify(keys));
        }
        // log.debug("setCache: stored", key);
    } catch (e) {
        log.debug("setCache error:", e.message);
    }
}

function clearCache() {
    try {
        var list = getCache(TRACKING_KEY);
        if (list) {
            var keys = JSON.parse(list);
            for (var i = 0; i < keys.length; i++) {
                storage.remove(keys[i]);
            }
            storage.remove(TRACKING_KEY);
            log.debug("clearCache: removed", keys.length, "keys");
        } else {
            log.debug("clearCache: no keys to clear");
        }
    } catch (e) {
        log.debug("clearCache error:", e.message);
    }
}

function cleanup(force) {
    try {
        var now = Date.now();
        var last = getCache("last_cleanup");
        var lastTime = last ? parseInt(last, 10) : 0;
        var age = now - lastTime;
        var threshold = 24 * 60 * 60 * 1000; // 24 hours

        if (force || lastTime === 0 || age > threshold) {
            clearCache();
            setCache("last_cleanup", String(now));
            var msg = force ? "forced" : ("last cleanup was " + (lastTime ? Math.round(age / 60000) : "never") + " min ago");
            log.info("[Extension] Cleanup: storage cache cleared (" + msg + ")");
             return { success: true, message: "Cache cleared!" };
        } else {
            var remaining = threshold - age;
            var remainingMinutes = Math.ceil(remaining / 60000);
            log.debug("[Extension] Cleanup skipped – next cleanup in " + remainingMinutes + " minute(s)");
            return false;
        }
    } catch (e) {
        log.error("[Extension] Cleanup error: " + e.message);
        return false;
    }
}

function initialize(config) {
    var settings = config || {};
    log.info("Extension initialized with settings:", settings.lang);

    storage.set("lang", settings.lang || 'english');
    // Run cleanup on init
    cleanup();
    return true;
}

function enc(v) {
    return encodeURIComponent(String(v == null ? "" : v));
}

function decodeEntities(s) {
    if (s == null) return "";
    return String(s)
        .replace(/&quot;/g, '"')
        .replace(/&apos;/g, "'")
        .replace(/&nbsp;/g, ' ')
        .replace(/&lt;/g, '<')
        .replace(/&gt;/g, '>')
        .replace(/&#(x[0-9a-f]+|\d+);/gi, function (m, d) {
            var value = d.charAt(0).toLowerCase() === 'x' ? parseInt(d.slice(1), 16) : parseInt(d, 10);
            return value <= 0x10ffff ? String.fromCodePoint(value) : m;
        })
        .replace(/&amp;/g, '&').trim();
}

function extractToken(permaUrl) {
    if (!permaUrl) return null;
    var parts = String(permaUrl).split(/[?#]/)[0].replace(/\/+$/, '').split("/");
    return parts[parts.length - 1] || null;
}

function catalogReference(value) {
    value = String(value == null ? '' : value).trim();
    if (/^https?:\/\//i.test(value)) value = extractToken(value) || '';
    return /^[A-Za-z0-9_,.-]{1,128}$/.test(value) ? value : '';
}

function mediaUrl(value) {
    var url = String(value || '').trim().replace(/^http:/, 'https:');
    return /^https:\/\/aac\.saavncdn\.com\//i.test(url) ? url : '';
}

function recordingIsrc(value) {
    var isrc = String(value || '').toUpperCase().replace(/[\s-]/g, '');
    return /^[A-Z]{2}[A-Z0-9]{3}\d{7}$/.test(isrc) ? isrc : '';
}

function getHighResImageUrl(url) {
    if (!url) return '';
    return String(url).replace(/^http:/, 'https:').replace(/(?:50|150)x(?:50|150)(\.[a-z]+)(?=[?#]|$)/i, '500x500$1');
}

function extractArtistNames(item) {
    if (!item) return '';
    var moreInfo = item.more_info || {};
    var artistMap = moreInfo.artistMap || {};
    var artists = (artistMap.primary_artists || []).concat(artistMap.featured_artists || []);
    var names = artists.map(function(artist) { return decodeEntities(artist.name); })
        .filter(function(name, index, values) { return name && values.indexOf(name) === index; });
    return names.join(', ') || decodeEntities(item.primary_artists || moreInfo.primary_artists ||
        String(item.subtitle || '').split(' - ')[0]);
}

function positiveInt(value) {
    var number = Number(value);
    return Number.isFinite(number) && number > 0 ? Math.floor(number) : 0;
}

function formatSong(song, album, index) {
    if (!song) return null;
    var token = extractToken(song.perma_url);
    var id = String(song.id || token || '');
    if (!id) return null;

    // log.debug("[formatSong] token: " + token);

    var more = song.more_info || {};
    var duration = Number(more.duration || song.duration || 0);

    var decryptedFull = decryptMediaUrl(more.encrypted_media_url);

    // Album artist
    var artistMap = more.artistMap || {};
    var primaryArtists = artistMap.primary_artists || [];
    var primary = primaryArtists[0] || {};
    var albumArtist = (album && album.artists) || primaryArtists.map(function(artist) {
        return decodeEntities(artist.name);
    }).filter(Boolean).join(', ') || extractArtistNames(song);
    var composers = (artistMap.artists || []).filter(function(artist) {
        return /^(music|composer)$/i.test(artist.role || '');
    }).map(function(artist) { return decodeEntities(artist.name); })
        .filter(function(name, position, values) { return name && values.indexOf(name) === position; });
    var trackNumber = positiveInt(more.track_number || song.track_number) ||
        (typeof index === 'number' ? index + 1 : 0);

    var formatted = {
        id: id,
        name: decodeEntities(song.title || song.song || ""),
        artists: extractArtistNames(song),
        album_name: decodeEntities(more.album || song.album || album && album.name || ""),
        album_id: String(more.album_id || song.albumid || album && album.id || extractToken(more.album_url) || ''),
        album_url: String(more.album_url || song.album_url || album && album.url || ''),
        album_artist: decodeEntities(albumArtist),
        artist_id: String(primary.id || String(song.primary_artists_id || '').split(',')[0] || ''),
        artist_url: String(primary.perma_url || ''),
        duration_ms: Number.isFinite(duration) ? Math.max(0, Math.round(duration * 1000)) : 0,
        cover_url: getHighResImageUrl(song.image || album && album.cover_url) || "",
        external_urls: String(song.perma_url || ''),
        preview_url: decryptedFull, // can play song for small duration
        release_date: String(more.release_date || song.release_date || song.year || album && album.release_date || ''),
        track_number: trackNumber,
        total_tracks: positiveInt(more.total_tracks || song.total_tracks || album && album.total_tracks),
        disc_number: positiveInt(more.disc_number || song.disc_number) || 1,
        total_discs: positiveInt(more.total_discs || song.total_discs),
        composer: composers.join(', ') || decodeEntities(more.music || song.music || ""),
        isrc: recordingIsrc(more.isrc || song.isrc),
        audio_quality: "AAC",
        item_type: "track",
        provider_id: EXT_ID,

        genre: decodeEntities(more.genre || song.genre || ""),
        label: decodeEntities(more.label || ""),
        copyright: decodeEntities(more.copyright_text || ""),
        explicit: song.explicit_content === '1' || song.explicit_content === 1 || song.explicit_content === true
    };

    return formatted;
}

function formatCollection(item, type, isDetail) {
    if (!item) {
        log.debug("[formatCollection] item is null/undefined");
        return null;
    }
    var token = String(item.id || item.albumid || extractToken(item.perma_url) || '');
    if (!token) {
        log.debug("[formatCollection] Failed to extract token for", type);
        return null;
    }
    // log.debug("[formatCollection] token: " + token + ", type: " + type + ", isDetail: " + isDetail);

    var songs = Array.isArray(item.list) ? item.list : Array.isArray(item.songs) ? item.songs : [];
    var more = item.more_info || {};
    var total = positiveInt(item.song_count || more.song_count || more.songs_count || item.list_count) || songs.length;

    var result = {
        id: token,
        name: decodeEntities(item.title || ""),
        cover_url: getHighResImageUrl(item.image) || "",
        total_tracks: total,
        item_type: type,
        url: String(item.perma_url || ''),
        provider_id: EXT_ID
    };

    if (type === 'album') {
        result.artists = extractArtistNames(item);
        result.artist_id = String((more.artistMap && more.artistMap.primary_artists && more.artistMap.primary_artists[0] || {}).id || '');
        result.album_type = item.type || "album";
        result.release_date = String(more.release_date || item.release_date || item.year || '');
    } else {
        result.album_type = "playlist";
    }

    if (isDetail) {
        result.tracks = songs.map(function(song, index) {
            // Playlist position is not an album track number or track total.
            return formatSong(song, type === 'album' ? result : null, type === 'album' ? index : undefined);
        }).filter(function(t) { return t !== null; });
        if (type === 'playlist') result.total_tracks = result.tracks.length;
        log.debug("[formatCollection] Mapped " + result.tracks.length + " tracks for " + type);
    }

    return result;
}

function processArtistSongs(songs) {
    if (!songs || !songs.length) return [];
    return songs.map(function(song) {
        return formatSong(song);
    }).filter(function(t) { return t !== null; });
}

function processArtistAlbums(albums) {
    if (!albums || !albums.length) return [];
    return albums.map(function(album) {
        return formatCollection(album, 'album');
    }).filter(function(a) { return a !== null; });
}

function processArtistSingles(singles, result) {
    if (!singles || !singles.length) return;
    // log.debug("[formatArtist] Found " + singles.length + " single(s)");
    for (var i = 0; i < singles.length; i++) {
        var single = singles[i];
        var formatted = formatCollection(single, 'album');
        if (formatted) {
            formatted.album_type = 'single';
            result.albums.push(formatted);
            // log.debug("[formatArtist] Added single: " + formatted.name);
        }
    }
}

function processCompilations(playlists, result) {
    if (!playlists || !playlists.length) return;
    // log.debug("[formatArtist] Found " + playlists.length + " playlist(s)");
    for (var i = 0; i < playlists.length; i++) {
        var playlist = playlists[i];
        var compilation = formatCollection(playlist, 'playlist');
        if (compilation) {
            // log.debug("[formatArtist] Added compilation: " + compilation.name);
            compilation.id = "playlist_" + compilation.id;
            compilation.item_type = 'album';
            compilation.album_type = 'compilation';
            result.albums.push(compilation);
        }
    }
}

function formatArtist(artist, isDetail) {
    if (!artist) {
        log.debug("[formatArtist] artist is null/undefined");
        return null;
    }

    // Extract token – use overview URL for detail, perma_url for search
    var token = String(artist.artistId || artist.id || extractToken(artist.urls && artist.urls.overview || artist.perma_url) || '');
    if (!token) {
        log.debug("[formatArtist] Failed to extract token");
        return null;
    }

    var result = {
        id: token,
        name: decodeEntities(artist.title || artist.name || ""),
        cover_url: getHighResImageUrl(artist.image) || "",
        image_url: getHighResImageUrl(artist.image) || "",
        item_type: "artist",
        provider_id: EXT_ID
    };

    if (isDetail) {
        result.listeners = positiveInt(String(artist.fan_count || '').replace(/,/g, ''));
        result.image_url = getHighResImageUrl(artist.image) || "";
        result.top_tracks = processArtistSongs(artist.topSongs || []);
        result.albums = processArtistAlbums(artist.topAlbums || []);
        processArtistSingles(artist.singles || [], result);
        processCompilations(artist.dedicated_artist_playlist || [], result);
        processCompilations(artist.featured_artist_playlist || [], result);

        log.debug("[formatArtist] Mapped " + result.top_tracks.length + " top tracks and " + result.albums.length + " albums (including singles and compilations)");
    }

    return result;
}

function getArtistService(token) {
    log.debug('[getArtistService] Artist ID: ' + token);

    // 1. Fetch main artist details
    var artist = getArtist(token);
    if (!artist) {
        log.debug('[getArtistService] No artist found');
        return null;
    }

/*
    // 2. Fetch extra songs (pages 2 and 3)
    var extraSongs = [];
    for (var page = 2; page <= 3; page++) {
        var more = getMoreSongs(artist.artistId, page);
        if (more && more.topSongs.songs && more.topSongs.songs.length) {
            extraSongs = extraSongs.concat(more.topSongs.songs);
        }
    }
    if (extraSongs.length) {
        if (!artist.topSongs) artist.topSongs = [];
        artist.topSongs = artist.topSongs.concat(extraSongs);
        log.debug('[getArtistService] Added ' + extraSongs.length + ' extra songs');
    }

    // 3. Fetch extra albums (pages 2 and 3)
    var extraAlbums = [];
    for (var page = 2; page <= 3; page++) {
        var more = getMoreAlbums(artist.artistId, page);
        if (more && more.topAlbums.albums && more.topAlbums.albums.length) {
            extraAlbums = extraAlbums.concat(more.topAlbums.albums);
        }
    }
    if (extraAlbums.length) {
        if (!artist.topAlbums) artist.topAlbums = [];
        artist.topAlbums = artist.topAlbums.concat(extraAlbums);
        log.debug('[getArtistService] Added ' + extraAlbums.length + ' extra albums');
    }
*/

    // 4. Format and return
    return formatArtist(artist, true);
}

var __upstream_initialize = initialize;
var __upstream_cleanup = cleanup;
var __upstream_getArtist = getArtistService;

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
