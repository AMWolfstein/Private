# Rust JSON provider migration design

## Current system
BuiltinLyricsClient in rust_backend/crates/providers/src/lyrics/builtin.rs dispatches 14 native implementations. LyricsHttp in lyrics/http.rs owns shared cancellable native network requests; LRCLIB uses its own client. Backend constructs the client in rust_backend/crates/extensions/src/backend.rs. extensions/lyrics/ contains inactive CommonJS ports; extensions/sources/ contains inactive upstream artwork subsets. No host exists for these copies.

## Design
- Ownership: mornye-providers owns validated immutable configuration snapshots. Configuration files live under extensions/config/. Rust remains the sole executor. Backend owns configuration persistence and publication.
- Native request adapters read named endpoint settings; existing parsing, matching, caching and cancellation stay native. Test/deployment endpoint overrides remain separate and authoritative.
- Versioned JSON rejects unknown keys, executable expressions, credentials and unsafe URLs. Each configurable endpoint has a compiled capability identity and constrained HTTPS destinations. Parameters/path placeholders are encoded by native code, never arbitrary string evaluation.
- Updates: validate a whole candidate before an atomic same-directory persistence operation, then activate only at next Backend initialization. Readers retain one snapshot throughout the backend lifetime. Bundled defaults survive missing/corrupt cache. Authenticate downloaded settings before installation; do not provision pretend production signing keys or silently download untrusted content.
- Artwork ports require source-specific native request/authentication/parsing and fixtures. Do not label source inventories or empty adapters as completed ports. Keep source references until parity is established. Reuse existing metadata response shapes where applicable.
- Contracts: preserve existing lyric and metadata APIs. Any new callable boundary needs caller/native tests before activation. Song IDs, library database, backups and user provider settings are unchanged.
- Lifecycle: cancellation propagates through existing network sessions. No unowned background worker or new startup network request.
- Failure: typed configuration errors; failed validation or persistence leaves prior state active. Unsupported authentication remains an explicit error.
- Removal: inactive JS ports are removed only after native equivalence checks. Native built-in lyrics are retained.

## Decisions
- PD-1: Native execution plus bounded JSON follows the owner's explicit choice. No WASM or downloaded native code.
- PD-2: Do not represent arbitrary provider algorithms as JSON. Changes outside the documented schema need an APK.
- PD-3: Keep deployment trust setup explicit; no generated private key is committed.

## Constitution check
- [x] I. Owner scope and Jellyfin exclusion retained.
- [x] II. Test evidence distinguished from device/live-provider evidence.
- [x] III. Preserve current native implementations and dependencies where possible.
- [x] IV. Characterization, rejection and persistence tests before activation.
- [x] V. Typed failures; misses and cancellations preserved.
- [x] VI. Immutable snapshots and explicit owner lifecycle.
- [x] VII. Atomic persistence and unchanged IDs/preferences.
- [x] VIII. Independent design and final code review required.
- [x] IX. No general-purpose configuration interpreter.
- [x] X. Explicit-path commits and authorized branch push only.

## Verification plan
Rust provider tests, configuration tests, existing artwork fixtures adapted for Rust, bridge tests where changed, Flutter analyze/tests, Android unit/build where native integration changes. Final work.py check auto; physical-device behavior remains unverified without hardware evidence.

## Complexity tracking
No approved deviations. Missing credentials/trust configuration must be reported rather than fabricated.

## Open choices
None needed for native configuration groundwork. Deployment credentials/trust material remain operator-owned.

## Review clarifications
The first implementation batch is native lyrics configuration, not a completed artwork migration. Remaining artwork ports are a required later batch, not removed from scope. Never delete inactive source references or claim all work completed on the strength of this batch.

### Configuration v1 (lyrics groundwork)
A JSON document has exactly schema_version=1, revision (positive u64), runtime_version=1, and lyrics_origins (complete map of 12 request origins to origin-only HTTPS replacements). Maximum document 64 KiB; duplicate keys and unknown keys rejected. URLs must have no credentials, path except /, query, fragment, non-443 ports or private/IP/local hosts. Destinations remain on the compiled public service allowlist; adding a new domain requires APK review. This batch exposes origin replacement only, not path/header/parser overrides; that limitation is documented explicitly. Identity values preserve all existing requests. Actual path/header expansion is a separate reviewed schema change.
Origins: lrclib.net, lyrics.paxsenix.org, lyricsplus.prjktla.my.id, lyricsplus.binimum.org, beta.music.apple.com, amp-api.music.apple.com, api.zarz.moe, c.y.qq.com, lyrics.kugou.com, genius.com, lrc.red, lyrics-api.boidu.dev (all https). Header-only music.apple.com and y.qq.com are not request routes. Shared origins serve several provider IDs; all 14 IDs remain available.

### Authentication, persistence and activation
Envelope fields: format=1, key_id, payload (base64 exact JSON UTF-8 bytes), signature (base64 Ed25519 signature). Verify exact bytes against an app-bundled trusted key map, never a key inside downloaded data. Empty production key map means remote installation is disabled; do not invent operator identity. Operator owns private keys outside Git. Native install API verifies signatures, validates schema/URLs and revision, writes complete envelope via tempfile+sync+atomic persist in backend-owned data directory. Store .provider_config.json. Reject downgrade revisions, including on startup relative to bundled revision. Tampered/corrupt/unknown-key caches fall back to bundled defaults with explicit load diagnostics. Keys are bundled under extensions/config/trusted-keys.json. The owner selected their own repository: AMWolfstein/Private, extensions/ on extension-system. GitHub reports it as public. No downloader is wired yet; private GitHub tokens must never be embedded into the APK.
Activation is deliberately next Backend initialization (restart), not hot swap. Existing readers, token caches, positive/negative caches and coalesced jobs retain one configuration generation throughout backend lifetime. On startup with a new generation, do not restore prior generation's lyrics cache: include revision in the native persistence filename. No old worker writes the new generation's file. Update installation never clears a cache while requests are in flight. No cross-language installer interface is introduced in this batch; define/test it before runtime update activation.

### Required artwork inventory (later batch)
All 13 imported providers remain in scope: amazon, apple-music, beatport, bugs-music, deezer, genie-music, jiosaavn, melon-music, qobuz-web, soundcloud, spotify-web, tidal-web, ytmusic-spotiflac. Each needs native artist identity and still image/header fields. Apple additionally needs album artwork, artist/album motion, logos and editorial description fields. Inputs remain source resource IDs, with local-library identity resolution as an explicit integration dependency. Credential/session requirements are retained exactly as recorded by source.json; do not invent anonymous availability. Completion requires request/authentication fixtures and expected output from the pinned JS reference for each supported operation, plus a real native caller. Current reference sources are about 10k lines and are not considered ported by this configuration batch. Missing parity fixtures block removal, not preservation.
