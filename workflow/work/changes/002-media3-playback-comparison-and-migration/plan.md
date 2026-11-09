# Plan 002: Media3 playback comparison and migration

## Summary

This batch delivers a source-backed comparison and draft staged roadmap in
[MEDIA3_EXOPLAYER_MIGRATION_PLAN.md](../../../../MEDIA3_EXOPLAYER_MIGRATION_PLAN.md).
It imports no implementation. The source is reusable but requires adaptation of
storage, service/bridge ownership, target AutoMix, output routes and application APIs.
The future batches follow the target guide's E01–E12 order rather than starting a
simultaneous engine and backend rewrite.

## Current system

Target baseline: `933e0bd6fbc00899372a815a74ab6fffc3a5fe73`.

- `lib/services/music_player_service.dart:127` owns transport/queue coordination;
  `music_player_automix.dart:446` creates phase-lock behavior during transitions.
- `lib/services/music_playback_deck.dart:148` adapts the patched audioplayers player;
  `:188` defines its existing USB channel. The Android ordinary wrapper uses
  `android.media.MediaPlayer`, not an existing target ExoPlayer engine.
- `android/app/src/main/AndroidManifest.xml:196` registers the existing audio-service
  playback service; Kotlin service transfer must replace its consumers together.
- `android/app/src/main/kotlin/com/zarz/mornye/NativeAudio.kt:8` exposes Oboe and native
  decoder JNI functions; CMake links Oboe/WavPack/FLAC.
- `lib/services/cast_output.dart`, `cast_playback_deck.dart`, Android Cast plugin and
  Rust cast service are separate from ordinary local playback.

Reference revision: `88e59879402cd23696a222c9a395592fa7fd1ea3`.

- `player/engine/EngineSelectionPreferences.kt:18`: Media3 default.
- `player/decoders/DecoderRegistry.kt:200`: platform and Kotlin providers registered.
- `sharedLogic/src/commonMain/kotlin/com/amwolfstein/sistrum/player/PlaybackQueue.kt:7`,
  `:79–82`: 1,000-ID truncation/deduplication and original-index clamp require target
  characterization before adaptation; do not copy that semantic mismatch.
- `MainActivity.kt:628`: system output switcher, not established Google Cast parity.
- `androidApp/src/main/cpp/CMakeLists.txt:1`: reference still builds the old FFmpeg
  native player; no-native completion is not established.

## Design

- Ownership and dependency direction: final Flutter presentation → typed client →
  Kotlin playback service/coordinator → Media3 and pure JVM components. The detailed
  draft bridge, state transitions and candidate boundaries are in the roadmap.
- Contracts across Dart, Kotlin and Rust: no signatures change now. Before code,
  define shared fixtures for request IDs/revisions, stable media IDs/source URIs/CUE,
  millisecond units, null duration, errors, ordering, snapshots and cancellation per
  `workflow/work/guides/contracts/playback-bridge.md`.
- State, threads, lifecycle and cancellation: current Dart owner stays authoritative
  during engine-only stages; E09 transfers ownership atomically. No competing queues
  or Dart/background timers after transfer. No blocking work on UI/command dispatchers.
- Failure: preserve explicit unavailable/unsupported/missing/permission/cancel/output
  failures and retry behavior; stale generation events cannot overwrite current state.
- Data compatibility: preserve IDs/schema/preferences/history/backups/cover keys and
  original-file survival, except an explicitly recorded owner-approved difference.
- Removal: none now. Every future deletion has a reference and acceptance gate;
  active FFmpeg consumers extend beyond playback. No imported Compose/database/sync.

Proposed code ownership (not recorded as reviewed modules in architecture.json):
`android/codecs/`, `android/dsp/`, `android/analysis/` for pure JVM imports;
`android/app/.../playback/` for Android Media3/service adapters; a Dart playback client
under `lib/services/` for transport and projection. Exact module boundaries depend on
E01 compatibility and bridge review. Existing source/metadata loader ownership is
unchanged. Do not create these directories in this documentation batch.

## Decisions

- PD-1: Plan only on a dedicated branch. Preserve existing internal-source commits;
  no player imports or deletion is authorized by this planning artifact.
- PD-2: Reuse source algorithms and tested mechanics selectively. Copying the whole
  Compose app or service would import unrelated sync/UI/state ownership.
- PD-3: Crossfade/DSD PCM/system output switching are not substitutes for target
  AutoMix/direct-output/Cast behavior. Explicit parity or recorded retirement required.
- PD-4: Follow the historical E01–E12 sequence. D1–D6 are guide-recorded policy,
  not new decisions made in this batch; reconcile output/licence/API applicability
  before code and identify the missing original authority document honestly.
- PD-5: No wholesale backend port or claim that Rust becomes metadata-only now.

## Constitution check

- [x] I. Current owner scope preserved; historical policy surfaced, no retirements applied.
- [x] II. Source and owner evidence separated from unrun target checks.
- [x] III. Comparison is the smallest requested complete deliverable; no runtime edit.
- [x] IV. Characterization and differential checks are required before future switches.
- [x] V. Target typed failure requirements specified; no current API changes.
- [x] VI. One owner per stage and shared bridge-fixture requirement documented.
- [x] VII. Data/publication invariants and no-copy database boundary documented.
- [x] VIII. Independent design review remains a gate before implementation; none claimed.
- [x] IX. Proposed boundaries correspond to actual platform/ownership responsibilities.
- [x] X. Docs/records commits only; no merge/history rewrite/APK. Push follows owner authorization.

## Complexity tracking

| Limitation | Consequence | Disposition |
| --- | --- | --- |
| Original AUDIO_ENGINE_MIGRATION.md absent | Historical guide cannot be represented as the original inspected document | Cite the existing guide and keep policy reconciliation visible |
| Reference and target are different applications | Source device experience is not target equivalence | Adapter/format/output tests and future device gates |
| Planning-only deliverable | No passing implementation or independent design gate exists | Keep draft plan status; no build/tasks approval |

## Verification plan

- Current checks: verify paths, pinned revisions, matrix coverage and documentation-only
  diff; `work.py lint 002`, `work.py check auto` (report unconfigured/blocked honestly).
- Existing test leads: `test/music_player_runtime_test.dart`, `music_player_gapless_test.dart`,
  `music_player_automix_test.dart`, `automix_phase_lock_test.dart`,
  `playback_library_queue_test.dart`, `playback_session_restore_test.dart`,
  `playback_equalizer_test.dart`, `playback_normalization_test.dart`,
  `cast_playback_deck_test.dart`, `content_uri_playback_cache_test.dart`.
- Future acceptance: add common bridge/decoder/DSP/queue fixtures and targeted native
  profiles before any port, then run the complete feasible suite and Android builds.
- Device cases: explicitly pending in the roadmap, not executed or waived by the
  owner's separately reported source-project experience.

## Open choices for the owner

No new product choice is required to complete this comparison. Before implementation,
reconcile historical output-retirement/API/licence policy and actual retained feature
scope. Independent design review and detailed executable assurance must precede code.
The existing change 001 is still in plan phase; verify its prerequisite status rather
than silently assuming an accepted engine implementation start.
