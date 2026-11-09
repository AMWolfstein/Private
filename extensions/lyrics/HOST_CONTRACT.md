# Draft native host boundary (not installed)

The current application does not expose this interface. The source ports require
a future trusted adapter; the following documents the complete dependency rather
than implying that existing generic extension APIs already provide it.

## Factory and lifecycle

`createProvider(id, host)` returns an isolated provider instance. The instance exposes
an asynchronous `fetchLyrics(request)` and rejects concurrent calls on itself.
Separate instances can be scheduled by the native lyrics service. The host must bind
an operation-scoped cancellation check and serialize each provider VM. Native service
caches, negative caching, priority grace, request coalescing, rate-limit cooldowns and
shutdown ownership are not reimplemented in JavaScript.

Request fields: `track`, `artist`, `album`, `duration` (seconds), `spotify_id`, and
`options`. Option names match Rust `FetchOptions`: `include_translation_netease`,
`include_romanization_netease`, `multi_person_word_by_word`, `apple_elrc_word_sync`,
`musixmatch_language`. Defaults are copied from the pinned native implementation.
The current native `SearchRequest` does not use album in built-in lookups; the port
accepts it for future ABI completeness without adding album filters to old requests.

## Host methods

- `check()`: synchronously throw when the caller is cancelled or the owner closed.
  Every awaited network/core/resolver operation is checked before and after.
- `request({url, headers, timeoutMs, maxBytes, allowedStatuses, unavailableErrors})`:
  perform a cancellable GET and return `{status, body}` with decoded UTF-8 text.
  Enforce host-owned network permissions, DNS/private-address policy, redirect
  checks, connection and body timeouts, decoded-body size and VM-memory limits.
  Non-200 explicitly allowed statuses must return without consuming a stalled body,
  matching native `LyricsHttp`; the JS size check alone is not a memory guard.
  Do not let downloaded source code expand its own host permissions.
- `resolveDeezerId(spotifyId)`: the existing cross-platform ID resolver, restricted
  to the Deezer lyrics path. It must preserve its own cancellation and network
  policy. This is not permission to restore a public cross-service sharing feature.
- `core`: pure/bounded native helper methods below. They must not dispatch another
  lyrics-provider search or reenter the same provider VM.

All host failures must use errors with `kind`: `not_found`, `unavailable`, `other`,
`cancelled` or `recursive`. Do not log tokens or raw authenticated request headers.
Per-request timeout support must accommodate Zarz-LRC's 65 seconds; overall VM/job
deadlines are separate and must account for its preceding token/catalog lookups.
The current installed-provider path's 30-second timeout is not sufficient.

`source.json` lists expected service hosts for review. The native Deezer resolver
has additional dependencies not covered by the proxy's host list. The future host
must explicitly decide and enforce these permissions, including response-supplied
Genius page URLs and redirect destinations.

## Native core helpers

| Methods | Existing native logic to retain/adapt |
| --- | --- |
| `primaryArtist`, `simplifyTrack`, `normalizeTitle`, `normalizeLooseArtist`, `titlesMatch`, `artistsMatch`, `durationMatches`, `artistInTitle`, `score`, `clockDuration` | `mornye_core::lyrics::matching` |
| `decode(kind, raw, complete)` | Existing typed HTTP/document decoders and their schema defaults, aliases, integer fidelity, UTF-8/surrogate and error handling |
| `selectLrclib`, `lrclibResponse` | Native recording-aware LRCLIB selection and conversion |
| `fromText`, `parseProxy` | `LyricsResponse::from_text`, native proxy payload parsing |
| `ttmlLyrics`, `formatKpoe`, `formatApple`, `formatZarzApple`, `appleSupplements` | Native payload/TTML formatting and supplemental fields |
| `base64Text`, `geniusText` | Native-compatible base64 handling and bounded HTML extraction |

`decode` kinds are: `lrclib`, `lrclib_list`, `spotify_list`, `youtube_list`,
`netease_search`, `netease_lyrics`, `apple_search`, `qq_search`, `qq_detail`,
`qq_lyrics`, `kugou_search`, `kugou_lyrics`, `genius_search`, `kpoe`,
`lrc_red_search`, `better_lyrics`. Results use the pinned Rust model's field names
(e.g. `song_count`, `artist_name`, `duration_in_millis`, `kind`), not a second
independent JSON interpretation with different defaults. ID values used as strings
must not lose precision through JavaScript Number. `complete=false` means streaming
first-JSON-value decoding, matching the existing native response decoder.

Formatting functions return text except `fromText`, `parseProxy`, `ttmlLyrics`,
`lrclibResponse` and `appleSupplements`, which return the native `LyricsResponse`
shape. `selectLrclib` returns a selected normalized row or null. `appleSupplements`
returns a response retaining translations/romanization rather than mutating a
cross-boundary object in place. Preserve `lines`, `syncType`, `instrumental`,
`plainLyrics`, `provider`, `source`, and all supported per-line supplementary fields.
The old extension result normalizer currently drops some of those fields; it must
be adapted and tested before these sources are connected.

Native base64/HTML helpers currently internal to providers may need safe host
exports. No Rust implementation or exported signature is changed by this source
addition. Native helpers changing later can still require an APK update; service
routing and provider-specific request logic can be updated independently once the
source loader and signed distribution mechanism are implemented.
