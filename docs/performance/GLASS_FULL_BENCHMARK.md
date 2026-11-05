# Glass POC: automated 60-second benchmark

Developer-only. Developer Options > Glass POC > **Run Full Benchmark**. It runs
five modes in order, each in Scene D (four glass surfaces, scrolling, 900 logical
px/s, reverse at each end, animated background off, shared backdrop off), and
writes one plain-text report. Production UI is not touched.

## How to run

1. Install the profile APK built with `SISTRUM_PERF_HUD=true`.
2. Open Developer Options > Glass POC.
3. Tap **Run Full Benchmark**. Leave the device untouched. The status line shows
   the mode, phase and measured time. The mode and scene chips are disabled while it runs.
4. When it finishes, the report opens. Tap **Copy Report** (in the dialog, or the
   Copy Report control in the POC controls). The copied text is the complete report.

Expected duration: five runs of about 2 s transition, 5 s warm-up and 60 s measured
interval, about six minutes in total.

## Run order and plan

Transparent Baseline, Old Liquid Glass, New Full Glass, New FakeGlass, Basic Blur.
Each mode uses the same geometry, content, speed and direction. Runs never
overlap. Warm-up frames are excluded. The measured interval is timed by the
monotonic Stopwatch, not by a frame count.

## State machine

`idle -> transition -> warmup -> measuring -> transition ... -> complete`

- **failed**: an exception in the run (for example, the page could not apply a
  mode). The configuration is still restored.
- **cancelled**: the app left the foreground (any lifecycle state other than
  resumed), the page was closed, or **Cancel benchmark** was tapped. The run keeps
  its partial data and does not resume.

Each run waits up to 30 s to start measuring. Measurement needs a verified render
path. New Full Glass must show `full_gpu` before measuring, so FakeGlass during GPU
initialization is never measured as Full Glass. A run that never starts is invalid,
and the next run starts.

When the run ends, the POC's mode, scene, shared backdrop and speed are restored.

## Measurement

- **Source**: every FrameTiming callback during the measured interval. No rolling
  300-frame window. Frames are stored in a buffer of 16,384 per run (at 120 Hz, a
  60 s run needs about 7,200). Frames past the buffer are counted as overflow, and
  the run is marked incomplete.
- **Build, Raster, Total span**: Flutter FrameTiming values, reported separately.
  Total span is vsync start to raster finish, and it is what exceedance counts.
- **Frame-budget exceedance**: percentage of frames whose total span exceeds
  1e6/hz us. Unchanged from the HUD definition.
- **Estimated frame production rate**: (frames - 1) over observed time, from
  Flutter callbacks. It is an estimate, not display FPS.
- **Frame gaps**: an interval between consecutive frame ends longer than two budgets.
  Gaps are counted and timed, and they lower coverage. A stall with no callbacks is
  reported as a gap, not as 60 FPS.
- **Coverage**: (observed time minus gap time) over the Stopwatch elapsed time.
  A run below 90% coverage is incomplete.
- **Scroll speed (actual)**: displacement of the list's applied offset over the
  whole measured interval, divided by the measured seconds. Never the target.
- **Boundary reversals**: counted over the whole interval, and counted inside each
  episode.
- **Sustained episodes**: at least 15 of the last 30 frames over budget starts an
  episode. It ends when the count falls to 3 or fewer. The worst five per renderer
  are kept, longest first (ties by larger max span). An episode open when the run
  ends is marked `open_at_end`.
- **Render path**: probed every second during the run from the widget tree. A mode
  is valid only if every sample matched its expected path, with no fallback seen.
  Old Liquid Glass and Reference Glass are not instrumented, so they are reported as
  `validity=VALID (render path unverified)`.

## Validity

- **VALID**: frames observed, path matched, coverage complete.
- **VALID (render path unverified)**: as above, for a mode the probe cannot verify.
- **INCOMPLETE**: overflow, or coverage below 90%.
- **INVALID**: no frames, a path mismatch or fallback, or measurement never started.
- **CANCELLED**: stopped before the run finished (partial data kept).
- **NOT RUN**: not reached because the benchmark stopped first.

## Report

Sections: 1 device and configuration; 2 validity and interruptions; 3 summary
comparison (one row per mode); 4 detailed metrics; 5 worst five episodes per
renderer; 6 diagnostic notes and limitations. The report never declares a winner.
P50 alone does not decide a renderer.

Device model is **not** read. Dart cannot see it without a native channel, and this
task did not add one to production code. Rendering backend is not verifiable from
Dart, so the report shows `shader_filters_supported` instead.

## Limitations

- Flutter FrameTiming does not measure displayed (presented) frames. Android
  presentation can be late or dropped without any change in these numbers. A
  Perfetto FrameTimeline capture is needed for that (see `GLASS_JANK_INVESTIGATION.md`,
  section 4.2).
- Root cause is not determined by this instrument. Every episode is `cause=unverified`.
- Boundary reversals are counted per episode and per run, not per frame.
- The render path is inferred from widget type names. A `--obfuscate` build may
  report `unverified` rather than guess.
- Frame timing is taken from the POC page's own monitor. The HUD does not need to
  be enabled, but the APK must be a profile build for numbers to mean anything.
- Thermal state and garbage collection are not observed.

## Tests

- `test/services/performance/glass_benchmark_aggregator_test.dart`: interval
  exclusion, percentiles and exceedance, production-rate label, stall and coverage,
  worst-five ordering, open episodes, boundary attribution, overflow, clean restart,
  empty interval.
- `test/widgets/glass_poc/glass_benchmark_runner_test.dart`: full run, no overlap,
  cancellation with partial data and no resume, timeout, Full Glass fallback marked
  invalid, failure with restore, dispose mid-run.
- `test/widgets/glass_poc/glass_benchmark_report_test.dart`: sections, measured
  values, unverified causes, no winner, cancelled report, complete copied text.
- `test/screens/settings/developer/glass_poc_benchmark_test.dart`: the page run
  end to end with a short plan: controls disabled, configuration restored, report
  dialog, Copy Report copies the full text.
- `test/widgets/glass_poc/auto_scroll_test.dart`: whole-interval speed and turns,
  configurable warm-up.
