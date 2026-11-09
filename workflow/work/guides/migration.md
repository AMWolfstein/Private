# Media3 and Kotlin migration authority

Source: owner's selected `docs/AUDIO_ENGINE_MIGRATION.md` in AMWolfstein/Private at bf827a53. Historical reference: retired Compose Sistrum, feature/media3-migration at 88e5987. All batches below are PLANNED in this starter. Reference sources must be checked at port time. Old paths/counts are discovery hints, not current evidence.

## Accepted direction

- Target application: Flutter UI, Kotlin behavior, Media3/ExoPlayer; no app-owned Rust/C++ implementation in the final state.
- D1: owner accepted GPL-3.0 migration for the reference code. At first import apply the accepted GPL-3.0-or-later project licence, retain original MIT notices and applicable GPL-only/third-party attribution; inspect actual file obligations. Do not strip notices.
- D2: minimum Android API 31 at the first engine-port code batch.
- D3: retire Direct USB/libusb. Preserve Android 14+ preferred-mixer bit-perfect and DoP; do not claim Java USB replaces isochronous libusb.
- D4: retire Oboe/AAudio HiResPlayback and dapExclusive, including settings/search/backup output; old imports ignore retired keys.
- D5: CUE plays through Media3 ClippingConfiguration; remove Split only once direct CUE playback is available.
- D6: Kotlin MediaLibraryService/coordinator owns playback, queue, restore, history, notifications, Auto, widget, focus, sleep timer, normalization and AutoMix/autoplay decisions. Flutter is the client. Remove audio_service/audio_session/audioplayers when replacement behavior is verified.
- FFmpeg is removed feature by feature after replacement verification, not used as the new playback engine.

D6/section 6.1 supersedes stale earlier instructions to keep the coordinator/AutoMix decisions in Dart or never port PlaybackService. Stage-specific adapters may temporarily take Dart arguments before service ownership transfers. The old plan's headline “no decisions made” is obsolete for D1–D6.

## Modes and order

**In-place migration:** keep the existing implementation as a temporary comparison/fallback only where the plan calls for it. Media3 first, backend port only after engine/device acceptance.

**New repository:** build target Kotlin components directly; do not install Rust/C++/FFmpeg only to delete them. Use an accessible separate reference checkout and fixtures for comparisons. Preserve the same behavioral acceptance dependencies; this is a packaging adaptation, not permission to run two unverified rewrites concurrently. Until the Media3 milestone is proven, reference backend/data behavior may be exercised in its reference environment or through a specifically designed temporary adapter. Record actual strategy in the first design. If this prevents a prerequisite being verified, mark it blocked rather than pretending parity.

## Engine batches (original section 7)

| Batch | Deliverable | Acceptance/removal dependency |
|---|---|---|
| E01 | Import/licence/API31 setup; codecs, DSP, analysis JVM modules | Source/notice inventory and host tests; no unrelated Compose import |
| E02 | Shared bounded offline decode service | Common corpus versus existing decode oracle; analysis/haptics/AutoMix consumers; cancellation/cleanup |
| E03 | Cover resize/probe and tag/ReplayGain fallback removal | Preserve failed-write originals; validate replacement per F4/F5/F2/F3 |
| E04 | Media3 platform-decoder engine and gapless | Characterization and device tests before retiring old engine |
| E05 | Registry/Kotlin format providers, failure reporting | Per-format corpus, scanner support and unsupported-format reporting |
| E06 | N-band EQ, balance, compressor, limiter, gain | Preset compatibility; no double Opus gain; output/DSP comparison |
| E07 | Dual-player AutoMix and live effects | Shared-session behavior, beat landing/phase-lock regressions, weak-device CPU/power; remove temporary renderer only after replacement |
| E08 | Direct CUE playback | Boundaries/seek tests, then retire Split atomically |
| E09 | Kotlin service/coordinator and Dart client | Background/focus/Auto/widget/session/queue tests; then remove audio_service/audio_session/audioplayers |
| E10 | Retained Android14+ bit-perfect/DoP source; retire direct USB/AAudio | Exact FLAC choice and PCM comparison before removing libFLAC/WavPack C/Oboe |
| E11 | Dependency/resource cleanup and policy update | Search actual callers; no obsolete flags/build paths; inspect packaged libraries when packaging authorized |
| E12 | Device acceptance | Gapless, AutoMix, EQ, DAC/DSD, Bluetooth/buttons/Auto/widget and one-hour screen-off/power evidence |

These batches summarize the original 15 steps; they do not waive their acceptance conditions. Optional new features (measured loudness, stereo width, silence-aware mixing) are not automatically required. Known reference gaps include decoder performance, power/CPU, output continuity, stale limiter status and failed-restore handling; “ported” does not mean “fixed”. Recheck the old queue clamp when importing the Kotlin coordinator.

## Backend batches (original section 10; after E12)

1. Lyrics/XML/playlist writing/CUE/palette.
2. Audio analysis.
3. Cover cache/library DB/collections and migration coordination.
4. Backup with compatible archives and failure-safe publication.
5. Tag reading then tag writing, with high-risk corruption tests.
6. Confirm retired Direct USB and retained Android14+ route.
7. Remove remaining Rust/UniFFI/JNA/build wiring only after all parity gates.

In place, use the CoreBackend seam and preserve its Dart-facing API. In a new repository, establish an equally narrow Kotlin boundary and prove compatibility against reference fixtures instead of copying unused Rust scaffolding. Preserve song IDs, schema/migration behavior, cover keys, tag contents and CUE interpretation. Final exact FLAC must be Kotlin; claxon is not a final-state solution. Own native builds disappear, but Flutter still ships native libraries; verify toolchain packaging requirements instead of promising every NDK tool is universally unnecessary.

## Open design choices to resolve at the relevant batch

- Exact Kotlin FLAC source/port and 16/24/32-bit corpus parity.
- First EQ implementation (plan offers DynamicsProcessing before generalized biquads); do not silently reduce supported bands/presets.
- D7 unsupported TTA/TAK and other decoder gaps: original plan recommends unsupported reporting but does not mark owner acceptance. Confirm at format scope definition.
- Actual reference revision, Media3/toolchain pins, database ownership, bridge payloads and new-repository comparison strategy.

Do not reopen accepted D1–D6 merely because a skill recommends another approach. Record subsequent owner changes as explicit decisions, with affected tests and batches.
