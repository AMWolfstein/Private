# Glass benchmark: refresh rate and metric definitions

Status: uncommitted. Covers the 120 Hz detection fix and the definitions the
benchmark report uses. Earlier 60 Hz results were recorded with the old budget
and are not rewritten; compare them only by their own report fields.

## Root cause of the 90 Hz report on a 120 Hz panel

Android and Flutter report the refresh rate through different paths:

- Android side (`DisplayRefreshRatePlugin`, `Display.getMode()`): updated by
  `DisplayListener` events and by the window request. It reports 120 Hz.
- Engine vsync (`VsyncWaiter.java`): `DisplayListener.onDisplayChanged` calls
  `setRefreshRateFPS`, which updates only the native vsync waiter. The vsync
  cadence therefore follows the real mode (engine VSync P50 8.35 ms on the
  120 Hz runs).
- Dart `FlutterView.display.refreshRate`: fed by `Shell::OnDisplayUpdates` ->
  `engine->SetDisplays`. That runs only from `AndroidShellHolder::UpdateDisplayMetrics`,
  called on engine start and on size or density updates (`FlutterJNI.updateDisplayMetrics`).
  A refresh-only mode change does not call it, so the Dart value stays at the
  rate read at the last metrics update (90 Hz here).
- `Shell::GetFrameBudget` (`shell.cc:1816`) caches the first refresh rate in
  `cached_display_refresh_rate_` and never clears it.

So the benchmark's `refresh_hz=90` and `frame_budget_ms=11.11` came from a
stale Flutter value, not from the vsync stream. The fix does not use the
Flutter value for the budget while Android reports an active mode.

## Metric definitions

| Name | Source | Meaning |
|---|---|---|
| `selected` | settings | The user's preference (0 = System Default). |
| `requested` | window attributes | `preferredDisplayModeId` set by the app. Not proof that Android accepted it. |
| `android_active_mode` | `Display.getMode()` | Mode Android reports as active. Used for the nominal budget. |
| `android_display_refresh` | `Display.getRefreshRate()` | Android-reported rate. Can differ from the mode rate. |
| `flutter_reported` (`refresh_hz`) | `FlutterView.display.refreshRate` | The engine's snapshot. Can be stale after a refresh-only change. Never used for the budget when Android reports a mode. |
| `nominal_refresh_hz` | `nominalDisplayRefresh` | Android active mode, else Flutter, else 60 Hz fallback (labelled). |
| `frame_budget_ms` | 1000 / nominal | Per-frame budget for exceedance and missed-slot estimates. 120 Hz = 8.33 ms. |
| `vsync_start_interval` | `FrameTiming.vsyncStart` deltas | Engine cadence. Measured, not inferred from the display. |
| `long_vsync_intervals` | vsync > 1.5 nominal periods | Counted only. Not a confirmed dropped frame. |
| `missed_slots` | round(interval / nominal) - 1, summed | Estimate of skipped slots from the vsync stream. |
| `raster_*`, `total_span_*` | `FrameTiming` | Raster and span durations. Raster includes the image acquire and fence waits inside the raster slice. GPU execution after submit is not included. |
| `phase_*` | `FramePhase` differences | Intervals between recorded timestamps only. See `glass_frame_schedule.dart`. |
| `frames_per_s` | drawn frames / measured time | Flutter frame production. Not displayed FPS. |
| `display_mode_changes` | Android report | Active-mode changes during the measured interval. Any change makes the run invalid. |

Not measured by these fields: actual panel presentation cadence. That needs
SurfaceFlinger present timestamps (see the adb steps below).

## Validity rules added

- A display-mode change between a run's measured start and end: `invalid`.
- No usable refresh rate (fallback used): `incomplete`, with the reason.

## Device checks (not run here: no adb device attached)

```
adb shell dumpsys display | grep -iE "mActiveSfDisplayMode|mActiveModeId|mAppRequestedMode|USER_SETTING|refreshRate" | head -20
adb shell dumpsys SurfaceFlinger --list | grep -i sistrum
adb shell dumpsys SurfaceFlinger --latency "<layer>"
adb logcat -d | grep -E "Impeller rendering backend|VsyncWaiter|DisplayRefresh"
```

For presentation cadence, compare the spacing of the actual-present column of
`--latency` with the vsync intervals in the report. A 120 Hz run should show
about 8.33 ms spacing in both. Where present spacing is 16.7 ms while
vsyncStart is 8.33 ms, frames are being held in the queue or pacing is slipping.
