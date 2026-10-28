# Online sources: one plan (artwork + lyrics + signed config)

Status: PROPOSAL. No code written. Waiting for the owner's OK and the answers in section 0.
Source prompt: `online-sources-prompt.md` (uploaded 2026-10-28). Upstream checked at Mornye v5.2.6
(`fb4945be`, blobs read with `git show`; the Mornye-Extension repo is not cloned here and will be
fetched in step 1).

## 0. Findings that change the brief, and decisions I need

| # | Finding | Decision needed |
|---|---------|-----------------|
| 1 | **There is no Ken Burns on album pages.** The only Ken Burns drift is `listening_rewind_screen.dart:1273`. Artist headers have none either, so there is nothing to remove. | Confirm I should ADD a slow Ken Burns to the album header (default, no network), ahead of the video work. |
| 2 | **The prompt's package names are the old ones.** `package:spotiflac_android` and `com.zarz.spotiflac` no longer exist after the Sistrum rename. | I use `package:sistrum` and `com.amwolfstein.sistrum`. Upstream attribution headers stay. |
| 3 | **AGENTS.md forbids this.** It says "do not reintroduce providers, downloads, extension credentials or remote artwork loading", "no other feature may use the network", and "Lyrics settings do not contain Embed lyrics or its output-mode submenu". | I need an owner override entry in AGENTS.md (like T16): opt-in online artwork and lyrics, off by default, behind explicit switches; the lyrics save-target setting is the one exception to the "no output-mode submenu" rule. Approve the wording in step 0. |
| 4 | **Upstream's HTTP crate cannot come over.** `mornye-network` is tokio + hyper + rustls + hickory (about 3k lines and about 20 crates). The offline cargo registry here has none of them, and `cargo test --offline` must keep working. | Plan below injects the transport instead (Kotlin `HttpURLConnection`, system TLS). Say if you prefer another approach. |
| 5 | **Ed25519 verification needs a crate.** The offline registries have no `ed25519-dalek` and no Dart Ed25519 package. `java.security` Ed25519 needs API 33; our minSdk is Flutter's default (24). | Step 1 first checks whether crates.io / pub.dev are reachable from this container. If yes: `ed25519-dalek` (Rust, tested with RFC 8032 vectors). If no: ask you before I write any crypto by hand. |
| 6 | **Config URL.** `raw.githubusercontent.com/AMWolfstein/Private/<branch>/config/...` returns 404 to the app while the repo is private, so config updates would never arrive until it is public. The app then silently keeps the bundled config (as designed). | Which branch is the stable constant? I suggest `main`. Is the repo going public before release? |
| 7 | **Video path (a) vs (b) cannot be proven here.** No Gradle wrapper and no device in this container; Media3 is not in any local cache. | I recommend (b), and add a spike gate before the UI work. Evidence in section 6. |
| 8 | **Third-party terms and privacy.** Apple's developer token is scraped from music.apple.com, and the proxy providers (paxsenix, zarz, KPOE) send title/artist to someone else's server. Both can disappear or change terms. | Opt-in and off by default, with a privacy note on each provider, as you specified. I am recording it here so it is your explicit call. |

## 1. Where each piece lives, and why

| Piece | Lives in | Why |
|-------|----------|-----|
| Provider logic: LRCLIB, Apple TTML, proxies, direct providers, TTML parser, Enhanced LRC writer, Apple token + API parsing, Deezer, matching and scoring | New crate `rust_backend/crates/online` (`sistrum-online`) | Pure, deterministic, unit-testable offline with recorded fixtures; reuses `core::lyrics` models |
| HTTP transport | Kotlin `PlatformHttpTransport` (`HttpURLConnection`), handed to Rust as a UniFFI foreign trait `HttpTransport` | System TLS and certificates, no new Rust dependencies, one place to enforce size caps, timeouts, HTTPS-only and the mobile-data rule |
| Motion video download + playback | Kotlin, next to Media3 (`MotionArtworkPlugin`) | Media3 is Android-only; keeps decoding off the Dart isolate |
| Coordinator (triggers, dedupe, concurrency 2, negative cache, retry), settings, UI, storage manifests, clear actions | Dart (`lib/services/online_sources/`) | Triggers come from playback and navigation, which already live in Dart |
| Config fetch + signature check | Dart fetch, Rust verify (`online::config`) | Keeps the verify code unit-testable; Dart only moves bytes |
| Config file, signing, upstream sync | `config/`, `scripts/`, `.github/workflows/` | As specified |

## 2. Exactly which upstream files return

From `rust_backend/crates/providers/src/lyrics/` (all MIT, upstream header kept):

| Upstream file | Fate |
|---------------|------|
| `lrclib.rs` | Ported (HTTP via the injected transport) |
| `builtin/apple.rs` | Ported (paxsenix/zarz TTML, word-synced) |
| `builtin/ttml.rs` | Ported; this is also where TTML to Enhanced LRC is built |
| `builtin/proxy.rs` | Ported (Spotify, Deezer, YouTube, Netease, Musixmatch via paxsenix; KPOE servers) |
| `builtin/direct.rs` | Ported (QQ Music, Kugou, Genius). `scraper`/`html5ever` are only pulled in if Genius needs HTML parsing; they are in the offline registry (0.27 / 0.39) |
| `service.rs` | Trimmed: provider order, per-call options, short in-flight dedupe. The persistent cache and negative TTL move to our manifest store |
| `http.rs` | Replaced by the `HttpTransport` trait |
| `cache.rs`, `calls.rs` (call graph for recursive extension calls) | Not ported |
| tests | Ported with their fixtures, rewritten against a fake transport |

Left out: the extension system, download providers, the provider registry, `mornye-network`, `desktop`, `extensions`. `httpdate` is dropped (only used for `Retry-After`; I parse the delta-seconds form myself).

From Mornye-Extension (LGPL-3.0, zarzet), read-only references translated into `online/src/artwork/apple.rs` and `deezer.rs`, which carry the LGPL-3.0 header and the zarzet NOTICE. I add a THIRD-PARTY note. Nothing is copied from Lokal.

## 3. Crate layout and bridge surface

```
crates/online/src/
  lib.rs            Transport trait, error type
  config.rs         schema structs, version rule, Ed25519 verify
  matching.rs       normalise, edition guard, Arabic folding, scoring
  lyrics/{lrclib,apple,ttml,proxy,direct,service,enhanced_lrc}.rs
  artwork/{apple_token,apple_api,motion_key,deezer}.rs
```

UniFFI additions in `crates/mobile` (blocking calls, cancellable through the existing `CancellationRegistry` ids, run on the existing data-jobs executor):
- `online_lyrics_fetch(request, providers, options, config_json, request_id) -> LyricsFetchResult`
- `online_artwork_resolve(kind, query, options, config_json, request_id) -> ArtworkResolveResult` (album motion URL, artist motion URL, static image URL, or negative)
- `online_ttml_to_enhanced_lrc(ttml) -> String`
- `online_verify_config(bytes, signature, public_key) -> ConfigVerdict`
- foreign trait `HttpTransport.request(HttpRequest) -> HttpResult` (implemented in Kotlin)

## 4. Triggers and deduplication

One `OnlineSourcesCoordinator` (Riverpod). Everything runs in the background and never awaits on the UI or playback path.

- **Key per item:** album key, artist key, track key (section 7). One in-flight map per key, so album open + playback of the same album collapse to one lookup.
- **Pool:** 2 concurrent lookups; extras queue (FIFO, newest-visible first).
- **Album motion:** first album page open, or first playback of any song from that album. **Artist motion + static image:** first artist page open. **Lyrics:** track starts playing, or the lyrics view opens for a track with no lyrics; prefetch of the next queued track (Wi-Fi only) if enabled.
- **Gate:** every lookup first checks its feature or provider switch and the "Download on mobile data" rule; if off, no request is made and nothing is queued.
- **Results:** positive, negative (retry after about 30 days, or via "Retry artwork" / "Search lyrics again"), or transient (marked, retried with backoff 1 h to 24 h, never saved as negative).
- **Off switch:** hides videos and stops lookups; nothing is deleted.

## 5. Matching rules and thresholds

- **Normalise:** lowercase, Unicode NFKC, strip punctuation, collapse spaces, drop `feat./ft.` tails, drop `remaster(ed) YYYY`, `edition`, `bonus track` suffixes. Arabic: remove tashkeel and tatweel, fold alef forms, `ى`/`ي`, `ة`/`ه`.
- **Editions never cross-match:** if exactly one side carries `deluxe`, `expanded`, `anniversary`, `(Taylor's Version)`, `live`, `acoustic`, `instrumental`, `karaoke`, `remix`, the candidate is rejected.
- **Score** = 0.40 title + 0.30 artist + 0.20 album + 0.10 duration (each 0..1, token-set similarity for text).
  - Lyrics: accept at score >= 0.85; reject when duration differs by more than 3 s (unless the provider reports none); prefer synced over plain, then word-synced if "Prefer word-synced" is on.
  - Album artwork: the album title must match exactly after normalisation, the artist must match, and track count within 20 % when both sides know it; accept at >= 0.90.
  - Artist: normalised name must match exactly and the result must have artwork; accept at >= 0.90. Deezer's empty-hash placeholder silhouette is "not found".
- **Arabic and Latin:** search with the Arabic form in storefronts `eg`, `ae`, `sa`, then `us`. A Latin result is accepted for an Arabic file only if the candidate also lists the Arabic form (or the file's Latin form equals the candidate's). No transliteration guessing. Below threshold: save a negative result, never a "best effort".

## 6. Video save path, (a) Transformer remux vs (b) DownloadManager

| | (a) Transformer remux HLS to one MP4, play with `video_player` | (b) Media3 `DownloadManager` + `SimpleCache`, play with our own ExoPlayer texture |
|---|---|---|
| Resume after kill | Not natively; a killed remux restarts | Built in (HLS downloader tracks segments) |
| Resolution cap | Hard to steer variants in Transformer | `DownloadHelper` track selection by height (<= 1080) |
| Re-encode risk | Transformer may transcode instead of transmux depending on the stream, costing time and battery | None; bytes are saved as served |
| Dependencies | Transformer + `video_player_android` (cached 2.10.0) | `media3-exoplayer`, `-exoplayer-hls`, `-datasource`, `-database`; no `video_player` |
| Playback control | `video_player` cannot disable audio focus or choose one decoder per header without patching | We own it: muted, looping, `handleAudioFocus=false`, one player per visible header |
| Offline play | File on disk | `CacheDataSource` only (no network), `SimpleCache` in app files |

**Recommendation: (b).** It resumes, caps resolution and plays with no audio focus. Cost: about 300 lines of Kotlin plus a texture bridge. **Spike gate:** step 6 starts with a minimal download + offline playback of one real Apple loop on your phone; I stop and report before building the UI if it does not play reliably. I cannot run this here, so this is a recommendation, not evidence.

Display: crossfade from the still/Ken Burns to the video when ready; pause when collapsed, off-screen, backgrounded, reduce-motion, `glassQuality` off, or a low-end device; header glass keeps using a still frame as its ground (saved next to the video) so there is no per-frame ground rebuild.

## 7. Storage layout and clear actions

App files storage (not cache dir): `<filesDir>/online/`.

```
online/artwork/album/<albumId>/{manifest.json, motion/ (SimpleCache), still.jpg}
online/artwork/artist/<artistId>/{manifest.json, motion/, still.jpg, image.jpg}
online/lyrics/<trackId>/{manifest.json, lyrics.lrc | lyrics.ttml}
```

- **ids:** album = SHA-1 of the normalised `album|albumArtist` (the library's existing `albumKey`), artist = SHA-1 of the normalised name, track = the library item's stable key. I confirm in step 3 that a rescan or tag edit keeps these; if a tag edit changes the key, it follows the existing key rules (the prompt's "as long as the id stays the same").
- **manifest.json:** `source`, `sourceId`, `type`, `fetchedAt`, `sizes`, `result` (`positive` / `negative` / `transient`), `retryAfter`, `configVersion`.
- **Deleted only by:** "Clear online artwork", "Clear online lyrics", Cache management's Clear cache (with the two sizes shown), uninstall. `native_cache_maintenance` and the cache page get two new rows.
- **Backup/restore:** the toggles, provider order and options only; no media, no lyrics.

## 8. Lyrics lookup order, save-to-file

Order per track: embedded, then sidecar `.lrc`/`.ttml` (today's `core::lyrics`), then our saved copy, then the enabled providers in order. Online is never reached if one of the first three returned lyrics.

Save to file ("Save lyrics to file" in the lyrics options menu, "Save automatically" off by default, target: Embed / `.lrc` next to file / Both):
- **Embed** only through the existing tag-writing path (`metadata_persistence_service` and the Rust `tags::write` lyrics field, ID3 via `id3v23_lyrics`). Unsupported formats are skipped with a clear message.
- **Sidecar:** SAF helper in `MainActivitySafIo` (temp file then swap, like the metadata editor).
- **Word-synced:** Enhanced LRC (`[mm:ss.xx]` line stamps plus inline `<mm:ss.xx>` word stamps) built by `enhanced_lrc.rs` from the TTML model; the TTML stays in app storage.
- **Never overwrite** existing embedded lyrics or an existing `.lrc` without a confirmation dialog; on a read-only folder or SAF denial, keep the app copy and say why.

## 9. Config schema, extractor, workflows

- `config/online_sources.json` (data only, no code) with `version` (integer, must increase), `apple` (token page, token regexes, bundle search patterns, API base, headers, storefronts, motion key priority for albums and artists, URL templates), `deezer` (API base, placeholder markers), `lyrics` (LRCLIB, proxy hosts, KPOE servers, direct endpoints, default provider order, default enabled set = LRCLIB only). `config/online_sources.schema.json` validates it; `docs/online-sources-config.md` documents every field.
- `scripts/extract_online_sources.py`: reads Mornye-Extension `sources/apple-music/index.js`, `sources/deezer/index.js` and Mornye `providers/src/lyrics/**`; writes the JSON with a `// source file:line` note per value in a sidecar `config/online_sources.provenance.json`; fails loudly (non-zero) when upstream's structure no longer parses. Tested against pinned upstream fixtures (committed).
- App: bundled copy (a test asserts it equals the repo file); daily fetch only while a feature is on; verify the signature with the embedded public key; ignore older versions; keep last good or bundled on any failure.
- `scripts/sign_config.py` (Ed25519 PEM), `*.key` added to `.gitignore`, a clearly marked **test key** until you send the public key (the swap location is one constant, `kOnlineSourcesPublicKey`).
- `.github/workflows/sign-config.yml`: on pushes touching the JSON; schema check, `version` increased, sign with secret `SISTRUM_CONFIG_SIGNING_KEY`, commit the `.sig` with `[skip ci]`, `contents: write` only, pinned action SHAs, key never printed, clear failure when the secret is missing. Docs: how to add the secret.
- `.github/workflows/sync-online-sources.yml` (daily cron + manual): clone latest Mornye-Extension and Mornye, run the extractor, smoke-test the NEW values live (token regex finds a token, a known album returns `editorialVideo`, LRCLIB answers, each enabled proxy answers), open a PR with diff, upstream commit links and smoke results; open an issue instead if the extractor cannot parse upstream; separate daily smoke test of the CURRENT config that opens/updates one issue and closes it on recovery; `AUTO_MERGE_ONLINE_SOURCES=true` (off by default) auto-merges only when schema and smoke both pass.
- **Not testable here:** the workflows themselves cannot run in this container; I validate YAML syntax and run the scripts locally against fixtures, and say so.

## 10. Expected storage

| Item | Typical size |
|------|--------------|
| Album motion loop (<= 1080 tall, 3 to 10 s) | 2 to 6 MB (+ a ~150 KB still) |
| Artist motion loop | 2 to 6 MB (+ still) |
| Artist static image | 100 to 300 KB |
| Lyrics (LRC / TTML) | 3 to 10 KB / 20 to 80 KB |
| Manifest | < 1 KB |

A 500-album library with every album and artist fetched is about 2 to 4 GB, so the Cache management page shows the totals and the clear actions are prominent. There is no automatic eviction (you said: kept forever).

## 11. Order of work, with commits

Every step follows AGENTS.md: code, then graphify, then docs; one analyze + one full test per step; `scripts/check_rust_backend.sh` for Rust steps; `scripts/check_android.sh` for Kotlin steps (cannot run here, so those are yours).

0. **Prereqs:** AGENTS.md override, crates/pub reachability check, your answers to section 0.
1. **Config + tooling** (no app code): schema, extractor, sign script, both workflows, docs, pinned fixtures, signature tests.
2. **Rust `online` crate (lyrics):** matching, ported providers, TTML, Enhanced LRC, config verify; fake-transport tests with recorded fixtures.
3. **Dart foundation:** settings and backup keys, coordinator, manifests, storage, clear actions, Cache management rows, Kotlin `PlatformHttpTransport`, mobile-data gate.
4. **Online lyrics UI + save-to-file:** Settings > Lyrics > Online lyrics, provider list (toggles + drag), lookup order, "Search lyrics again", save/embed/sidecar with overwrite confirmation.
5. **Artwork lookups (Apple, Deezer):** token extraction, motion key priority, placeholder handling, negative cache; Ken Burns on albums (finding 1).
6. **Motion video:** spike gate on your phone, then `MotionArtworkPlugin`, album/artist header integration, pause rules, still-frame ground.
7. **Tests and docs:** remaining tests from the prompt's list, `docs/online-sources-config.md`, THIRD-PARTY note, manual phone test list, AGENTS.md and migration plan progress.

## 12. Tests (no network, recorded fixtures)

Defaults (Ken Burns on albums only; no requests when off); triggers fire once plus prefetch; negative caching and retry; persistence across rescans and deletion only via clear actions; lookup order (local beats online); duration rejection; Arabic/Latin and edition matching; Apple token extraction from a saved page and bundle; motion key priority; Deezer placeholder; TTML to Enhanced LRC; embed and sidecar writes including a read-only folder and the overwrite confirmation; config signature (good, tampered, missing); extractor against pinned upstream fixtures. A manual phone checklist ships with step 7.
