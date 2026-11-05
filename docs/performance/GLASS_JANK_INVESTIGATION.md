# Glass POC intermittent FPS drops: investigation

Status: **root cause unknown.** This document is a diagnostic record. It does
not declare the problem fixed, and it does not select a renderer.

Branch: `new-blur`. Scope: developer-only Glass POC and the independent
Performance HUD. No production UI, rendering library, or dependency was changed.

## 1. What was observed (reported, not reproduced here)

Reported on a 60 Hz Android device, Profile build with the HUD enabled:

- In all four POC modes (Old Liquid Glass, New Full Glass, New FakeGlass,
  Basic Blur), FPS sometimes fell to about 24, and frame-budget exceedance
  sometimes reached 100%.
- The degradation recovered without changing the mode.
- In stable periods, several modes reached Raster P90 below 11 ms and 0%
  exceedance.

This was not reproduced in this session. No device was available here, and the
numbers above are the user's report. They are not evidence that this
investigation produced.

## 2. Phase 1: audit of the existing measurements (code read, no change to definitions)

Each claim below was checked against the code in `lib/services/performance/`
and `lib/widgets/performance/perf_hud_overlay.dart`.

| Question | Finding |
|---|---|
| How is "FPS" calculated? | `fps_estimate` = (n - 1) / (newest raster-finish time - oldest raster-finish time) over the rolling window of the last 300 frames. It is an estimate of frame *production* from Flutter's FrameTiming. It is not Android display FPS. |
| Is the estimate stale after idle? | **Yes.** The window has no age limit. When no frames arrive, the snapshot keeps showing the last 300 frames, however old. An idle period therefore shows the last busy window, not a current value. |
| How is exceedance calculated? | Share of window frames whose `totalSpan` exceeds 1e6/hz us. `totalSpan` is vsync start to raster finish. |
| Are build and raster combined? | Not as separate numbers. `totalSpan` includes build, raster and any pipeline wait. Build and raster are reported as separate percentiles. Exceedance therefore measures frame production latency, not raster time alone. |
| Does the HUD distinguish production from display? | **No.** FrameTiming exposes raster finish, not the time the frame reached the screen. Nothing in the HUD measures presentation. |
| Does the window hide transient spikes? | **Yes.** At 60 Hz, 300 frames is 5 s. A 1 s degraded burst is about 60 frames, so its effect on exceedance and P99 is diluted by the other 240 frames. The window percentiles therefore understate a short burst. The HUD refresh (750 ms) does not drop frames; it only samples the window. |
| Do measurements include idle or stale frames? | Idle frames are included as they arrive, and nothing marks them. Stale windows persist after idle (see FPS above). |
| Do mode changes reset state? | In the POC: renderer and scene changes reset the window (`PerfFrameMonitor.reset`). In the HUD outside the POC: no reset on screen change. The window is shared across screens. |
| Does the HUD add rebuilds? | The overlay calls `setState` every 750 ms (`kPerfHudRefresh`) and sorts up to 300 frames per refresh. This is not per-frame work and cannot explain a per-frame stall, but it is a periodic raster and allocation cost. |

Corrections: none of the existing definitions were changed. The inaccuracies
above are documented, not silently fixed.

## 3. Phase 2: spike recorder (developer POC only)

`lib/services/performance/perf_spike_recorder.dart`, attached only while the Glass
POC page is open (`PerfFrameMonitor.spikeRecorder`).

- Trigger: at least 15 of the last 30 frames exceed the budget. It re-arms when
  the count falls to 3 or fewer. A spike is therefore sustained, not a single frame.
- Captured: up to 120 frames before the trigger and 120 after. Each segment has
  exceedance, build and raster P50/P90/P99, and total-span P90. Frame intervals
  are bucketed (<=17, <=25, <=34, <=50, <=100, >100 ms).
- Context, read once at the trigger: renderer, verified render path and
  fallback, scene, animation, shared backdrop, speed target, actual speed, scroll
  direction, boundary transitions in the window, and warm-up state.
- Events, bounded to 32: renderer, scene and speed changes, and app lifecycle
  (`AppLifecycleListener`). Event time is the last frame's end time.
- Bounded storage: 8 snapshots, 120 + 30 + 120 frames of preallocated buffers.
  Allocation happens at a trigger and at finish only, never per frame.
- Output: "Copy spike log" in the POC.

Not captured, and why:
- Thermal state: not exposed to Dart in this app. Not observed.
- Garbage collection and allocation pressure: not observable from Dart without
  DevTools. Not observed.
- Shader compilation and GPU resource creation: not directly observable here.
  Only the render-path probe and warm-up gating are visible.
- Display presentation: not in FrameTiming. See Phase 4.

## 4. Phase 3 (controlled comparisons) and Phase 4 (Android presentation)

**Not run in this session.** Both need the user's device. The procedure is below
so the results can be compared with the spike logs.

### 4.1 Controlled device matrix

Build: `flutter build apk --profile --target-platform android-arm64 --dart-define=SISTRUM_PERF_HUD=true`.
Same device, same scene geometry, Scene D at 900 px/s, 2 s warm-up, at least
300 counted frames per run. Repeat each run at least three times, and keep the
spike log for each.

| Run | Mode | Scene |
|---|---|---|
| A | Transparent Baseline | D, auto-scroll 900 px/s |
| B | Old Liquid Glass | D, 900 px/s |
| C | New Full Glass (check `glass_render_path=full_gpu` first) | D, 900 px/s |
| D | New FakeGlass | D, 900 px/s |
| E | Basic Blur | D, 900 px/s |
| F | each of B–E | static scene (no scroll) |

Read the results as follows:
- A spike is evidence for a cause only when it correlates with a variable that
  differs between runs. Run A has no glass. If A spikes as often as B–E, the
  cause is not in the glass path.
- Compare spike timing with `scroll_boundary_transitions` and with the
  `spike_event` lines (renderer and scene changes). Turns are counted, not
  attributed to frames.
- Do not infer causation from correlation alone (per the request).

### 4.2 Perfetto FrameTimeline capture (to separate production from presentation)

Requires an Android device with the Perfetto UI or `trace_processor`. Not run here.

1. Save this config as `frametimeline.cfg`:

   ```
   buffers { size_kb: 65536 }
   data_sources {
     config {
       name: "android.surfaceflinger.frametimeline"
     }
   }
   data_sources {
     config {
       name: "linux.process_stats"
       process_stats_config { scan_all_processes_on_start: true }
     }
   }
   duration_ms: 30000
   ```

2. `adb push frametimeline.cfg /data/misc/perfetto-configs/` then
   `adb shell perfetto -c /data/misc/perfetto-configs/frametimeline.cfg --txt -o /data/misc/perfetto-traces/glass.trace`
   (or the Perfetto UI's recording page). Start it, run the scene, then stop.
3. `adb pull /data/misc/perfetto-traces/glass.trace` and open it in
   ui.perfetto.dev. Use the *Expected/Actual Timeline* tracks for the app's
   `applicationId` (check `android/app/build.gradle`; do not assume a name). Look for "Jank" type
   labels such as *App Deadline Missed*, *SurfaceFlinger CPU Deadline Missed*
   and *Buffer Stuffing*.
4. Match the frame times to the spike log's `window_start_end_us` only as
   approximate timestamps. The clocks differ, so match by ordering, not by value.

Signals this procedure can observe: whether the app or SurfaceFlinger missed a
deadline, and whether frames were presented late. It does not observe GPU
completion directly; GPU timing is not in FrameTimeline.

## 5. Evidence status

| Class | Status |
|---|---|
| 1. Flutter-reported frame timings (build, raster, total span) | Recorded by the HUD and the spike recorder. Not reproduced here. |
| 2. Estimated FPS from Flutter frame production | Computed by `fps_estimate`. Stale after idle (see section 2). Not display FPS. |
| 3. Android display-presentation evidence | **None collected.** Requires the Perfetto procedure in section 4.2. |

## 6. Suspected causes, ranked by the evidence available

No suspect is confirmed. The ranking reflects what could be checked, not
what was proven.

1. **Measurement artifact, partly confirmed by code.** The window is 300 frames
   with no age limit, and the FPS estimate is not time-bounded. A stale window
   can show a low FPS or 100% exceedance after a busy period. This explains
   some reported readings, but not a sustained drop observed during an active run.
2. **Per-frame work outside the glass path, not yet checked.** Build time spikes
   (not raster) would point to Dart work on the UI thread: allocation, rebuilds, or
   GC. The spike logs separate build and raster, so this can be checked on the device.
3. **Shader or GPU resource initialization inside a run.** New Full Glass loads its
   GPU geometry asynchronously. The probe waits for `full_gpu` before measuring,
   so warm-up excludes it, but Old Liquid Glass and Basic Blur have no equivalent gate.
4. **Android presentation or thermal throttling.** Plausible for periodic drops that
   recover on their own, but no evidence was collected. Requires section 4.2.
5. **Scroll boundary reversal.** Reversal is a direction change, not a jump, so it
   is an unlikely cause. The turn count is recorded per spike to test this.

## 7. Reproduction steps

1. Install the profile APK built with `SISTRUM_PERF_HUD=true`.
2. Developer Options > Glass POC. Select the mode, then Scene D, then Fast (900 px/s).
3. Let it run for at least 60 s, then tap Copy spike log, and separately Copy metrics.
4. Repeat for each mode in section 4.1, three times each.
5. Note the wall-clock time of any visible drop, and compare it with the spike
   `wall_clock`.

## 8. Captured spike examples

None captured in this session. The recorder is in the APK, but no device run
was performed here. An example will be added here only from a real device log.

## 9. Recommended next experiment

The smallest test that separates the suspects above:

1. Run section 4.1 run A (no glass) and run C (New Full Glass), three times each,
   at 900 px/s, and copy the spike logs.
2. Run section 4.2 Perfetto on one run of C.
3. If spikes occur in A as often as in C, the cause is outside the glass path.
   The next step is then Perfetto alone, with thermal and CPU frequency tracks added.
4. If spikes occur only in the glass modes, compare `spike_pre`/`spike_post`
   build and raster P90 to see which thread moved.

## 10. Conclusion

- **Root cause: unknown.** No device capture was made in this session, so no
  cause is confirmed.
- **Narrowed:** the HUD's FPS estimate and window are not reliable across idle
  periods (confirmed from code). The spike recorder and Perfetto procedure are
  in place to test the remaining suspects.
- **Not fixed.** No optimization was made, and none is claimed. A single stable
  300-frame window is not evidence of resolution.
