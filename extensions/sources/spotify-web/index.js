// SPDX-License-Identifier: LGPL-3.0-only
// Extracted from https://github.com/mornyeapp/Mornye-Extension
// Upstream 12530ceda46dc78a10f9258b7d65a71452dfcf50 / sources/spotify-web/index.js
// Inactive source import: no app integration or update trust policy is installed.

const TOTP_SECRETS = {
  59: [
    123, 105, 79, 70, 110, 59, 52, 125, 60, 49, 80, 70, 89, 75, 80, 86, 63, 53,
    123, 37, 117, 49, 52, 93, 77, 62, 47, 86, 48, 104, 68, 72,
  ],
  60: [
    79, 109, 69, 123, 90, 65, 46, 74, 94, 34, 58, 48, 70, 71, 92, 85, 122, 63,
    91, 64, 87, 87,
  ],
  61: [
    44, 55, 47, 42, 70, 40, 34, 114, 76, 74, 50, 111, 120, 97, 75, 76, 94, 102,
    43, 69, 49, 120, 118, 80, 64, 78,
  ],
};

const TOTP_VERSION = 61;

const TOKEN_EXPIRY_SKEW_MS = 60 * 1000;

let clientState = {
  accessToken: null,
  accessTokenExpiry: 0,
  clientToken: null,
  clientTokenExpiry: 0,
  clientID: null,
  deviceID: null,
  clientVersion: null,
  cookies: {},
  initialized: false,
};

const SPOTIFY_COVER_SIZE_300 = "ab67616d00001e02";

const SPOTIFY_COVER_SIZE_640 = "ab67616d0000b273";

const SPOTIFY_COVER_SIZE_MAX = "ab67616d000082c1";

const nativeTrackMetadataCache = new Map();

const nativeAlbumMetadataCache = new Map();

const deezerTrackMetadataCache = new Map();

const deezerAlbumMetadataCache = new Map();

const spotifyRadioPlaylistCache = new Map();

function initialize(config) {
  log.info("Spotify Web Extension initializing...");

  try {
    const cached = storage.get("client_state");
    if (cached) {
      const parsed = JSON.parse(cached);
      clientState.accessToken = parsed.accessToken || null;
      clientState.accessTokenExpiry = Number(parsed.accessTokenExpiry || 0);
      clientState.clientToken = parsed.clientToken || null;
      clientState.clientTokenExpiry = Number(parsed.clientTokenExpiry || 0);
      clientState.clientID = parsed.clientID || null;
      clientState.deviceID = parsed.deviceID || null;
      clientState.clientVersion = parsed.clientVersion || null;
      clientState.cookies =
        parsed.cookies && typeof parsed.cookies === "object"
          ? parsed.cookies
          : {};
      if (!clientState.deviceID && clientState.cookies.sp_t) {
        clientState.deviceID = clientState.cookies.sp_t;
      }
      clientState.initialized =
        tokenIsUsable(clientState.accessToken, clientState.accessTokenExpiry) &&
        tokenIsUsable(clientState.clientToken, clientState.clientTokenExpiry);

      if (clientState.initialized) {
        log.info("Loaded cached Spotify Web session");
      }
    }
  } catch (e) {
    log.warn(
      "Failed to load cached Spotify Web session:",
      e.message || String(e),
    );
  }

  return true;
}

function persistClientState() {
  try {
    return storage.set("client_state", JSON.stringify(clientState));
  } catch (e) {
    log.warn("Failed to persist Spotify Web session:", e.message || String(e));
    return false;
  }
}

function cleanup() {
  persistClientState();
  nativeTrackMetadataCache.clear();
  nativeAlbumMetadataCache.clear();
  deezerTrackMetadataCache.clear();
  deezerAlbumMetadataCache.clear();
  spotifyRadioPlaylistCache.clear();
}

function tokenIsUsable(token, expiry) {
  if (!token) return false;
  const expiryMs = Number(expiry || 0);
  // Older cached sessions did not store expiry. Reuse them until Spotify
  // rejects them, then the existing 401 retry refreshes and persists expiry.
  return expiryMs <= 0 || Date.now() < expiryMs - TOKEN_EXPIRY_SKEW_MS;
}

function absoluteExpiryMs(value) {
  let expiry = Number(value || 0);
  if (!isFinite(expiry) || expiry <= 0) return 0;
  // Accept either Unix seconds or Unix milliseconds.
  if (expiry < 100000000000) expiry *= 1000;
  return expiry;
}

function relativeExpiryMs(seconds) {
  const ttlSeconds = Number(seconds || 0);
  if (!isFinite(ttlSeconds) || ttlSeconds <= 0) return 0;
  return Date.now() + ttlSeconds * 1000;
}

function generateTOTP() {
  const secretList = TOTP_SECRETS[TOTP_VERSION];

  const transformed = [];
  for (let i = 0; i < secretList.length; i++) {
    transformed.push(secretList[i] ^ ((i % 33) + 9));
  }

  let joined = "";
  for (let i = 0; i < transformed.length; i++) {
    joined += transformed[i].toString();
  }

  let hexStr = "";
  for (let i = 0; i < joined.length; i++) {
    hexStr += joined.charCodeAt(i).toString(16).padStart(2, "0");
  }

  const hexBytes = [];
  for (let i = 0; i < hexStr.length; i += 2) {
    hexBytes.push(parseInt(hexStr.substr(i, 2), 16));
  }

  const secret = base32Encode(hexBytes);

  const counter = Math.floor(Date.now() / 1000 / 30);
  const code = generateTOTPCode(secret, counter);

  return { code: code, version: TOTP_VERSION };
}

function base32Encode(bytes) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  let result = "";
  let bits = 0;
  let value = 0;

  for (let i = 0; i < bytes.length; i++) {
    value = (value << 8) | bytes[i];
    bits += 8;

    while (bits >= 5) {
      result += alphabet[(value >>> (bits - 5)) & 31];
      bits -= 5;
    }
  }

  if (bits > 0) {
    result += alphabet[(value << (5 - bits)) & 31];
  }

  return result;
}

function generateTOTPCode(secret, counter) {
  const key = base32Decode(secret);

  const counterBytes = [];
  let c = counter;
  for (let i = 7; i >= 0; i--) {
    counterBytes[i] = c & 0xff;
    c = Math.floor(c / 256);
  }

  const hmac = utils.hmacSHA1(key, counterBytes);

  const offset = hmac[hmac.length - 1] & 0x0f;
  const code =
    ((hmac[offset] & 0x7f) << 24) |
    ((hmac[offset + 1] & 0xff) << 16) |
    ((hmac[offset + 2] & 0xff) << 8) |
    (hmac[offset + 3] & 0xff);

  const otp = code % 1000000;
  return otp.toString().padStart(6, "0");
}

function base32Decode(str) {
  const alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567";
  str = str.toUpperCase().replace(/=+$/, "");

  const result = [];
  let bits = 0;
  let value = 0;

  for (let i = 0; i < str.length; i++) {
    const idx = alphabet.indexOf(str[i]);
    if (idx === -1) continue;

    value = (value << 5) | idx;
    bits += 5;

    if (bits >= 8) {
      result.push((value >>> (bits - 8)) & 0xff);
      bits -= 8;
    }
  }

  return result;
}

function extractCookies(response) {
  if (!response || !response.headers) return;

  let setCookie =
    response.headers["Set-Cookie"] || response.headers["set-cookie"];
  if (!setCookie) {
    for (const key in response.headers) {
      if (key.toLowerCase() === "set-cookie") {
        setCookie = response.headers[key];
        break;
      }
    }
  }
  if (!setCookie) return;

  const cookieStrings = Array.isArray(setCookie) ? setCookie : [setCookie];

  for (const cookieStr of cookieStrings) {
    const match = cookieStr.match(/^([^=]+)=([^;]*)/);
    if (match) {
      const name = match[1].trim();
      const value = match[2].trim();
      clientState.cookies[name] = value;

      if (name === "sp_t") {
        clientState.deviceID = value;
      }
    }
  }
}

function buildCookieHeader() {
  const parts = [];
  for (const name in clientState.cookies) {
    if (clientState.cookies.hasOwnProperty(name)) {
      parts.push(name + "=" + clientState.cookies[name]);
    }
  }
  return parts.join("; ");
}

function spotifyResponseError(response) {
  if (!response) return "no response";
  if (response.error) return String(response.error);
  return response.statusCode
    ? "HTTP " + response.statusCode
    : "missing HTTP status";
}

function spotifyRequest(method, url, body, headers) {
  var response;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      response =
        method === "POST"
          ? http.post(url, body, headers)
          : http.get(url, headers);
    } catch (error) {
      response = { error: (error && error.message) || String(error) };
    }
    var reason = spotifyResponseError(response);
    var retryable =
      !response ||
      response.error ||
      response.statusCode === 408 ||
      response.statusCode >= 500;
    if (
      attempt === 1 ||
      !retryable ||
      /cancel|denied|not permitted|certificate/i.test(reason)
    )
      break;
    log.warn("Spotify session request retry after:", reason);
    if (typeof utils.sleep === "function" && utils.sleep(250) === false) {
      throw new Error("Spotify request cancelled");
    }
  }
  return response;
}

function ensureDeviceID() {
  if (!clientState.deviceID) {
    // Some session pages do not resend sp_t. Keep one anonymous device ID
    // across token refreshes and application restarts instead of failing.
    clientState.deviceID = clientState.cookies.sp_t || generateDeviceID();
    persistClientState();
  }
  return clientState.deviceID;
}

function getSessionInfo() {
  const headers = {
    "User-Agent": utils.randomUserAgent(),
  };

  const cookieHeader = buildCookieHeader();
  if (cookieHeader) {
    headers["Cookie"] = cookieHeader;
  }

  const response = spotifyRequest(
    "GET",
    "https://open.spotify.com",
    null,
    headers,
  );

  if (!response || response.error || response.statusCode !== 200) {
    throw new Error(
      "Failed to get session info: " + spotifyResponseError(response),
    );
  }

  extractCookies(response);

  const match = response.body.match(
    /<script id="appServerConfig" type="text\/plain">([^<]+)<\/script>/,
  );
  if (match) {
    try {
      const decoded = atob(match[1]);
      const cfg = JSON.parse(decoded);
      clientState.clientVersion = cfg.clientVersion;
    } catch (e) {}
  }

  if (!clientState.clientVersion) {
    throw new Error("Spotify session page did not include a client version");
  }
  ensureDeviceID();
  persistClientState();
}

function getAccessToken() {
  const totp = generateTOTP();

  const url =
    "https://open.spotify.com/api/token?reason=init&productType=web-player" +
    "&totp=" +
    totp.code +
    "&totpVer=" +
    totp.version +
    "&totpServer=" +
    totp.code;

  const headers = {
    "User-Agent": utils.randomUserAgent(),
    "Content-Type": "application/json;charset=UTF-8",
  };

  const cookieHeader = buildCookieHeader();
  if (cookieHeader) {
    headers["Cookie"] = cookieHeader;
  }

  const response = spotifyRequest("GET", url, null, headers);

  if (!response || response.error || response.statusCode !== 200) {
    throw new Error(
      "Failed to get access token: " + spotifyResponseError(response),
    );
  }

  extractCookies(response);

  const data = JSON.parse(response.body);
  if (!data || !data.accessToken || !data.clientId) {
    throw new Error("Spotify access token response is incomplete");
  }
  clientState.accessToken = data.accessToken;
  clientState.accessTokenExpiry = absoluteExpiryMs(
    data.accessTokenExpirationTimestampMs ||
      data.accessTokenExpirationTimestamp,
  );
  clientState.clientID = data.clientId;
  persistClientState();

  return clientState.accessToken;
}

function getClientToken() {
  if (!clientState.clientVersion) {
    getSessionInfo();
  }
  if (
    !clientState.clientID ||
    !tokenIsUsable(clientState.accessToken, clientState.accessTokenExpiry)
  ) {
    getAccessToken();
  }
  ensureDeviceID();

  const payload = {
    client_data: {
      client_version: clientState.clientVersion,
      client_id: clientState.clientID,
      js_sdk_data: {
        device_brand: "unknown",
        device_model: "unknown",
        os: "windows",
        os_version: "NT 10.0",
        device_id: clientState.deviceID,
        device_type: "computer",
      },
    },
  };

  const response = spotifyRequest(
    "POST",
    "https://clienttoken.spotify.com/v1/clienttoken",
    JSON.stringify(payload),
    {
      Authority: "clienttoken.spotify.com",
      "Content-Type": "application/json",
      Accept: "application/json",
      "User-Agent": utils.randomUserAgent(),
    },
  );

  if (!response || response.error || response.statusCode !== 200) {
    throw new Error(
      "Failed to get client token: " + spotifyResponseError(response),
    );
  }

  const data = JSON.parse(response.body);
  if (data.response_type !== "RESPONSE_GRANTED_TOKEN_RESPONSE") {
    throw new Error("Invalid client token response: " + data.response_type);
  }
  if (!data.granted_token || !data.granted_token.token) {
    throw new Error("Spotify client token response is incomplete");
  }

  clientState.clientToken = data.granted_token.token;
  clientState.clientTokenExpiry = relativeExpiryMs(
    data.granted_token.expires_after_seconds,
  );
  clientState.initialized = true;
  persistClientState();

  return clientState.clientToken;
}

function generateDeviceID() {
  const chars = "0123456789abcdef";
  let result = "";
  for (let i = 0; i < 32; i++) {
    result += chars.charAt(Math.floor(Math.random() * chars.length));
  }
  return result;
}

function ensureInitialized() {
  const accessTokenUsable = tokenIsUsable(
    clientState.accessToken,
    clientState.accessTokenExpiry,
  );
  const clientTokenUsable = tokenIsUsable(
    clientState.clientToken,
    clientState.clientTokenExpiry,
  );

  if (accessTokenUsable && clientTokenUsable) {
    clientState.initialized = true;
    return;
  }

  clientState.initialized = false;

  if (!clientState.deviceID || !clientState.clientVersion) {
    getSessionInfo();
  }
  if (!accessTokenUsable) {
    getAccessToken();
  }
  if (!clientTokenUsable) {
    getClientToken();
  }

  clientState.initialized = true;
  persistClientState();
}

function resetAuthState() {
  clientState.initialized = false;
  clientState.accessToken = null;
  clientState.accessTokenExpiry = 0;
  clientState.clientToken = null;
  clientState.clientTokenExpiry = 0;
  persistClientState();
}

function query(payload, allowRetry) {
  ensureInitialized();

  const response = http.post(
    "https://api-partner.spotify.com/pathfinder/v2/query",
    JSON.stringify(payload),
    {
      Authorization: "Bearer " + clientState.accessToken,
      "Client-Token": clientState.clientToken,
      "Spotify-App-Version": clientState.clientVersion,
      "Content-Type": "application/json",
      "User-Agent": utils.randomUserAgent(),
    },
  );

  if (!response || response.error) {
    throw new Error(
      "Query failed: " + (response ? response.error : "no response"),
    );
  }

  if (response.statusCode === 401 && allowRetry !== false) {
    resetAuthState();
    ensureInitialized();
    return query(payload, false);
  }

  if (response.statusCode !== 200) {
    throw new Error("Query failed: HTTP " + response.statusCode);
  }

  return JSON.parse(response.body);
}

function fetchArtist(artistID) {
  log.info("Fetching artist:", artistID);

  const overviewPayload = {
    variables: {
      uri: "spotify:artist:" + artistID,
      locale: "",
    },
    operationName: "queryArtistOverview",
    extensions: {
      persistedQuery: {
        version: 1,
        sha256Hash:
          "446130b4a0aa6522a686aafccddb0ae849165b5e0436fd802f96e0243617b5d8",
      },
    },
  };

  const overviewResponse = query(overviewPayload);
  const artistData = getNestedValue(overviewResponse, "data.artistUnion") || {};

  const allDiscographyItems = [];
  let offset = 0;
  const limit = 50;

  const topTracks = [];
  const topTracksData =
    getNestedValue(artistData, "discography.topTracks.items") || [];

  for (const item of topTracksData) {
    const trackData = item.track || {};
    if (!trackData.uri) continue;

    const trackID = trackData.id || spotifyIDFromURI(trackData.uri);

    const albumData = trackData.albumOfTrack || {};
    const albumName = albumData.name || "";
    const albumID = albumData.id || spotifyIDFromURI(albumData.uri);
    const albumURL = albumID ? "https://open.spotify.com/album/" + albumID : "";
    const coverURL = spotifyBestImage(albumData.coverArt);
    const durationMs =
      getNestedValue(trackData, "duration.totalMilliseconds") || 0;
    const trackArtists = spotifyArtistEntries(
      getNestedValue(trackData, "artists.items") || [],
    );
    const artistsString = uniqueMetadataValues(
      trackArtists.map(function (artist) {
        return artist.name;
      }),
    ).join(", ");
    const firstTrackArtist = trackArtists.length ? trackArtists[0] : {};
    const spotifyURL = "https://open.spotify.com/track/" + trackID;

    topTracks.push({
      id: trackID,
      name: trackData.name || "",
      artists: artistsString,
      album_name: albumName,
      album_artist: spotifyArtistNames(albumData.artists) || artistsString,
      album_id: albumID,
      album_url: albumURL,
      artist_id: firstTrackArtist.id || "",
      artist_url: firstTrackArtist.url || "",
      duration_ms: durationMs,
      images: coverURL,
      cover_url: coverURL,
      preview_url:
        getNestedValue(trackData, "previews.audioPreviews.items.0.url") || "",
      release_date: normalizeSpotifyDate(albumData.date),
      track_number: Number(trackData.trackNumber || 0),
      total_tracks: Number(getNestedValue(albumData, "tracks.totalCount") || 0),
      disc_number: Number(trackData.discNumber || 0),
      album_type: normalizeSpotifyAlbumType(
        albumData.albumType || albumData.type,
      ),
      external_urls: spotifyURL,
      external_links: { spotify: spotifyURL },
      copyright: spotifyCopyrightText(albumData.copyright),
      comment: albumURL,
      item_type: "track",
      provider_id: "spotify-web",
      spotify_id: trackID,
      isrc: "",
      explicit: isExplicitSpotify(trackData),
    });
  }

  while (true) {
    const discographyPayload = {
      variables: {
        uri: "spotify:artist:" + artistID,
        offset: offset,
        limit: limit,
        order: "DATE_DESC",
      },
      operationName: "queryArtistDiscographyAll",
      extensions: {
        persistedQuery: {
          version: 1,
          sha256Hash:
            "5e07d323febb57b4a56a42abbf781490e58764aa45feb6e3dc0591564fc56599",
        },
      },
    };

    try {
      const response = query(discographyPayload);
      const discographyData =
        getNestedValue(response, "data.artistUnion.discography.all") || {};
      const items = discographyData.items || [];

      if (items.length === 0) break;

      allDiscographyItems.push(...items);

      const totalCount = discographyData.totalCount || items.length;
      if (allDiscographyItems.length >= totalCount || items.length < limit) {
        break;
      }

      offset += limit;
    } catch (e) {
      log.debug("Discography fetch error:", e.message);
      break;
    }
  }

  const profile = artistData.profile || {};
  const stats = artistData.stats || {};
  const visuals = artistData.visuals || {};

  const artistInfo = {
    id: artistID,
    name: profile.name || "",
    images: spotifyBestImage(visuals.avatarImage),
    header: getNestedValue(visuals, "headerImage.sources.0.url") || "",
    followers: stats.followers || 0,
    listeners: stats.monthlyListeners || 0,
    biography: getNestedValue(profile, "biography.text") || "",
    verified: profile.verified || false,
  };

  const albums = [];
  for (const item of allDiscographyItems) {
    const releases = getNestedValue(item, "releases.items") || [];
    if (releases.length === 0) continue;

    const release = releases[0];
    let releaseID = "";
    if (release.uri) {
      const parts = release.uri.split(":");
      releaseID = parts[parts.length - 1];
    }

    const dateInfo = release.date || {};
    let releaseDate = dateInfo.isoString || "";
    if (releaseDate && releaseDate.includes("T")) {
      releaseDate = releaseDate.split("T")[0];
    }

    albums.push({
      id: releaseID,
      name: release.name || "",
      album_type: (release.type || "album").toLowerCase(),
      release_date: releaseDate,
      total_tracks: getNestedValue(release, "tracks.totalCount") || 0,
      artists: artistInfo.name,
      cover_url: spotifyBestImage(release.coverArt),
      external_urls: "https://open.spotify.com/album/" + releaseID,
      provider_id: "spotify-web",
    });
  }

  log.info("Fetched artist with", albums.length, "releases");

  return {
    type: "artist",
    artist: {
      id: artistInfo.id,
      name: artistInfo.name,
      image_url: artistInfo.images,
      header_image: artistInfo.header,
      listeners: artistInfo.listeners,
      albums: albums,
      top_tracks: topTracks,
      provider_id: "spotify-web",
    },
  };
}

function getNestedValue(obj, path) {
  if (!obj || !path) return undefined;

  const parts = path.split(".");
  let current = obj;

  for (const part of parts) {
    if (/^\d+$/.test(part)) {
      const index = parseInt(part, 10);
      if (!Array.isArray(current) || index >= current.length) {
        return undefined;
      }
      current = current[index];
    } else {
      if (
        current === null ||
        current === undefined ||
        typeof current !== "object"
      ) {
        return undefined;
      }
      current = current[part];
    }
  }

  return current;
}

function spotifyIDFromURI(uri) {
  const value = String(uri || "").trim();
  if (!value) return "";
  const parts = value.split(":");
  return parts[parts.length - 1] || "";
}

function normalizeSpotifyDate(dateValue) {
  let value = "";
  if (typeof dateValue === "string") {
    value = dateValue;
  } else if (dateValue && typeof dateValue === "object") {
    value = dateValue.isoString || "";
    if (!value && dateValue.year) {
      value = String(dateValue.year);
      if (dateValue.month) {
        value += "-" + String(dateValue.month).padStart(2, "0");
        if (dateValue.day) {
          value += "-" + String(dateValue.day).padStart(2, "0");
        }
      }
    }
  }
  if (value.indexOf("T") >= 0) value = value.split("T")[0];
  return value;
}

function uniqueMetadataValues(values) {
  const result = [];
  const seen = {};
  for (let i = 0; i < (values || []).length; i++) {
    const value = String(values[i] || "").trim();
    if (!value) continue;
    const key = value.toLowerCase();
    if (seen[key]) continue;
    seen[key] = true;
    result.push(value);
  }
  return result;
}

function spotifyArtistEntries(value) {
  const items = Array.isArray(value)
    ? value
    : getNestedValue(value, "items") || [];
  const artists = [];
  for (let i = 0; i < items.length; i++) {
    const item = (items[i] && (items[i].data || items[i])) || {};
    const name = getNestedValue(item, "profile.name") || item.name || "";
    const id = item.id || spotifyIDFromURI(item.uri);
    if (!name && !id) continue;
    artists.push({
      id: id,
      name: name,
      url:
        getNestedValue(item, "sharingInfo.shareUrl") ||
        (id ? "https://open.spotify.com/artist/" + id : ""),
    });
  }
  return artists;
}

function spotifyArtistNames(value) {
  return uniqueMetadataValues(
    spotifyArtistEntries(value).map(function (artist) {
      return artist.name;
    }),
  ).join(", ");
}

function spotifyBestImage(value) {
  if (!value) return "";
  let sources = Array.isArray(value) ? value : value.sources || [];
  if (!sources.length && value.items && value.items.length) {
    sources = (value.items[0] && value.items[0].sources) || [];
  }
  let best = null;
  let bestSize = -1;
  for (let i = 0; i < sources.length; i++) {
    const source = sources[i] || {};
    if (!source.url) continue;
    const width = Number(source.width || 0);
    const height = Number(source.height || 0);
    const size =
      width > 0 && height > 0 ? width * height : Math.max(width, height);
    if (!best || size > bestSize) {
      best = source;
      bestSize = size;
    }
  }
  return (best && spotifyMaxCoverURL(best.url)) || "";
}

function spotifyMaxCoverURL(value) {
  const url = String(value || "");
  if (!url) return "";
  if (url.indexOf(SPOTIFY_COVER_SIZE_300) !== -1) {
    return url.replace(SPOTIFY_COVER_SIZE_300, SPOTIFY_COVER_SIZE_MAX);
  }
  if (url.indexOf(SPOTIFY_COVER_SIZE_640) !== -1) {
    return url.replace(SPOTIFY_COVER_SIZE_640, SPOTIFY_COVER_SIZE_MAX);
  }
  return url;
}

function spotifyCopyrightText(value) {
  const items = Array.isArray(value)
    ? value
    : getNestedValue(value, "items") || [];
  return uniqueMetadataValues(
    items.map(function (item) {
      return (item && (item.text || item.value)) || "";
    }),
  ).join("; ");
}

function normalizeSpotifyAlbumType(value) {
  const type = String(value || "album")
    .trim()
    .toLowerCase();
  if (type === "ep") return "ep";
  if (type === "single") return "single";
  if (type === "compilation") return "compilation";
  if (type === "audiobook") return "audiobook";
  if (type === "podcast") return "podcast";
  return "album";
}

function isExplicitSpotify(obj) {
  if (!obj) return false;
  var label = getNestedValue(obj, "contentRating.label");
  if (typeof label === "string" && label.toUpperCase() === "EXPLICIT")
    return true;
  if (obj.explicit === true) return true;
  if (typeof obj.isExplicit === "boolean") return obj.isExplicit;
  return false;
}

function atob(str) {
  const chars =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=";
  let result = "";
  let i = 0;

  str = str.replace(/[^A-Za-z0-9+/=]/g, "");

  while (i < str.length) {
    const enc1 = chars.indexOf(str.charAt(i++));
    const enc2 = chars.indexOf(str.charAt(i++));
    const enc3 = chars.indexOf(str.charAt(i++));
    const enc4 = chars.indexOf(str.charAt(i++));

    const chr1 = (enc1 << 2) | (enc2 >> 4);
    const chr2 = ((enc2 & 15) << 4) | (enc3 >> 2);
    const chr3 = ((enc3 & 3) << 6) | enc4;

    result += String.fromCharCode(chr1);
    if (enc3 !== 64) result += String.fromCharCode(chr2);
    if (enc4 !== 64) result += String.fromCharCode(chr3);
  }

  return result;
}

function getArtist(artistId) {
  try {
    const result = fetchArtist(artistId);
    return result.artist;
  } catch (e) {
    log.error("getArtist failed:", e.message);
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
