# Media3/ExoPlayer comparison and migration plan

Status: source comparison and draft implementation roadmap only. No player code,
decoder, dependency, minimum SDK, licence or runtime preference changes in this batch.

## Revisions and evidence

- Target: `AMWolfstein/Private`, branch `media3-exoplayer`, created from
  `933e0bd6fbc00899372a815a74ab6fffc3a5fe73` on `extension-system`.
- Reference: `AMWolfstein/SistrumKotlin`, `feature/media3-migration`,
  `88e59879402cd23696a222c9a395592fa7fd1ea3`.
- The owner reports running the Kotlin implementation on their phone. This is valid
  source-project experience; the exact device, scenarios and measurements were not
  supplied here. It is not evidence of the future Flutter integration passing.
- This comparison inspects source and checked-in test/measurement records. No new
  Gradle, Flutter, native or device tests were run for this documentation-only batch.
- `docs/AUDIO_ENGINE_MIGRATION.md` is absent from this target checkout. Existing
  `workflow/work/guides/migration.md` records historical direction, D1–D6 and E01–E12;
  it must not be represented as a newly inspected original migration document.

The reference has an implemented Media3 engine, a default Media3 selection, Kotlin
codec providers and pure JVM codecs/DSP/analysis/metadata modules. It is a reusable
source baseline, not a drop-in replacement or a completed no-native application.

## Feature comparison

A candidate marked **adapt** is not parity-verified. Reference files below are under
`androidApp/src/main/kotlin/com/amwolfstein/sistrum/` unless otherwise specified.
Target paths are relative to this repository. Tests are existing leads to preserve
and extend, not claims that those tests were executed here.

| Feature | Current Flutter application | Kotlin reference | Disposition / integration gate |
| --- | --- | --- | --- |
| Play, pause, resume, seek, errors | `lib/services/music_player_service.dart`, `music_playback_deck.dart`; normal output uses the patched audioplayers Android `MediaPlayerWrapper.kt` | `player/media3/Media3Engine.kt`, `Media3PlayerFactory.kt` | Adapt engine and preserve `PlaybackDeck` behavior; malformed source, rapid seek and failed prepare cases first. Current engine is not already ExoPlayer. |
| Queue, current item, shuffle, repeat | Dart `MusicPlayerHandler`; `test/playback_library_queue_test.dart`, `music_player_runtime_test.dart` | `player/PlaybackCoordinator.kt`, `sharedLogic/src/commonMain/kotlin/com/amwolfstein/sistrum/player/PlaybackQueue.kt` | Adapt domain rules; do not import the 1,000-item cap or distinct-ID assumptions without testing requested-item identity and existing duplicates. |
| Queue edge case in the reference | Target requested item must survive any preparation/paging | Reference `PlaybackQueue.play` deduplicates/takes 1,000 then clamps the original index | Confirmed import hazard: 1,001 unique IDs with start index 1,000 selects item 999; `[a,a,b,c]` starting at index 2 selects c after deduplication. Fix identity mapping in the target port with tests; do not modify the separate reference repo here. |
| Gapless | `lib/services/music_player_gapless.dart`, `test/music_player_gapless_test.dart` | Media3 playlist/transition handling; `Media3EngineGaplessTest` | Adapt; verify exact boundaries, trim, mixed sample rates, repeat and cancellation on a device. |
| Crossfade | Dart AutoMix/decks and cancellation | Dual-player `Media3Engine` / `TransitionController` | Reuse tested mechanics where compatible; audible continuity and stream clocks remain device gates. |
| Beat-matched AutoMix and effects | `music_player_automix.dart`, `automix_phase_lock.dart`, `automix_effect_renderer.dart`; phase-lock and effect tests | Crossfade and silence-aware transitions; no established equivalence to the target beat/tempo/phase-lock contract | Adapt separately in E07. Ordinary crossfade must not silently replace AutoMix, tempo matching or live effects. |
| Gain / ReplayGain / normalization | `playback_normalization.dart`, `replaygain_service.dart`; existing settings/tag fallback | Gain processors/resolver; measured-loudness and tag fallback | Preserve current modes, settings and Opus handling. Measured loudness is not automatically a newly required feature. Compare samples/levels with documented tolerances. |
| EQ and limiter | `playback_equalizer.dart`, patched Android EQ; `test/equalizer_test.dart` | Float DSP chain; `FloatChainAudioSink.kt`, limiter/session logic | Adapt band count, parameter ranges, presets and bypass semantics. Do not substitute a differently parameterized reference EQ. |
| WavPack / APE / WMA / Musepack / ALAC / AIFF / PCM | Current Android/native/FFmpeg paths depend on format and output | `player/decoders/DecoderRegistry.kt:200` registers platform plus Kotlin providers; independent `codecs/` module | Reuse/adapt after a per-format corpus and scanner/container acceptance matrix. A registered provider is not universal format coverage. |
| DSD | USB/direct and PCM paths in target, including native dependencies | `KotlinDsdProvider.kt` exposes float PCM and conversion; Kotlin DSD/container code has documented refusals | DSD-to-PCM is not USB native DSD/DoP. Preserve or explicitly retire each route; DST and channel/rate restrictions must be reported. |
| USB direct / bit-perfect | `UsbDirectPlayback.kt`, `UsbPcmSource.kt`, Rust `mobile/src/usb_audio.rs`, native FLAC/WavPack | No equivalent app-owned isochronous USB path established by this review | Historical D3/D4 records retirement of libusb/AAudio while retaining preferred-mixer/DoP. Surface that policy before implementation; do not claim existing direct USB can simply move to Kotlin. |
| HiRes / Oboe output | `android/.../HiResPlayback.kt`, `NativeAudio.kt`, C++ Oboe/libFLAC/WavPack | Media3/AudioTrack/float sink | Historical retirement is a product difference, not proven equivalent output. E10 requires route/format/DSP-bypass evidence before native removal. |
| Google Cast | `lib/services/cast_output.dart`, `cast_playback_deck.dart`; Android Google Cast plugin plus Rust media server | `MainActivity.showSystemOutputSwitcher` uses Android's output switcher | Preserve the target's real Cast route. The reference button is not a replacement for the Cast receiver integration or HTTP media server. |
| Background, focus, headset buttons, notification | `audio_service` Android service; Dart handler and platform bridges | Kotlin `PlaybackService`, focus/noisy receiver, `MediaSession` and notifications | Adapt service ownership; source uses Android `Service`/platform `MediaSession`, not the target-guide Media3 `MediaLibraryService`. Native bridge/session design is required. |
| Android Auto and widgets | Existing audio-service browser and target player widgets | Source session/service behavior and app-specific consumers | Target browser/Auto/widget acceptance is required; do not infer Android Auto parity from a notification or MediaSession alone. |
| Restore / sleep / history / metadata updates | Session writer/restore stores, runtime sleep timer, listening stats | Coordinator/session stores and app-specific sync/listening dependencies | Preserve target IDs, preferences and history formats. Do not import reference Room/sync/device identity. Screen-off/kill/reconnect tests before ownership transfer. |
| SAF/content URIs | Target SAF/file leases/cache handling | Reference runtime resolves app-synced files; codec random-access adapters exist | Add content-URI/revoked-permission/seekable and non-seekable source acceptance. Absolute file paths alone are insufficient. |
| CUE | Existing cue/split library flow | Reference CUE integration tasks remain open in spec 002 | Direct clipped CUE playback must pass boundaries/seeks/backing-file tests before Split can retire, per historical D5. |
| Haptics / preview / playback rate | Target haptics/preview/deck APIs and tests | No complete equivalence established | Inventory consumers and adapt or explicitly retain them; absence from the reference is not permission to remove them. |
| Network files / caches | Existing network source/cache/offline-save behavior | Source is local/offline-oriented | Keep until a separate approved offline-scope change handles remote-only files. Do not remove it accidentally during the engine port. |
| Metadata | Rust/native and Dart/FFmpeg read/write/enrichment paths | `metadata/` is a broad pure-JVM read-only WaxLabel port | Candidate for a later reader task. Not a replacement for tag writing, embedding pictures/lyrics, preserving tags or atomic SAF publication. |
| Images, lyrics, internal sources | Staged code under `extensions/`; active Rust/old extension system remains | Not a proven replacement for the target internal-source runtime | Independent workstream. Do not change source loader, update cadence, providers or lyrics normalization in the engine comparison batch. |

## What can actually be reused

1. **Candidate reuse:** pure `codecs/`, `dsp/` and `analysis/` implementations and their
   independent oracle fixtures, preserving pinned origins and attribution.
2. **Adapt:** Media3 engine, factory, extractor/provider adapters, stream gain and
   transition logic. Recheck Media3 experimental APIs against the exact pinned version.
3. **Adapt with explicit tests:** queue/coordinator, serialization and restore behavior.
   The reference service is tied to sync, diagnostics, resources, Last.fm and UI startup.
4. **Exclude:** Compose UI, reference branding/database/sync/identity, legacy native
   engine, FFmpeg build and the developer engine-selection UI.
5. **Defer:** optional new sound features and wholesale backend rewrite. Keeping Rust
   only for metadata is not decided or implemented by importing a playback engine.

The reference pins Media3 1.11.1 and API 31, while target Gradle currently delegates
minimum SDK to Flutter and uses its own AGP/Kotlin configuration. Copy no root Gradle
or version catalog wholesale. Verify JDK/AGP/Kotlin/Media3 compatibility at E01.

## Proposed ownership and bridge

Final direction: Flutter UI → typed Dart playback client → Method/Event channels →
Kotlin service/coordinator → Media3/decoder/DSP interfaces. Pure JVM modules do not
import Flutter, Android UI, application databases or channel maps.

During engine-only batches the existing Dart coordinator remains authoritative.
During E09, transfer the authoritative queue, history, restore, sleep and transition
ownership atomically to the Kotlin service. Flutter then observes snapshots; it does
not run a competing queue or schedule background fades. Do not run both owners live.

Before coding the bridge, specify common Dart/Kotlin fixtures for:

- request ID, session epoch and monotonic queue/state revision; accepted versus
  completed results; exactly one terminal result for accepted work;
- stable media IDs, source URI, CUE boundaries, artwork reference, nullable metadata;
  integer millisecond positions/durations and explicit null for unknown duration;
- commands for queue changes, play/pause/stop/seek/skip, shuffle/repeat/sleep/settings;
- authoritative queue/current-item/state/output/EQ/error snapshots plus bounded
  position events; reject events from older epochs or replaced prepare generations;
- typed missing/unsupported/permission/cancelled/operation/output failures;
- Activity/Flutter-engine detach versus service destruction, reattach snapshots,
  focus loss, noisy output, background execution and native-only media controls;
- blocking file/decoder/HTTP work off UI/command dispatchers, bounded buffers and
  cancellation that interrupts owned work and releases leases/temporary files.

Preserve current IDs, database schemas, preferences, backups and cover identity.
Define storage access needed when Flutter is absent; do not share SQLite merely by
opening the same filename from a second cache/connection owner.

## Ordered migration batches

These follow E01–E12 from the target's migration guide; each is a future batch.
The current commit implements none of them. Replacement tests precede switching
consumers, and reference device experience is kept separate from target evidence.

| Batch | Deliverable | Gate before next consumer/removal |
| --- | --- | --- |
| E01 | Resolve recorded licence/API/output policy; import selected pure modules and fixtures into Android Gradle modules | Pin source/licences; compatible build and JVM oracle tests; no Compose/legacy engine import |
| E02 | Bounded native offline decode shared by analysis/AutoMix/haptics | Same corpus as current decode path; exact PCM where promised; cancellation, seek, channel/rate and resource tests |
| E03 | Replace cover resize/probe and individual tag/ReplayGain FFmpeg fallbacks | Original file survives read/write/flush/publication failures; retained tags and SAF semantics compared |
| E04 | Platform-decoder Media3 deck behind current seam, including gapless | Existing transport/queue/gapless characterizations plus device continuity; old engine remains comparison-only |
| E05 | Add Kotlin registry/providers and scanner support | Per-format corpus including corrupt/unsupported/rate/channel variants, requested-track identity and failure reporting |
| E06 | Adapt EQ, normalization, gain, limiter and retained processing modes | Existing preset/settings compatibility; no double gain; sample/level and device output checks |
| E07 | Port target AutoMix, phase locking and effects to native timing | Existing beat landing/phase-lock/effect tests plus weak-device two-decoder CPU/power and audible continuity |
| E08 | Direct Media3 CUE playback | Exact clip boundaries, seek/repeat/backing-file safety; only then retire Split |
| E09 | Kotlin service/coordinator with Dart client | Shared bridge tests; Auto/browser/widget/focus/media buttons; restore/sleep/stats; real screen-off and reconnect tests; then retire old audio plugins |
| E10 | Retained Android14+ preferred-mixer bit-perfect/DoP and explicit output retirements | Decoder choice, exact PCM/DoP, DAC routes and bypass behavior proven; no inferred USB equivalence |
| E11 | Remove proven obsolete playback code/dependencies/build resources | Full source/build/export/package inventory with zero retained callers; source-specific licence/notice review |
| E12 | Final target device acceptance | Gapless, AutoMix, EQ, DAC/DSD, Cast, Bluetooth/buttons/Auto/widgets and one-hour screen-off/power evidence |

## FFmpeg and app-owned C++ removal gates

**Yes, their retirement can be a target. No, the current source is not ready for
those deletions.** Playback moving to Media3 does not replace all FFmpeg consumers.

| Dependency | Current retained uses | Required evidence before deletion |
| --- | --- | --- |
| FFmpeg/ffprobe | `ffmpeg_support.dart`, `audio_analysis_runner.dart`, `automix_analyzer.dart`, `automix_effect_renderer.dart`, `replaygain_service.dart`, `ffmpeg_metadata.dart`, cover/probe/split/enrichment/finalization paths | Enumerate all direct and indirect callers, replace or separately approve removal of each feature, compare formats/analysis/effects/tag outputs, failure-inject writes and SAF publication, then remove plugin and extension-host native fallbacks together |
| App-owned C++ | `android/.../NativeAudio.kt` JNI for Oboe, native FLAC and WavPack; `android/app/src/main/cpp/CMakeLists.txt` links Oboe/WavPack/libFLAC | Prove retained format/output behavior, handle D3/D4 retirement explicitly, verify callers/JNI/exports/CMake dependencies and inspect final Android linkage before removal |
| Rust audio functions | USB worker, analysis and Cast media server, among others | Separate dispositions after engine/device acceptance; not deleted by a Kotlin engine import |

Removing app-owned C++ is not a promise of zero native `.so` files: Flutter, retained
Rust and dependencies may still ship native code. FFmpeg removal and C++ removal are
separate gates. Do not replace the hardware tests with source scans or test counts.

## Verification and confidence

- Current coverage: code inspection and repository-backed test inventory only.
- Source records report prior host/device results but also metadata corpus and
  hardware/performance gaps. They are not newly executed target results.
- Maintain a format × container × sample format/rate × channels × source kind ×
  output × processing-mode matrix; record unsupported cases instead of silently
  falling back or claiming every format plays.
- Planned automated commands: formatting/analyzers, existing Dart regressions,
  JVM codec/DSP/parity/bridge tests, Rust checks for any changed native boundary,
  Android JVM tests and debug/release arm64 builds. Register actual targeted
  commands before implementation; do not fabricate a passing workflow profile.
- Planned device cases: local and SAF, denied/revoked access, rapid commands, killed
  UI process/reattach, focus and route changes, DAC, Cast, offscreen fades and power.
- No physical-device testing or Android build occurs in this planning batch.

## Decisions before implementation

The target migration guide records GPL-3.0/API31, retirement of direct libusb and
AAudio, preservation of preferred-mixer bit-perfect/DoP, CUE-before-Split and a Kotlin
MediaLibraryService owner. This session authorizes a comparison/plan, not executing
those retirements. Reconcile their applicability with the owner's requested retained
features before code imports; record any superseding owner decision explicitly.

Independent design review and detailed bridge/port assurance are still required
before implementation. The active Android-only change 001 is not marked done in
its workflow records; verify/close its prerequisites or record an explicit owner
sequencing decision. Do not mark this plan as implementation-approved merely because
its documentation is committed or pushed.

Formal record: [change 002](workflow/work/changes/002-media3-playback-comparison-and-migration/plan.md).
