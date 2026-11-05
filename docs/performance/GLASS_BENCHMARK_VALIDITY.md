# Glass benchmark validity: audit of the first automated run

Branch `new-blur`. Scope: the developer-only Glass POC benchmark. No Glass library
and no production UI was changed.

This document records what the first 60-second automated run could and could not
show, the root causes found in the code, and the fixes. It does **not** contain new
performance results: the benchmark has not been repeated on a device, and no
renderer decision is made here.

## 1. The first report's inconsistencies

| Observation | Cause (verified in code) |
|---|---|
| `scroll_speed_actual=n/a`, `scroll_direction_at_end=stopped`, `scroll_boundary_reversals=0` in every mode | **Measured, then erased.** `_finishMode` called `host.haltRun()` before `_result()` read the scroller. `halt()` runs `_clearRun()`, which zeroes the path, the measured seconds and the turn count. The report therefore read the cleared state. The run's scrolling was **never recorded**, so the first report cannot prove whether the list moved. |
| No sustained-degradation episodes at 100% exceedance | **Episode lost at the end.** `_finishMode` built the summary **before** `_aggregator.end()`. An episode still open at the end is only closed by `end()`, so it was never in the summary. The same ordering existed in `interrupt()`. |
| ~2694 frames over 60 s (44.9/s) in every mode, including Transparent Baseline | **Not explained by the report.** The report counted FrameTiming callbacks only. It had no independent count of drawn frames, so it could not show whether timings were lost or frames were not drawn. See section 3. |
| Raster P90 about 23 ms for Glass modes | **Not established.** See section 4. |

## 2. Task A: scroll workload verification

Recorded now, during the run (the scroller's own counters, read **before** halt):

- `measuredPathPx`: total displacement applied since measurement started.
- `measuredSeconds` and `activeFraction`: active scrolling seconds over the
  Stopwatch time of the interval. Below 95% is INVALID.
- `measureTicks`: scroll frames received while measuring. Zero is INVALID.
- `unattachedTicks`: frames where no list position was attached. Any is INVALID.
- `maxTickGapSeconds`: the longest time between two scroll frames. Above 0.5 s is INVALID.
- `overallPxPerSecond`: displacement over the whole interval. Outside ±5% of
  900 px/s is INVALID.
- `totalBoundaryTurns`, `direction`: reported, not validated.

A run is VALID only if every rule above holds, not because its timer completed.
The `scroll_*` lines in the report show each value per mode.

Tests (`glass_benchmark_runner_test.dart`, `auto_scroll_test.dart`):
- scroll metrics captured during the run survive the halt that follows it;
- a run whose list never scrolled is INVALID;
- a run at the wrong speed is INVALID;
- a scroll stop or a detached list is INVALID;
- measured distance equals the applied displacement; detached ticks and tick gaps are counted.

## 3. Task B: frame accounting

The frame counts come from `PerfFrameMonitor`:

- One `addTimingsCallback` registration, added by `start()` and removed by `stop()`.
  Nothing is registered per run. Each `FrameTiming` is counted once.
- Timings are counted into the aggregator only while collection is on (the warm-up
  is excluded).
- The benchmark timer is a `Stopwatch` (monotonic), not a frame count.
- **New:** a persistent frame callback counts every drawn frame, independently of
  FrameTiming delivery. Each mode's report lists `frame_begin_callbacks` (drawn) and
  `frame_timings_received` (timings). The run is INCOMPLETE if drawn frames exceed
  timings by more than the larger of 2 frames or 2%, because some timings never arrived.
- The benchmark's own UI updates: one progress notification per second drives a
  single status line, and the measured stage is not rebuilt. That is a few hundred
  microseconds per second. It cannot explain 44.9 frames per second.

What is **not** established: whether the engine drew 44.9 frames per second because
the device or the pipeline limited it, or because the workload did. The first report
cannot tell these apart. The new counters can: if drawn frames and timings agree at
about 2,694 and the reported refresh rate is 60 Hz, the rate is a production limit,
not lost timings. Do not read 44.9 as display FPS.

## 4. Task C: episode detection

Threshold logic: at least 15 of the last 30 frames over budget starts an episode;
it ends at 3 or fewer. Verified by the aggregator's tests, which include an
episode with 40 consecutive over-budget frames.

The defect was ordering, not the threshold (section 1). Fixes:
- `_finishMode` and `interrupt` now close the aggregator (`end()`), then build the
  summary. An open episode is finalized as `open_at_end=true`.
- Each mode starts a fresh aggregator interval (`begin()`), and the previous mode's
  open episode is never carried over (`discard()` before a new run).
- Frames past the buffer are counted as overflow and the run is INCOMPLETE.

Regression test: a sustained 100% over-budget run that is still open at the end
records exactly one episode, marked `open_at_end`, and it appears in the report
(`runner` test: "...still open at the end records an episode").

## 5. Task D: manual versus automated Scene D

Workload path, compared in code:

| Aspect | Manual Scene D | Automated Scene D |
|---|---|---|
| Scene and surfaces | `SistrumGlassScene.scrollingContent`, four surfaces | same provider and widget tree |
| Scroll start | `_applyScene` -> `_beginScrollRun` | `applyRun` -> `_applyScene` -> `_beginScrollRun` (same method) |
| Speed | user's choice (Normal by default) | Fast (900) set by `setSpeed` |
| Background animation | off in Scene D | off (`applyRun` uses Scene D) |
| Shared backdrop | user's switch | forced off |
| Warm-up | 2 s | 5 s, from the plan |
| Measurement | the HUD's 300-frame **rolling** window, read at a moment | the **whole 60 s** interval (aggregated) |
| Instrumentation attached | HUD only | HUD plus aggregator plus persistent frame callback plus per-second progress |
| Mode sequence | one mode at a time, by hand | five modes in one session, with transitions |

Conclusions that the code supports:
- The scene, the widget tree and the scroll start path are the same.
- The two numbers do not measure the same thing. A 300-frame window at one moment
  is not comparable with a 60-second aggregate that includes every episode. The
  manual 9-10 ms number cannot be compared directly with 23 ms.
- The Transparent Baseline in the automated run also reports about 44.9 frames per
  second. A cost that the Glass libraries add cannot make the baseline slower, so
  the shared factor is not in the Glass path. This is evidence, not proof: the
  manual baseline was never measured over 60 s.

Not concluded: any Flutter Engine bug. The workload is not yet shown equivalent,
because the first run's scroll evidence was erased (section 1).

## 6. Next steps (in this order)

1. Install the profile APK built from this commit (section 7).
2. Run the 60-second benchmark once. Check that every mode shows `scroll_speed_actual`
   near 900, `scroll_active_fraction_pct` near 100, `scroll_frames` in the thousands,
   and `frame_begin_callbacks` close to `frame_timings_received`. Any mode failing
   those is INVALID and must not be compared.
3. If the scroll checks pass but raster is still high, record a Perfetto FrameTimeline
   trace for the Transparent Baseline run (`GLASS_JANK_INVESTIGATION.md`, section 4.2).
   Compare the baseline's FrameTimeline with its own manual run before attributing
   anything to a Glass renderer.
4. Only then repeat the full benchmark for all five modes.

## 7. Verification status

- `flutter analyze`: No issues found (before this document).
- `flutter test`: see the commit message and the summary delivered with the APK.
- The benchmark was **not** rerun. No renderer conclusion is drawn from the first run.
