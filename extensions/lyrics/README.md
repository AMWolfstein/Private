# Staged ports of the native lyrics providers

This directory contains JavaScript/CommonJS source ports of all 14 built-in Rust
lyrics providers. **The Rust originals are retained unchanged and remain the active
implementation.** Nothing here is installed, bundled into Flutter, registered with
the current loader, or invoked by the application. Jellyfin is not included.

## Sources

| Provider IDs | Native source | Ported behavior |
| --- | --- | --- |
| `lrclib` | `providers/src/lyrics/lrclib.rs` | Exact metadata attempts, primary/full artist and simplified title attempts, recording-aware search selection, instrumental results |
| `spotify`, `deezer`, `youtube` | `builtin/proxy.rs` | Identifier validation, search/matching, resolver dependency and proxy retrieval |
| `netease`, `musixmatch` | `builtin/proxy.rs` | Search, optional translation/romanization and translation-to-word-lyrics fallback |
| `lyricsplus` | `builtin/proxy.rs` | Primary/secondary endpoints, request formatting and native KPOE formatting |
| `apple_music`, `mornye_lyrics` | `builtin/apple.rs` | Catalog token discovery/refresh, recording selection, separate Paxsenix/Zarz-LRC endpoints, native supplementary timing/translation data |
| `qqmusic`, `kugou`, `genius` | `builtin/direct.rs` | Candidate selection, QQ duration checks, base64 and bounded HTML parsing dependencies |
| `lrcred`, `betterlyrics` | `builtin/ttml.rs` | Full-artist/version matching, validated ISRC document paths and native TTML parsing |

Native paths above are relative to `rust_backend/crates/`; the exact paths,
source commit and SHA-256 hashes are in `origin-lock.json`. Original Rust cache,
provider-order service, pure matching/parsers, local file reads/writes and native
cancellation remain native. This is a staged port, not a completed runtime migration.

## Layout and use in tests

Each `sources/<id>/provider.cjs` exports a factory accepting the draft host described
in `HOST_CONTRACT.md`. It returns `{id, fetchLyrics(request)}`. All provider network
routing is implemented in `shared/providers.cjs`; common error/transport handling
is in `shared/runtime.cjs`. No factory calls the original built-in lyrics fetcher.

```js
const makeProvider = require('./sources/lrclib/provider.cjs');
const provider = makeProvider(host);
const result = await provider.fetchLyrics({
  track: 'Song', artist: 'Artist', album: 'Album', duration: 180,
  spotify_id: '', options: {},
});
```

This example requires an implemented trusted host. `host` is not supplied by the
current application. CommonJS and async calls need a future bundle/loader adapter;
these files are not directly compatible with today's four-positional-argument
`fetchLyrics` extension ABI. `source.json` is documentation, not an install manifest.

Run offline checks from the application repository root:

```sh
node --test extensions/lyrics/tests/*.test.cjs
```

The tests exercise every provider's request flow using fixture HTTP responses and
stubbed native helpers. They cover fallback order, cancellation, request limits,
source-ID handling, word/translation options and retention of the original Rust
files. They do **not** prove parser/matching equivalence, live service availability,
subscription/session flows, current QuickJS compatibility or Android behavior.

Before activation, implement the host adapter and compare Rust versus these ports
with the same fixture bytes and the real native matching/parsers. Compare success,
missing/outage/cancellation classifications, returned words/timing/supplements and
request sequence. Do not delete originals or switch provider preferences before
those comparisons pass. Source signing, update packaging and rollback are separate
future tasks; this import does not implement them.

The Apple proxy ports deliberately remain distinct from the previously imported
`extensions/sources/apple-music/index.js` subscription-based provider. These ports
retain the native endpoint/authentication paths instead of introducing its user-token
requirement. Per-instance JavaScript token caching is included, but cross-provider
native token coalescing still requires design/validation in the host integration.
