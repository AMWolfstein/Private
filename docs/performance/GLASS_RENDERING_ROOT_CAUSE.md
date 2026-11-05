# Glass rendering root cause (developer POC)

Status: **provisional**. This report separates what the code and the recorded
benchmark numbers establish from what needs a device capture that has not been
made yet. Nothing here declares the performance problem fixed. Production UI is
unchanged and remains glass-free (see `AGENTS.md`).

Scope: the automated 60 s Scene D benchmark on `new-blur`, profile APK with
`SISTRUM_PERF_HUD=true`, Android arm64. Modes: Transparent Baseline, Basic Blur,
Old Liquid Glass, New Full Glass, New FakeGlass. Benchmark code:
`lib/widgets/glass_poc/glass_benchmark_runner.dart`,
`lib/services/performance/glass_benchmark_aggregator.dart`,
`lib/widgets/glass_poc/glass_benchmark_report.dart`.

## 1. Recorded results (single run, as reported)

| Renderer | Raster P90 | Total span P90 | Budget exceedance |
|---|---|---|---|
| Transparent Baseline | 4.82 ms | 7.47 ms | 0% |
| Old Liquid Glass | 7.25 ms | 9.52 ms | 0% |
| New Full Glass | 23.71 ms | 28.57 ms | 100% |
| New FakeGlass | 8.49 ms | 10.90 ms | 0.1% |
| Basic Blur | 6.93 ms | 9.79 ms | 0% |

Shared conditions: Scene D, four surfaces, automatic scroll at about
896.4 logical px/s, 22 boundary reversals. Every mode produced about 44.9 Flutter
frames per second (about 2694 frames over 60 s).

Earlier manual New Full Glass runs gave a Raster P90 near 10 ms. Only one
automated run per mode is on record, so no median or spread can be stated yet.

## 2. Confirmed findings

**F1. The 44.9 frames/s rate does not depend on the renderer.** Raster P90 ranges
from 4.82 ms to 23.71 ms across the five modes, yet the frame count is the same.
A rate limit that holds with a 4.8 ms raster and with a 23.7 ms raster is not
caused by rasterization. The renderer cannot explain the frame count.

**F2. The Full GPU path is only enabled in the profile build.** The profile
manifest sets `io.flutter.embedding.android.EnableFlutterGPU`. The render-path
probe (`sistrum_glass_render_path.dart`) classifies by the mounted widget tree:
`_RawShapes` means the real layer is present, and `RawFakeGlass` means the
FakeGlass fallback. A `full_gpu` result is therefore a **widget-tree
configuration check**. It shows that the package built its GPU subtree. It does
not show that Flutter GPU executed the shaders on the device.

**F3. Each Glass surface owns its own `LiquidGlassLayer`.** Four surfaces mean four
layers in New Full Glass, and each layer is a separate backdrop read and
composition. This is a structural cost that FakeGlass and Basic Blur do not pay
in the same way. The cost is not measured separately yet.

**F4. The benchmark measures the whole interval.** `GlassBenchmarkAggregator`
records every FrameTiming delivered during the 60 s Stopwatch interval, with
episodes and coverage computed over that interval. The 44.9 figure is therefore
not a rolling-window artefact.

## 3. Not established (Task 1)

**U1. Cause of the New Full Glass raster variation (10 ms against 24 ms).** Not
established. The code path was not profiled on a device. The suspects, in the
order they should be tested, are:

1. Backdrop capture and the intermediate textures for four independent layers
   (per-frame copy or allocation). Not verified against the package source in
   this report.
2. Shader pipeline compilation on the first frames of a run. This is not assumed.
   It needs a trace that separates the first seconds of a run from the steady state.
3. Thermal or clock throttling. A later run after a hot run would show it. Run
   order was not randomized.

Manual and automated runs differ in run order, warm-up and whether the HUD
overlay was in the same position, so their 10 ms vs 24 ms values cannot be
attributed to the renderer until the runs are repeated under one protocol
(Section 6).

## 4. Explanation of the 44.9 frames/second pattern (Task 2)

What is known:

- The pattern is identical across all renderers, so it sits above rendering.
- The auto-scroller (`SistrumAutoScroller`) is driven by a `Ticker`. A Ticker
  requests a frame per vsync and does not set a frame rate. It does not use
  `animateTo`, and no fixed-rate timer exists in the benchmark path. The scroller
  does not cap the frame rate.
- `frame_begin_callbacks` (persistent frame callback) and
  `frame_timings_received` (`addTimingsCallback`) are both recorded. If the two
  counts match, no FrameTiming was lost. The count from the single reported run
  was not checked against this, so it is not confirmed.

Candidate explanations, not yet distinguished:

- **C1. The panel or the vsync signal runs at about 45 Hz, not 60 Hz** (for
  example, a power or refresh-mode policy, or a reported 60 Hz that differs from
  the active mode). Then Flutter renders every vsync and the count matches the
  panel. Test: the active refresh rate during the run.
- **C2. Android presentation drops frames.** The frames are produced but not all
  presented. This is the Android display side, which Dart timings do not see.
  Test: the Perfetto FrameTimeline present timestamps.
- **C3. Flutter frame scheduling drops every few vsyncs** under load that the
  raster P90 does not show. Test: the vsyncStart interval distribution.

Dart-side measurement cannot separate C1, C2 and C3. The frame-start timestamps
are in `FrameTiming` (`FramePhase.vsyncStart`), but the benchmark does not record
their intervals yet.

## 5. Manual against automated differences (Task 3)

Checked against the code:

| Item | Manual | Automated | Status |
|---|---|---|---|
| Widget tree and surface geometry | same POC surfaces | same `SistrumGlassScene` | equal by construction, not re-verified on device |
| Glass parameters | `sistrumRendererGlassSettings` | same function | equal |
| Scrolling | user drag | `SistrumAutoScroller` Ticker | **differs** |
| Warm-up | none | 5 s active warm-up, not sampled | **differs** |
| Run order | user-chosen | fixed plan, 2 s transition between modes | **differs** |
| Background | same | same | equal |

The run order and the warm-up mean the two protocols are not identical. The
manual New Full Glass ~10 ms result cannot be compared with the automated 24 ms
until both are run under the same protocol.

No repeated measurements exist yet. No median, variability or worst-case figure
is claimed from this report.

## 6. Recommended renderer for Sistrum (provisional)

Production has no glass today, and the architecture decision requires device
data in the same scene that meets the under-3% frame-budget target before any
production glass. Against that rule:

- New Full Glass fails the budget in the recorded run (100% exceedance) and its
  variation is unexplained. It cannot be recommended.
- Old Liquid Glass and Basic Blur stayed within budget (0% exceedance) in the
  recorded run, but each run was single.
- New FakeGlass had 0.1% exceedance with raster P90 of 8.49 ms.

**Provisional recommendation:** keep production glass-free. If a renderer must
be chosen for a later decision, the current evidence favours **New FakeGlass**
over New Full Glass, because it stays within budget in the recorded run. It is not
a production choice: it needs a repeated device run before it is considered.

## 7. Smallest justified next change

One diagnostic change, no optimization and no renderer change:

1. Add the vsyncStart and rasterFinish interval histogram to the benchmark report
   (per mode), and the active display refresh rate read at the start and end of
   each mode. Record `frame_begin_callbacks` and `frame_timings_received` in the
   same line as the rate.
2. Capture a Perfetto FrameTimeline trace for the Transparent Baseline mode and
   for New Full Glass, on the same device, with the same protocol:

   ```
   adb shell cmd display get-display-modes   # active refresh rate
   adb shell perfetto -c - --txt -o /data/misc/perfetto-traces/glass.pftrace <<'EOF'
   buffers: { size_kb: 65536 }
   data_sources: { config { name: "linux.ftrace" ftrace_config { ftrace_events: "sched/sched_switch" } } }
   data_sources: { config { name: "android.surfaceflinger.frametimeline" } }
   duration_ms: 70000
   EOF
   ```

   The trace answers C1 (refresh), C2 (presentation drops) and C3 (scheduling).
3. Run each mode at least three times in a randomized order with the same
   warm-up, then report median, spread and worst case.

## 8. Open items

- U1 (Full Glass raster variation): unresolved. Needs items 2 and 3 above.
- U2 (44.9 frames/second): unresolved. Needs the refresh rate and the FrameTimeline
  trace to decide between C1, C2 and C3.
- The `full_gpu` result has not been confirmed by GPU execution. Only the widget
  configuration was checked.
