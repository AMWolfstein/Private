# Architecture, API Coherence, and Initialization Review

- **Repository:** Sistrum
- **Branch:** `desloppify/code-health`
- **Reviewed commit:** `ed3aaf7b`
- **Review method:** Read-only source review using Graphify navigation and direct inspection of implementation and callers.
- **Scope:** Cross-module architecture, API coherence, and initialization coupling. Split `part` files were assessed as one Dart library; splitting files was not counted as a design improvement by itself.

## Scores

| Dimension | Score | Assessment |
| --- | ---: | --- |
| Cross-module architecture | 86/100 | Service-to-screen/provider imports are generally avoided, but the audio-analysis widget still owns operational workflow that crosses the UI/service boundary. |
| API coherence | 88/100 | Most inspected boundaries have clear types, but scan-progress decoding silently converts unexpected result shapes to empty data. |
| Initialization coupling | 82/100 | Playback provides injectable dependencies and single-flight initialization, but restoration and widget/status integration still depend on runtime-global state. |

Scores are evidence-based judgments of the inspected code, not measured reliability or proof of device behavior.

## Findings

### 1. P2 — A transient restore failure can prevent later retries

- **Dimension:** Initialization coupling
- **Evidence:** `lib/services/playback/music_player/music_player_runtime.dart:233-234` caches the restore Future. `lib/services/playback/music_player/music_player_session_restore.dart:9-12,79-81` catches errors while reading or restoring the session and returns normally. `lib/screens/shell/main_shell.dart:91-93` starts the restore without an explicit retry.
- **Impact:** If reading the saved session fails before a handler is attached, the completed Future can remain cached; subsequent restore calls reuse it rather than attempting the operation again. This is a source-level behavior; frequency and user-visible impact have not been measured on a device.
- **Suggested fix:** Return an explicit restore outcome, retain single-flight behavior while restoration is pending, and clear the cached Future on retryable failure. Add a test for a first failed database read followed by a successful retry.

### 2. P2 — A scoped Android playback runtime binds to the global widget service

- **Dimension:** Initialization coupling
- **Evidence:** `lib/services/playback/music_player/music_player_runtime.dart:98-102` supports separately constructed runtimes and injected dependencies. At `:217-220`, every successfully initialized Android runtime binds its handler to `PlayerWidgetService.instance`. The binding replaces the service's previous handler and subscriptions in `lib/services/playback/notification/player_widget_service.dart:119-125`.
- **Impact:** Initializing a second scoped runtime can redirect the process-wide player widget to its handler. The effect on normal production use is not established; the trigger requires multiple runtimes with Android behavior enabled.
- **Suggested fix:** Inject widget binding into the runtime or perform global widget binding at the application composition root. Test two runtimes and both disposal orders.

### 3. P2 — The audio-analysis widget coordinates non-UI operations

- **Dimension:** Cross-module architecture
- **Evidence:** `lib/widgets/audio_analysis/audio_analysis_widget.dart:64-89` constructs FFmpeg jobs and the analysis runner. The same Dart library's `lib/widgets/audio_analysis/audio_analysis_card_pipeline.dart:132-160` coordinates cache invalidation, cache reads, analysis execution, and cache writes. The runner and store already exist under `lib/services/audio_analysis/`.
- **Impact:** Testing or reusing the complete analysis workflow requires exercising widget-owned state and lifecycle even when the intended behavior concerns analysis and persistence. This is a boundary and testability concern; no runtime performance impact was measured.
- **Suggested fix:** Move the operational workflow and cancellation coordination into a focused controller or service. Retain image rendering and disposal in the widget, and test cache hits, cancellation, and failures without mounting UI.

### 4. P2 — Scan-progress decoding silently accepts an unexpected result shape

- **Dimension:** API coherence
- **Evidence:** `lib/services/native/native_channel.dart:91-102` returns an empty map for null, an empty string, or a decoded non-map. The required and nullable map decoders at `:64-88` reject unexpected non-map values. `lib/services/native/library_scan_bridge.dart:173-177,191-194` uses the permissive decoder for polling and events; `lib/services/library/scan/library_scan_progress.dart:31-44` defaults absent progress to zero.
- **Impact:** A native contract mismatch can look like an empty progress snapshot instead of reaching the polling-error or stream-fallback handling. This was determined by tracing the source; no malformed device response was injected.
- **Suggested fix:** Define whether null or an empty payload is valid. Reject unexpected shapes consistently, preserve intentional fallback behavior, and add malformed polling and event response tests.

### 5. P3 — Scoped handler status checks the global playback runtime

- **Dimension:** Initialization coupling
- **Evidence:** `lib/services/playback/music_player/music_player_service.dart:154-161` accepts a runtime, defaulting to the global runtime only when none is supplied. `lib/services/playback/music_player/music_player_hooks.dart:65` instead tests whether the handler belongs to global `musicPlayerRuntime`. `lib/services/playback/automix/music_player_automix_status.dart:3-7` only publishes AutoMix status when that test succeeds.
- **Impact:** An independently owned runtime does not publish through that global status path. Whether that is an intentional restriction or a user-visible issue for a production configuration requires verification.
- **Suggested fix:** Specify the intended ownership of global AutoMix status. If scoped runtimes should publish, inject a status publisher or use the owning runtime; otherwise document and test the restriction.

## What was verified and what remains open

- The review found no direct imports from application screens or providers into the inspected service layer. A navigation module under `core` uses UI primitives; navigation itself is a UI boundary, so its location alone was not reported as a defect.
- No application source, tests, or production configuration were changed during this review. Findings were established from source and caller inspection; no new tests, Android device runs, or performance measurements were performed.
- `LOCAL_OFFLINE_MIGRATION_PLAN.md` reports a prior clean analysis and 2,253 passing Flutter tests on this tree. Those are historical project records, not tests executed as part of this review.
- Multi-runtime widget behavior and progress-contract failure handling need targeted tests; no claim is made that either was observed on a physical device.
- Graphify output was used for navigation and was partly truncated; exact claims were checked in source. File line numbers refer to the reviewed commit and can move in later revisions.
