# New Full Glass — Shared Backdrop POC

Status: **NOT DEVICE-VERIFIED. Keep as a developer-only experiment, not a
performance improvement or production recommendation.** No APK was built here;
the owner will build it. No shader, package source, dependency declaration,
lockfile, production UI, or Android refresh-rate policy was changed.

## 1. Files changed

- `lib/widgets/glass_poc/app_glass_backdrop_plan.dart`: conservative paint-order
  planner for explicit backdrop keys.
- `sistrum_glass_mode.dart`, `sistrum_glass_surface.dart`, and
  `sistrum_renderer_glass.dart` in the same directory: append the experimental
  mode and forward its key to the existing package's `withOwnLayer` constructor.
- `sistrum_glass_render_path.dart`: require the same four real GPU layers and
  reject FakeGlass fallback for the new Full Glass mode.
- `glass_benchmark_run.dart`, `glass_benchmark_runner.dart`, and
  `glass_benchmark_report.dart`: separate repeated A/B protocol, topology and
  geometry reporting, invalidation on changes, and explicit unverified status.
- `lib/screens/settings/developer/glass_poc_page.dart`: developer-only mode,
  `Run Shared Backdrop A/B`, and scene-specific assignment of persistent keys.
- `lib/providers/performance/glass_poc_mode_provider.dart`: label the new request
  separately from the existing Reference Glass comparison switch.
- Focused tests in `test/widgets/glass_poc/`: region safety, counterbalancing,
  path/fallback classification, reporting, and transient-layout invalidation.

The existing five-mode benchmark and six existing renderers remain available.

## 2. Exact architecture

The source pin remains `liquid_glass_renderer: 1.0.0-dev.2` and Flutter remains
3.47.7. The package's `LiquidGlass.withOwnLayer` accepts `backdropKey` and
`useBackdropGroup`; an explicit key takes precedence over an ancestor group.
Flutter's `BackdropKey` identifies the shared filter input. It is not permission
to merge overlapping filters or change their optical shader.

Both A and B retain four independent package layers, the same superellipse
shapes, iOS 27 regular light/dark settings, `fake: false`, foreground content,
positions, dimensions, and scrolling. A continues to pass no backdrop key.
B passes stable, explicit keys computed for this developer scene. No shared
geometry layer, custom shader, custom capture loop, or bounded capture is added.

Paint order is back button, trailing header capsule, mini-player, then tab bar.
The background painter and scrolling list are painted before all four. There is
no other interleaved content in this scene. The planner is specific to that
contract; new interleaved content must be included in its bounds or isolated.

For each surface in paint order, reuse a group's capture only if its sampling
rectangle misses **every** surface/foreground painted since the group's first
member, including members of other groups. Otherwise use another key. This
preserves the previously painted input conservatively instead of assuming all
four visible silhouettes are independent.

Sampling rectangles include conservative bounds for the pinned material:

- contour/antialias outsets;
- three blur sigmas and a physical-pixel allowance;
- peak refraction displacement including dispersion;
- content revealed by backdrop shrink.

The package's default/preset frost can grow by at most 1.78 and has a
5.8-device-pixel downsampling floor. The planner bounds this through public
settings, without calling package members marked `@internal`. These bounds are
specific to the pinned version and must be reviewed when upgrading it. All
foregrounds fit within the supplied surface bounds; the adapter requests no
exterior shadows. The planner accounts for RTL header placement.

## 3. Which surfaces share and why

There is deliberately no unconditional four-surface key. Wide-separated header
controls can share when the later capsule's sampling region excludes the back
button. The mini-player can reuse that input only if its sampling region also
misses both earlier header surfaces. On a roomy stage an assignment can be
`groups=0,0,0,1` for `roles=back,trailing,mini,tab`.

The actual assignment depends on stage dimensions, DPR, and settings, not the
example above. Each run records `backdrop_configuration`, including assignments,
stage size, DPR, direction, and brightness. Compare reports using the same stage
geometry and settings. A transient layout/assignment change invalidates the run,
even if the old configuration returns before the next one-second sample.

## 4. Which surfaces remain independent and why

The mini-player and tab bar have only a 10-logical-pixel gap. Blur/refraction
sampling support can cross that gap even though their silhouettes do not
overlap, so the later tab bar generally cannot reuse the mini-player's earlier
input. Short stages can similarly require the mini-player to retain the earlier
header output. Narrow header layouts can require another independent key.

Any overlapping/nested or otherwise incompatible sampling region remains
independent. If the guard assigns four different keys, that run is a valid
guarded configuration but **does not exercise reduced input sharing**; do not
report it as a successful sharing optimization.

## 5. Visual parity

**NOT DEVICE-VERIFIED.** Region safety and configuration tests do not establish
pixel equivalence of the compositor, live refraction, or temporal correctness.
Ordinary host widget tests may use FakeGlass and must never count as Full Glass
optical validation. The package's requested path is not presentation evidence.

Before accepting B, use a profile build on the physical phone:

1. Keep brightness/theme, orientation, stage dimensions, system text scale,
   scene, and refresh selection identical for A and B.
2. In Scene D choose the same speed (900 logical px/s) and reset before each
   capture. Compare **equal scroll offsets**, not just equal wall-clock times.
   For fixed captures, pause auto-scroll and manually align the same text row
   using the same surface edges as landmarks. This is a manual device check,
   not a pixel-golden result generated by this change.
3. Check static captures and moving recordings at corners and edges for missing
   or stale content, distortion, seams, blur/tint differences, and ordering.
4. Include light/dark and RTL. Test short/narrow layouts where regions overlap;
   confirm the report's groups split and the ordering matches A.
5. Check the render path is `full_gpu`, with no fallback, before comparing.

The existing Scene D is text over a deterministic painted pattern. It does not
prove scrolling album-artwork parity. A separately controlled artwork workload
is still needed before making a broader product-quality claim. This experiment
does not change the historical workload to obtain more favorable numbers.

If visual parity fails, the experiment is unsuccessful regardless of timing.

## 6. Benchmark comparison

No performance measurements were collected for this POC. Do not substitute old
independent-renderer results for missing shared-backdrop measurements.

| Refresh | Configuration | Build P50/P90/P99 | Raster P50/P90/P99 | Span P50/P90/P99 | Queue delay | Engine cadence | Flutter production | Android presentation |
|---|---|---|---|---|---|---|---|---|
| 60 Hz | Transparent Baseline | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured |
| 60 Hz | New Full Glass — Current | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured |
| 60 Hz | New Full Glass — Shared Backdrop | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured |
| 120 Hz | Transparent Baseline | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured |
| 120 Hz | New Full Glass — Current | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured |
| 120 Hz | New Full Glass — Shared Backdrop | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured | Not measured |

Budget exceedance, coverage, sustained degradation, active Android mode, and
effective render path/fallback are likewise not device-measured here. The
existing report carries these fields when the experiment runs.

### Exact device procedure

The owner builds and installs a **profile** APK with `SISTRUM_PERF_HUD=true`.
The existing profile manifest enables Flutter GPU; do not change release flags
or shaders for this experiment. Prepare the repository's locked dependencies
and required SDK semantics backport in the owner's build environment.

1. Open Developer Options > Glass POC.
2. Select 60 Hz through the app's existing Appearance refresh preference. Do not
   change global Android refresh settings. Confirm Android reports the requested
   active mode and power saver is off; wait for the mode to settle.
3. Start **Run Shared Backdrop A/B**. It fixes Scene D, four surfaces, 900
   logical px/s, no animated background, 5 s warmup and 60 s measurement.
4. Let all 18 runs complete: six rounds, approximately 20 minutes total with
   2-second transitions. Orders are `ABC, BCA, CAB, CBA, ACB, BAC` where A is
   baseline, B current Full Glass, C shared Full Glass. Each configuration
   occupies each ordinal position twice; within-round directed neighbor pairs
   are balanced. Cross-round boundaries are separated by transitions and warmup.
5. Copy Shared Backdrop Report. Preserve raw reports and device/build metadata,
   thermal/power conditions, and all invalid/incomplete outcomes.
6. Repeat at 120 Hz through the app setting, after thermal recovery. Confirm
   active mode and budget: 60 Hz about 16.67 ms, 120 Hz about 8.33 ms. Never
   replace nominal 120 Hz with observed 60 Hz cadence to make exceedance vanish.
7. Compare valid repeat distributions and repeat variability, not just one
   percentile or a fixed-order first run. Reject mixed stage dimensions,
   assignment changes, mode changes, fallback, inadequate frame coverage, or
   failed scrolling validity. A sharing request with no actual sharing is not
   evidence about the optimization.

The current benchmark already prefers Android's active mode through
`nominalDisplayRefresh`; Flutter-reported refresh, engine VSync, callback-derived
production and physical presentation remain separate. The HUD budget regression
test covers 120 Hz/8.33 ms and 60 Hz/16.67 ms. The metric calculations were not
changed for this experiment.

### Presentation and trace collection

On a connected device, collect metadata without changing display policy:

```bash
adb shell dumpsys display > display.txt
adb shell dumpsys SurfaceFlinger --list > surface-layers.txt
# Identify the actual Sistrum layer from the list, then use its exact name:
adb shell dumpsys SurfaceFlinger --latency '<actual Sistrum layer>' > presentation.txt
```

SurfaceFlinger latency output is a bounded recent history, not a complete
60-second capture. Preserve its header/rate and actual presentation timestamps;
use periodic collection with de-duplication or a FrameTimeline trace for a full
interval. Do not calculate a 60-second FPS from a single short ring buffer.

Use Android Studio System Trace or Perfetto to capture Android FrameTimeline,
thread scheduling and graphics work. Include baseline, current and shared under
the same tracing conditions. Record trace boundaries against benchmark phases
and check buffer loss. Example for a roughly four-minute capture of the first
three runs (start the benchmark promptly after starting the trace in another
terminal):

```bash
adb shell perfetto --txt -c - \
  -o /data/misc/perfetto-traces/sistrum-glass.pftrace <<'EOF'
buffers { size_kb: 65536 fill_policy: DISCARD }
duration_ms: 240000
data_sources { config { name: "android.surfaceflinger.frametimeline" } }
data_sources { config {
  name: "linux.ftrace"
  ftrace_config {
    ftrace_events: "sched/sched_switch"
    ftrace_events: "sched/sched_wakeup"
    ftrace_events: "power/cpu_frequency"
    atrace_categories: "gfx"
    atrace_categories: "view"
    atrace_apps: "com.amwolfstein.sistrum"
  }
} }
EOF
adb pull /data/misc/perfetto-traces/sistrum-glass.pftrace
```

Verify the installed application ID/layer; side-by-side builds can differ.
Supported trace sources and graphics counters vary by device. Increase buffers
or narrow sources if loss occurs. This example does not trace all 18 runs;
capture additional rounds if needed to establish repeatable presentation
behavior. Keep traced and untraced results labeled separately.

Inspect actual versus expected presentation, CPU/raster scheduling, image
acquisition/fence waits and GPU work where supported. Raster duration is not
pure GPU execution, and build-to-raster delay alone does not prove GPU
saturation. No Perfetto or SurfaceFlinger findings are claimed here.

## 7. Actual verification status

- ADB outside the command sandbox: **no devices attached**.
- `dart format`: passed for changed Dart files.
- Full-project `flutter analyze --no-pub`: failed because the retained package
  configuration belongs to the old checkout (`spotiflac_android`) and does not
  resolve `sistrum` or either pinned glass dependency. Its unresolved-import
  cascade is not a clean analysis result for this branch.
- The SDK preparation check reports the repository-required semantics patch is
  missing. No third-party/SDK source was modified in this task.
- A temporary `/tmp` harness uses exact copies of the relevant source/tests and
  only already cached packages, with a corrected project-name mapping. It is
  not a restoration of the current lockfile and does not validate the renderer
  package or developer-page integration. No dependencies were installed.
- Isolated host tests: **68 passed**, covering the region planner, A/B protocol,
  fallback classification, report, runner invalidation, existing runner behavior,
  and refresh-rate model. These are not GPU visual tests.
- Targeted analysis of 11 isolated source/test files: **No issues found**.
- Whole-app renderer/widget tests, full suite, GPU visual parity, device timing
  and profile build: **not verified**. The owner requested to build the APK.
- Graphify executable unavailable; graph refresh could not run. No graph output
  was fabricated. Review graph freshness separately when the tool is available.

## 8. Performance findings

Confirmed only from source: safe surfaces can request a common input without
changing their Full Glass shaders or merging their four layers. Unsafe sampling
relationships get separate keys. The captured assignment makes a no-sharing
case visible. Topology/layout changes invalidate a measured run.

**No repeatable performance improvement has been established.** Capture
reduction, GPU bandwidth, raster blocking and presentation effects require
the physical-device experiment. No FPS prediction is made.

## 9. Optional bounded capture — separate experiment

Do not combine `LiquidGlassCapture` with this A/B change. It changes the capture
region and would add another independent variable.

If sharing alone is visually correct, compare a separate configuration using
tight top-header and bottom-bar clusters. Paint the background below, not
inside, the capture. A screen-spanning union of top and bottom chrome can erase
the benefit. Let the package derive margins for blur (roughly three sigmas),
dispersion/refraction reach, backdrop shrink, contour and exterior effects;
review transforms/DPR and retained clips. Tight silhouette-only bounds can
cause edge replication, clipped blur, incorrect edge refraction or seams.
Separate keys are still necessary when an upper glass surface must sample a
lower glass surface. Measure extra capture/composition cost against any smaller
processing region before recommending it.

## 10. Keep, revise or discard

**Keep only as an opt-in, unverified developer experiment.** The unchanged
control remains the reference. Do not promote B without matched-offset visual
parity and repeated timing/presentation improvement. Revise or discard if parity
fails or performance does not improve. Any package upgrade requires reviewing
the safety bounds and repeating both checks.
