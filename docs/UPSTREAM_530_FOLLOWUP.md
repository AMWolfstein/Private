# Local/offline v5.3.0 follow-up

Reference upstream tag: `afee4332a257f1b6aeb288229eddf04ac0777b3c`.
This follows the earlier local playback and Android Auto batches on the current
Flutter/audioplayers engine. It does not depend on the planned Kotlin/Media3
migration. The comparison below covers the requested feature/performance areas;
it is not a claim that all 453 upstream commits since the older v5.2.6 checkpoint
were individually audited or merged.

## Advanced acoustic Autoplay

`Playback > Match the sound` stays optional and off by default. A refill's
existing bounded background scheduler analyzes at most nine local tracks,
sequentially, rather than sweeping/decoding the whole library. It uses one or
two 24-second mono 22,050 Hz s16le windows near 30% and 60% of a known-duration
song; short songs use one central window, unknown durations try 30 and 90
seconds. Decoder jobs retain one thread and their existing 20-second per-window
cancellation deadline. Queue reset, opt-out and disposal retire results and
cancel both FFmpeg and native analysis. SAF descriptors remain owned until
analysis cleanup; temporary PCM is deleted in `finally`.

The existing native data-job bridge now accepts `audio_features`; it reads at
most two bounded regular PCM files, checks cancellation throughout analysis,
and returns 42 finite features. No decoded audio is serialized through the
Dart/native message codec. The descriptor contains:

- 13 MFCC means and spreads, spectral brightness/rolloff/flatness and band shares;
- energy/loudness, onset density and spectral flux;
- tempo with confidence and octave-aware comparison;
- chroma-based tonic/mode with key strength.

Adapted upstream matching standardizes the candidate/session feature space with
prior scales, uses recent-session timbre similarity and evaluates tempo/energy
continuity and compatible keys against each preceding pick. Duplicate exclusion,
recency penalties and artist diversity remain active. Missing features receive
the mean known score rather than being treated as bad songs. Low-confidence
tempo/key does not create a confident transition claim. The model is DSP, not
semantic genre recognition, and key/tempo estimates can be ambiguous.

Cache `autoplay_sound_v2` stores at most 512 small descriptors and rejects stale
size/mtime identities, invalid layouts and nonfinite/overflowing data. Legacy
six-value v1 summaries are not reused; they are disposable caches, not user
preferences. Saved sound-match preference and existing learning model survive.
No full-library sweep, charging-policy UI or remote analysis is added.

## Compared changes and decisions

| Area / upstream source | Decision and local evidence |
|---|---|
| MFCC/tempo/key extraction and matching: `song_features.dart`, `native_audio_features.rs`, `autoplay_sound_signal.dart` | Adapted to existing AutoMix decoding/cancellation and native data jobs. New Rust numerical tests and Dart signal tests retained. No engine replacement or new Cargo dependency. |
| In-place collection ordering: `b12f0399` | Added Reorder songs / Done in Loved and playlist headers. Drag handles operate on stable occurrence keys. Persistence validates complete current membership transactionally, updates timestamps in bounded batches and preserves track metadata. Playlist ASC / Loved DESC and new-like-first contracts survive backups/browser reads. No Wishlist or Link code. |
| Session encoding: `4de2cff4`, `08c4f6d7`, `e954e847` | Existing `PlaybackSessionWriter` already serializes the queue only on revision changes; scalar position writes stay fixed-size. Large snapshots now encode on a worker; large saved JSON parses on a worker. The upstream preference 512 KB limit does not apply to our SQLite storage. No second persistence format introduced. |
| Session position filtering: `4823a141` | Added Android platform wrapper with 500 ms extrapolation tolerance. App listeners still receive every state; changed controls, queue index, errors, speed, buffering and real seeks are forwarded. Failed sends reset filter state; media-item publication and stop are forwarded. |
| Queue publication: `4eaa5eff` | Vendored audio_service sends an idle change immediately, retains only the newest pending queue while a send is in flight, and retries publication after failure. Android still receives the full queue; existing item/state ordering is tested. |
| Listening flushes: `3e2f5d66`, `929c8886` | Timer runs only with active/pending work. Idleness includes queued writes that may fail and return time; failed writes remain retryable. Disposal and the existing ten-second checkpoint cadence remain. |
| FFmpeg startup/callback order: `fde03233`, `71c7de52` | Vendor same locked 2.5.7 package with deferred executor loading, ordered main-loop replies and synchronized native callback registration. Existing audio AAR and API retained. No download finalizer exists in target. |
| Large imported fonts: `668a850b` | Validate/hash on worker; restored font reads also run there. IDs, size bounds and missing/corrupt font fallback remain unchanged. |
| Initial platform calls / orientation: `65a50d87`, `9b4fdabc`, `4e90afa2` | Existing main already overlaps orientation with initialization. Initial orientation errors now have an immediate logged handler. Installation preparation remains single-flight; target has no download-library SAF grant validation step to transplant. |
| Android route facts: `ad2820cc` | Bluetooth/LE/hearing-aid routes report negotiated codec format as unreported and label PCM properties as system defaults; no fabricated output rate/depth or resampling. Sheet refreshes route on resume. USB direct-output facts retain precedence. |
| Direct-build About revision: `22a2abac` | Android Gradle supplies existing GIT_COMMIT define through a tested shell helper. Explicit defines and source archives remain supported. No iOS/CI/package changes transplanted. |
| Setup: `afee4332`, `d6daf454` | Added native SDK probe with device_info fallback, isolating probe failure from setup initialization. Target intentionally uses SAF folder selection from Android 10; replacing that with broad all-files permission is inappropriate. Nearby-device permission for upstream LAN/Link is excluded. |
| Cover provider/bitmap safety: `7db48420`, `9019e853`, `22e3536d`, `f2cf97a3` | Already adapted in the preceding Android Auto batch: opened-descriptor validation/finally cleanup, independent bitmap ownership and bounded recent decoded art. Preserved. |
| Cover index/cache batching: `01700972`, `0ddb26c5`, `37c81d2c`, `37d9a6c2` | Upstream optimizes its network JsonCacheInfoRepository. Target local covers use EmbeddedCoverResolver's source-versioned sidecars, coalesced validation, bounded LRU/scheduler and file/byte eviction; it does not use that network index. Do not introduce it or claim equal benchmark results. |
| Download-history lookup/rebuilds: `b336075b`, `3332de22`, `09437e55`, `0331d5ec`, `f5e48193` | Download-history/shadowing source is absent from the local-only target. Existing bounded SQL browse/search and LibraryTracksFolderData snapshot reuse are retained. No downloaded-history model rebuilt for parity. |
| Apple Now Playing artwork: `81430eb5`; desktop timers/SMTC; Material settled blur/system palette | Different platforms/renderers. Target retains Sistrum's shared chrome and pre-blurred artwork grounds. No platform/renderer transplant. |
| Link, NAS, WebDAV, providers, downloads, online lyrics/translations, release tour | Outside local/offline Android scope; excluded. Existing app updater is preserved. |

## Verification and limits

Source checkpoint: `bad86c09`. Verification on 2026-11-01:

- Full `flutter test --reporter expanded`: **2,377 passed, 3 skipped, 0 failures** (5m47s).
- `flutter analyze`: **No issues found**.
- `bash scripts/check_rust_backend.sh`: formatting/Clippy clean, **207 passed, 1 ignored** across the workspace.
- Android JVM: app **93 passed, 1 skipped**, audio_service **11 passed**, FFmpegKit **3 passed**. Rust Android libraries and Kotlin/Java compile through the unit task.
- `python3 scripts/test_flutter_git_commit.py`: **6 passed**; shell syntax check clean.

Graph checkpoint `d0c4a8a3`: **28,671 unique nodes / 54,836 valid links**, no dangling endpoints. Existing partial extraction warnings in vendored libusb sources remain.

No device test was executed. Android unit tasks package library resources, not an APK.

Numerical tests use synthetic clicks, triads, tones, noise and silence; these
establish signal behavior, not real-library perceptual recommendation quality.
JVM FFmpeg tests use Android stand-ins. Device CPU/battery cost, startup gains,
Bluetooth/OEM behavior, audible gapless continuity and Android Auto/DHU remain
unmeasured here. No APK is packaged or installed. No upstream benchmark number
is presented as a measurement of this fork.

Adapted acoustic, media-filter and test code retains LGPL-3.0-only notices and
in-app terms in `assets/licenses/autoplay_learning.txt`. Existing vendor licenses
are retained. No Rust/C++ implementation, FFmpeg codec package or audio engine
is replaced. Direct Dart dependencies now explicitly name already-resolved
platform/test interfaces; no package version upgrade is part of this batch.
