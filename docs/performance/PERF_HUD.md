# Developer performance HUD

A floating, developer-only overlay that shows Flutter frame timings. It is
independent of Glass and Blur: it draws an opaque-or-translucent solid panel,
with no `BackdropFilter`, `ImageFilter.blur`, `ShaderMask` or custom shader.

## Enabling it

The HUD is compiled in only when one of these holds:

- the build defines `SISTRUM_PERF_HUD=true` (`bool.fromEnvironment`), or
- the build is a debug build (`kDebugMode`).

An ordinary release build without the define has no overlay and no unlock
path. The flag lives in `lib/core/constants/perf_hud_build.dart`.

Inside a permitted build:

1. Open Settings > About.
2. Tap the version row seven times. Developer options appears under it.
3. Open Developer options and turn on **Performance HUD**. Opacity, Reset
   performance metrics and Copy performance report are on the same page.

The HUD can also be closed from its own close button.

## Build commands

Measure on a real device with a profile build, not a debug one. The release
script (`scripts/build_android.sh`) hard-codes `--release --obfuscate`, so a
profile build is run directly with Flutter:

```bash
export PATH=$HOME/toolchains/flutter/bin:$PATH
dart scripts/prepare_flutter_sdk.dart
flutter build apk --profile \
  --target-platform android-arm64 \
  --dart-define=SISTRUM_PERF_HUD=true \
  --dart-define=GIT_COMMIT=$(git rev-parse --short=8 HEAD)
adb install -r build/app/outputs/flutter-apk/app-profile.apk
```

The Android Gradle build compiles the Rust backend for the selected ABI as
part of the build. This document was written without a device, so the profile
APK has not been installed or measured on hardware here.

## Behaviour

- **Position.** Starts in the upper-right corner, below the status bar and
  any cutout. Drag it with the panel body (the grip icon marks it). It clamps
  to the safe area (system bars, cutouts, 8 dp margin) and is saved on drag end
  and restored on the next launch. Orientation changes re-clamp it.
- **Expand and collapse.** A tap on the panel toggles compact and expanded.
  Buttons inside the expanded panel use their own taps.
- **Touch.** The overlay is a `Positioned` child of a root `Stack`, so only the
  panel's bounds take touches. The rest of the app stays interactive.
- **Layering.** The overlay sits above the navigator, so it floats above
  routes, dialogs, sheets, the bottom bar and the mini player.
- **Refresh.** Numbers refresh every 750 ms from one `Timer` inside the
  overlay. The app root never rebuilds for the HUD.
- **Disabling.** Turning the HUD off stops the timing callback and cancels the
  refresh timer.

## Metrics

Frame timings come from `SchedulerBinding.instance.addTimingsCallback`. The
callback copies each `FrameTiming` into a bounded ring of 300 frames (a
constant, `kPerfWindowFrames`) using preallocated typed lists. It does not
allocate per frame, log, or call `setState`. The callback is removed by
`removeTimingsCallback` when monitoring stops.

- **Build and raster.** `buildDuration` and `rasterDuration`, reported as
  p50, p90 and p99 over the window. Percentiles use the nearest-rank method on
  a sorted copy, computed only when the HUD refreshes.
- **Frame-budget exceedance.** The percentage of window frames whose
  `totalSpan` (vsync start to raster finish) is longer than the budget.
- **Budget.** `1000 / hz` ms. For 60 Hz this is 16.67 ms.
- **Refresh rate.** Read from `FlutterView.display.refreshRate`. A value
  outside 20–360 Hz, or no value, uses 60 Hz and is labelled **fallback**.
- **FPS estimate.** `(frames − 1) / (newest frame end − oldest frame end)`.
  It is an estimate from frame timing, not a display measurement, and it is
  labelled as such.
- **Window.** Duration between the oldest and newest frame end in the window.

An empty window reports `n/a`, never `0`. Reset clears the window and the
total frame count.

## Copy report

Copy writes one text block. Estimated values are labelled.

```
sistrum-perf
screen=/library
hz=60
hz_source=reported
budget=16.67ms
frames=300
frames_total=1234
window=rolling
window_ms=4999
build_ms_p50=1.82
build_ms_p90=3.10
build_ms_p99=6.40
raster_ms_p50=2.05
raster_ms_p90=4.80
raster_ms_p99=9.70
frame_budget_exceedance=2.3%
fps_estimate=59.8 (estimated)
```

`screen` is the current route path (from GoRouter when available, otherwise
`unknown`). `hz_source` is `fallback` when the display gave no usable value.

## Glass POC

Developer Options > Glass POC is a developer-only page that compares four
rendering modes on identical geometry: Transparent Baseline, Basic Blur,
Liquid Glass and Reference Glass. It is not reachable from production screens.
Glass modes use the pinned `liquid_glass_widgets` 1.16.1 package. Liquid Glass
shares one `LiquidGlassLayer`; Reference Glass gives each surface its own layer.
A shared layer's grouped premium children are not drawn, so Reference Glass
must not use one. The selected mode is shown in the HUD panel
(`Glass`) and written to copied reports as `glass_mode=`. The Glass POC copy also writes `glass_render_path` (the verified path, `full_gpu`, `fake_backdrop`, `backdrop_filter`, `none` or `unverified`), `glass_fallback`, the scene, and the Scene D scroll fields (`scroll_speed_preset`, `scroll_speed_target`, `scroll_speed_actual`, `scroll_speed_unit`, `scroll_direction`, `scroll_boundary_behavior`, `scroll_boundary_transitions`); see `GLASS_ARCHITECTURE_DECISION.md` section 10. The mode is held in
memory, so a restart returns to the baseline. Modes are reviewed on a physical
device only; no benchmark results are recorded here before that review.

## Limitations

- **Budget exceedance is not dropped-frame counting.** It compares each frame's
  span with the budget. A frame that misses a vsync but still finishes under
  the budget can be missed. Conversely, a frame that finishes just over the
  budget counts even if the user did not see a stutter.
- **Build plus raster is not frame latency.** The two phases overlap with the
  engine pipeline, and the vsync wait is not counted, so their sum does not
  equal the time to show a frame.
- **FPS is estimated.** It comes from the spacing of frame ends and is only
  meaningful over a steady window.
- **No GPU metrics.** Flutter's `FrameTiming` gives no GPU counters, backdrop
  reads or shader timings, and none are reported or inferred.
- **Refresh rate may be unknown.** Where the engine cannot report it, the
  fallback of 60 Hz is shown and labelled.
- **Profile, not debug.** Debug builds are slower and their numbers are not
  representative. The HUD is available in debug builds for convenience only.
- **Platform timing.** Timings come from the framework. They are not a
  system trace. Use Perfetto or Flutter DevTools for a deeper breakdown.

## Files

- `lib/core/constants/perf_hud_build.dart`: build gate.
- `lib/services/performance/perf_frame_window.dart`: bounded window, snapshot,
  percentiles, refresh-rate resolution, report formatting. Pure Dart.
- `lib/services/performance/perf_frame_monitor.dart`: callback owner and the
  app-wide monitor provider.
- `lib/providers/performance/perf_hud_settings_provider.dart`: persisted HUD
  and Developer options state.
- `lib/widgets/performance/perf_hud_geometry.dart`: clamping and default
  corner. Pure Dart.
- `lib/widgets/performance/perf_hud_overlay.dart`: the overlay.
- `lib/screens/settings/developer/developer_options_page.dart`: Developer
  options.
- `lib/screens/settings/about_page.dart`: the seven-tap unlock.
- `lib/app.dart`: mounts the overlay above the navigator.
- `lib/screens/settings/developer/glass_poc_page.dart`: the Glass POC page.
- `lib/widgets/glass_poc/`: `SistrumGlassSurface`, `SistrumGlassScope` and modes.

Glass POC spike recorder: while the Glass POC page is open, sustained budget degradation (15 of the last 30 frames over budget) is captured with 120 frames before and after, and copied with "Copy spike log". It is developer-only, bounded (8 snapshots), and does not change the HUD's metrics. See `GLASS_JANK_INVESTIGATION.md`.
