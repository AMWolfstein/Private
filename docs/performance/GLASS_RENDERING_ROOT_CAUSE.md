# Glass rendering root cause (developer POC)

Status: **open**. The instrumentation and the repeatability protocol are in
place (commit `5483fa3`). The device runs that would answer the open questions
have **not** been made from this environment, so no new performance result is
claimed here. Production UI is unchanged and remains glass-free (see
`AGENTS.md`). Nothing in this document declares the Glass engine fixed.

Scope of the earlier evidence: one automated 60 s Scene D run per renderer on
`new-blur`, profile APK with `SISTRUM_PERF_HUD=true`, Android arm64.

## 1. Recorded single-run results (unchanged)

| Renderer | Raster P90 | Total span P90 | Budget exceedance |
|---|---|---|---|
| Transparent Baseline | 4.82 ms | 7.47 ms | 0% |
| Old Liquid Glass | 7.25 ms | 9.52 ms | 0% |
| New Full Glass (4 surfaces) | 23.71 ms | 28.57 ms | 100% |
| New FakeGlass | 8.49 ms | 10.90 ms | 0.1% |
| Basic Blur | 6.93 ms | 9.79 ms | 0% |

All five modes produced about 44.9 frames per second, about 2694 frames over
60 s. Earlier manual New Full Glass runs gave a raster P90 near 10 ms. Each mode
has one automated run, so no median or spread can be stated.

## 2. Confirmed findings

**F1. The frame count does not depend on the renderer.** Raster P90 ranges from
4.82 ms to 23.71 ms, yet every mode produced the same frame count. Rasterization
cost cannot explain that count.

**F2. The `full_gpu` result is a widget-tree check, not GPU execution.** The
render-path probe (`sistrum_glass_render_path.dart`) classifies by the mounted
tree: `_RawShapes` is the real layer, `RawFakeGlass` is FakeGlass. The profile
manifest enables `io.flutter.embedding.android.EnableFlutterGPU`. Whether the
shaders ran on the device is not verified.

**F3. Each glass surface owns its own `LiquidGlassLayer`.** Four surfaces mean
four separate layers in New Full Glass. The per-layer cost is not measured yet.

**F4. The benchmark measures the whole interval.** `GlassBenchmarkAggregator`
records every FrameTiming during the 60 s Stopwatch interval. The 44.9 figure is
not a rolling-window artefact.

## 3. Correction to the earlier manual/automatic comparison (Task 3)

The earlier report said the manual measurements used user dragging. That is
wrong, and the implementation shows why:

- **"Manual" meant manual selection.** The user chose the renderer, scene and
  speed in the Glass POC page. The benchmark itself was never dragged by hand.
- **The scroll was the automatic scroller.** The earlier HUD captures recorded
  `scroll_mode=auto`, `scroll_speed_preset=fast` and `scroll_speed_actual≈897
  logical_px_per_second`. `SistrumAutoScroller` (a `Ticker`, no `animateTo`)
  drives that scroll; a finger does not.
- **Not every earlier test is covered by this correction.** Only the captures
  whose HUD lines are on record are known to be auto-scrolled. Any earlier run
  without those lines is not classified here.

So the manual and automated runs compared earlier differed in run order,
warm-up, and whether the same protocol and validity rules applied. They did not
differ in how the list moved.

## 4. Instrumentation added (Task 1)

`GlassFrameScheduleRecorder` (`lib/services/performance/glass_frame_schedule.dart`)
records four series for each measured interval, in bounded buffers with no
per-frame allocation. Each series names its clock:

| Series | Event or delivery | Clock |
|---|---|---|
| `vsync_start_interval_ms` | event (`FrameTiming.vsyncStart`) | engine |
| `raster_finish_interval_ms` | event (`FramePhase.rasterFinish`) | engine |
| `frame_begin_interval_ms` | delivery (persistent frame callback) | Dart Stopwatch |
| `frame_timing_arrival_interval_ms` | delivery (`addTimingsCallback` batch) | Dart Stopwatch |

Engine and delivery intervals are never subtracted from each other. Two engine
series are event timestamps. Two Stopwatch series are the times Dart saw the
callback, not the time the frame was scheduled.

Also recorded per run: `frame_begin_events` (drawn frames),
`timing_batches` and `timings` (FrameTiming received), `long_vsync_intervals`
(engine vsync interval over 1.5 nominal periods), and `missed_slots` (nominal
periods skipped by vsync intervals, a 2-period gap counts 1).

**What this does and does not show.** The implied refresh from the median vsync
interval is evidence about the vsync cadence only. It is not the display's
measured frame rate, and the report does not present it as one.

**Refresh rates.** The requested refresh rate is **not** available from Dart.
The reported rate comes from `FlutterView.display.refreshRate`, which is the
observed value. Reading the window's preferred mode needs a native channel, and
none was added (see section 7 for the adb command that reads it without code).

**Thermal state.** Not accessible from Dart. See section 7.

## 5. Layer-count experiment and repeatability (Tasks 2, 4, 5)

Implemented in the developer POC only:

- **Surface counts.** Scene D's four surfaces are the header back button, the
  header capsule, the mini player and the tab bar. The experiment uses
  - 1 surface: mini player only;
  - 2 surfaces: mini player and tab bar;
  - 4 surfaces: all four (the standard Scene D layout).
  Surfaces are counted by the same render-path probe as before, so a missing or
  extra layer makes the run invalid.
- **Unavoidable differences.** The 1, 2 and 4 configurations do not have the same
  glass-covered area. Stepping from 2 to 4 also adds the two header controls. So
  the scaling result is layer count together with covered pixels. A
  same-area control (one large layer against four small ones of equal total
  area) is needed to separate them, and it is not in this change.
- **Protocol.** Diagnostic plan: Transparent Baseline; New Full Glass at 1, 2
  and 4 surfaces; Old Liquid Glass at 4; New FakeGlass at 4; Basic Blur optional.
  Three repeats, counterbalanced: each round rotates the configuration list and
  odd rounds run it backwards. The executed order is recorded per run. Each run
  keeps the standard timing (2 s transition, 5 s warm-up, 60 s measured, Ticker
  scroll at 900 px/s). The standard 60 s protocol is unchanged.
- **No retries.** An invalid, incomplete or cancelled run stays in the report,
  is excluded from every statistic, and is never replaced.
- **Report.** `formatGlassDiagnosticReport`: device and clocks; executed order
  and validity; VSync and frame production per run; per-run raster and span
  P50/P90/P99 and exceedance; repeatability (median, min, max, range, CV) per
  configuration; New Full Glass scaling with a repeat-separation check; frame-rate
  evidence; conclusions; open questions.

**Status: not yet run on a device.** The layer-scaling values, the repeatability
statistics and the 44.9 frames/s evidence are **not measured** by this change.
The profile APK is built with the protocol, but the numbers come from running
it on the device (section 7).

## 6. Hypotheses for the 44.9 frames/s pattern

Confirmed: the rate is identical across renderers (F1).

Plausible, not yet tested:

- **H1. The panel or its refresh policy runs near 45 Hz.** The engine would then
  deliver vsync at about 22 ms, and frames would match the vsync cadence. Test:
  the vsync interval P50 and the adb refresh query (section 7). If the vsync
  interval is about 22 ms, H1 is supported and H2 is not needed.
- **H2. Flutter drops every few vsync slots.** The vsync cadence is 60 Hz, but
  frames are not produced on some slots. Test: `missed_slots` and
  `frames_per_s` in the diagnostic report.
- **H3. Android drops frames after raster.** Frames are produced but not all
  presented. Dart timings cannot see this. Test: the FrameTimeline trace in
  section 7.

The diagnostic report's conclusions section applies these tests mechanically
and labels each candidate as evidence, not as a cause.

## 7. Device-side verification (no Dart evidence is enough for these)

Run each command on the device with USB debugging on, the profile APK installed,
and the device left in the same state for every run.

**Refresh rate (requested and observed).**

```
adb shell dumpsys display | grep -iE "mRefreshRate|preferredRefreshRate|refreshRate" | head -20
adb shell dumpsys SurfaceFlinger --display-id 2>/dev/null | head -40
```

Record the active mode and the preferred mode. A difference between them is
evidence for H1.

**Thermal state, before and after each run.**

```
adb shell dumpsys thermalservice | head -30
```

Record the `Thermal Status` value. Record the time of each run as well, so a
thermal change can be matched to a run.

**FrameTimeline trace.** Capture a system trace of the Transparent Baseline
run and of a New Full Glass run, both at 4 surfaces, using the same device state.
The FrameTimeline track lists the presentation time of each frame, which tests
H3. Use Android Studio's System Trace or Perfetto's `record_android_trace` with
the `frametimeline` and `sched` data sources, then open the trace in
ui.perfetto.dev. The inline `perfetto -c -` configuration written in an earlier
revision of this document was not run and is not recommended.

**Protocol for the diagnostic runs.** Use `Run Diagnostic Repeats` in the POC
page, then `Copy Diagnostic Report`. Keep the device on the charger, screen on,
no other apps in the foreground, and do not touch the screen during a run.
Record the adb refresh query and the thermal status before the first run and
after the last one.

## 8. Open questions

1. The requested and observed display refresh rate during each run (section 7).
2. Whether the 44.9 frames/s pattern comes from the vsync cadence (H1), the
   frame scheduling (H2) or the presentation (H3). The FrameTimeline trace and
   the repeat-run vsync data decide between them.
3. Whether the New Full Glass raster cost (10 ms in one manual run, 24 ms in the
   automated run) is repeatable. The three diagnostic repeats decide that.
4. Whether layer count or covered area drives the scaling. Needs a same-area
   control, which is not implemented.
5. Whether `full_gpu` executes the shaders on the device. Only the widget tree is
   checked.
6. Thermal state during the runs (section 7).

## 9. Renderer recommendation

Production has no glass, and the architecture decision requires device
measurements in the same scene that meet the under-3% frame-budget target before
any production glass. Nothing in this document changes that.

From the single earlier run only: New Full Glass exceeded the budget in every
frame (100%) and its raster variation is unexplained. Old Liquid Glass and Basic
Blur stayed within budget. New FakeGlass had 0.1% exceedance. None of this is
repeated yet, so no renderer is recommended from it.
