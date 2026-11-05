# Glass architecture decision

Status: decided 2026-11-05. Production stays glass-free. The developer Glass POC
(Developer Options > Glass POC) keeps `liquid_glass_widgets` 1.16.1. No new
engine is added.

## 1. BitChord source analysis

Repository: `https://github.com/kushagrasinghx/BitChord`, inspected at commit
`b690dc1` (shallow clone). BitChord is a Kotlin Multiplatform / Jetpack Compose
app, not Flutter. Its glass is Android-only.

| Concern | Where (BitChord `b690dc1`) | What it does |
|---|---|---|
| Liquid glass surface | `app/src/main/java/com/music/bitchord/ui/components/LiquidGlass.kt`, `Modifier.liquidGlass` (around line 202) | `drawBackdrop` with an effect chain: `colorControls`, `blur(8dp × 0.33)`, `lens` (AGSL), then a theme tint, a `Highlight` rim and a `Shadow`. |
| Shared capture | `MainActivity.kt` (around lines 419–431) | One `rememberLayerBackdrop` records the whole app once. Every glass surface samples that same layer. |
| Resolution | `LiquidGlass.kt`, `GLASS_RESOLUTION_SCALE = 0.33f`, passed as `backdropScale` | The backdrop is processed at one third resolution. |
| Effect pipeline | `app/.../ui/components/backdrop/effects/{Blur,Lens,ColorFilter,RenderEffect}.kt` | Vendored from Kyant0/backdrop v2.0.0 (Apache-2.0). Uses `android.graphics.RenderEffect` and AGSL `RuntimeShader`. |
| Minimum API | `backdrop/Platform.kt` | RenderEffect needs API 31; the lens shader needs API 33 (`isRuntimeShaderSupported`). |
| Fallback | `LiquidGlass.kt`, `isGlassSupported()` | Below API 31 the surface is not glass. Haze fallbacks are used instead. |
| Frosted bars | `sharedUi/.../OptimizedHaze.kt`; `dev.chrisbanes.haze:haze:1.3.1` in `sharedUi/build.gradle.kts` | Haze blur with `HazeInputScale.Fixed(0.33f)`. The comment says the full-resolution blur "was sampling at full resolution on every frame of every scroll" before the change. |
| Lightweight variant | `LiquidGlass.kt`, `lightweightLiquidGlass` and `liquidGlassRim` | No capture, no blur, no lens. A tint plus a highlight stroke, for controls over a stable background. |
| Reduce dynamic blur | `LiquidGlass.kt` (around line 208) | Replaces the glass with a solid surface. |
| Default | `app/.../data/settings/AppSettings.kt`, line 472: `liquidGlass = MutableStateFlow(false)` | Opt-in. Off by default. |

Facts versus hypotheses:

- Verified from source: a single recorded backdrop, sampled per surface; one-third
  resolution; RenderEffect blur; AGSL lens on API 33+; opt-in default off.
- Not verified: BitChord's frame timings. The repository has no benchmark or
  trace data, and there is no device I can measure. Its performance claims are
  code comments, not measurements.

## 2. Sistrum POC facts (device data as reported)

Liquid Glass (`GlassQuality.standard`) uses the package's lightweight path: one
`BackdropFilter` with a custom fragment shader per surface
(`lib/widgets/shared/lightweight_liquid_glass.dart` in 1.16.1). Reference Glass
(`premium`, `useOwnLayer: true`) takes the premium own-layer path, which is
`toImageSync`-based (`lib/widgets/shared/adaptive_glass.dart`). Basic Blur is one
`BackdropFilter` with `ImageFilter.blur(12)` per surface, at full resolution.

| Mode | Raster P50 | Raster P99 | Frame-budget exceedance | Conditions |
|---|---|---|---|---|
| Transparent baseline | 2.43 ms | 3.09 ms | 0% | device |
| Basic Blur | 21.02 ms | 25.50 ms | 100% | device |
| Liquid Glass, animated | 8.70 ms (P90 15.94) | 19.30 ms | 19% | device |
| Liquid Glass, static | 6.39 ms (P90 9.27) | 39.01 ms | 5.3% (75 frames only) | device |
| Reference Glass (old, grouped) | 3.00 ms | 3.94 ms | 0% | device, nothing drawn |

The earlier "Reference Glass is cheap" result was a rendering failure, not a
performance win. The old build drew no header, mini player or tab bar (reproduced
on a Linux Impeller harness, screenshot `old_reference.png`). Its raster time was
the cost of drawing almost nothing. Reference Glass has not been measured on a
device since the fix in `8a006f1`.

The acceptance target is under 3% exceedance during scrolling, with no persistent
raster violations. Liquid Glass with animation is at 19%, and Basic Blur is at
100%.

## 3. Architecture comparison

| | A. `liquid_glass_widgets` (current) | B. BitChord (Kyant backdrop + RenderEffect) | C. Built-in `BackdropFilter` blur |
|---|---|---|---|
| Visual fidelity to BitChord | Close in intent (refraction, rim). Not a match. | Reference. | Frosted only. No refraction or rim. |
| Raster cost (device) | Liquid 6–9 ms; animated P50 8.7 ms | Not measured. Not testable here. | 21 ms P50 at 4 surfaces. |
| Backdrop sampling | Per surface (lightweight); own layer per surface (premium) | One recorded layer shared by all surfaces, one-third resolution | Per surface, full resolution |
| Shader | Package fragment shaders | AGSL lens and RenderEffect blur | None (blur is native) |
| Multiple surfaces | Cost grows with count | Shared capture; cost grows with surface area | Cost grows with count and area |
| Platform | Flutter, Android and iOS | Android 12+ (API 31); lens needs API 33 | Flutter, all platforms |
| Maintenance | Pinned dependency, reviewed in this repo | About 3,000 lines of vendored Kotlin, copied from another project | Smallest |
| Flutter port | Exists | Not a Flutter API. A port needs our own capture-and-sample pipeline. | Exists |

Verified: A's cost is measured. B's source is verified but its performance is
not. C is the most expensive per surface and is measured.

Hypothesis: B's one-third shared capture would lower the cost of multiple
surfaces. Flutter has no public API that gives a `BackdropFilter` a reduced input
resolution or a shared captured layer. Getting that would mean building our own
capture-and-sample pipeline. The task rules forbid that without strong evidence,
and we have none.

## 4. Decision

1. Keep the current architecture, option A: `liquid_glass_widgets` 1.16.1, pinned.
   It is the only tested glass pipeline in Sistrum, and its Liquid Glass mode is
   the cheapest glass measured on the device.
2. Do not adopt BitChord's Kyant backdrop, its vendored effect package, or Haze.
   The code is Android-only Compose, it has no Flutter equivalent, and BitChord
   has no performance evidence to offer.
3. Do not build a custom capture-and-blur engine. The Flutter equivalent of B
   is unproven, and this decision must not become another speculative engine.
4. No production rollout. Glass stays in the developer POC.
5. Basic Blur is not a candidate for production. It is the measured-expensive
   baseline.

## 5. Limitations and what would change the decision

- Liquid Glass with animation exceeds the 3% target (19%). No fix is supported
  by evidence yet, so no change is made.
- Reference Glass draws correctly on Linux Impeller, but it has not been
  measured on the device since the fix.
- Measurements from earlier runs were taken under different conditions and must
  not be treated as controlled benchmarks.
- To reopen this decision, measure on the device, in the same scene, with the
  same geometry: static and animated background, scrolling content, one surface
  and then four. Use the Performance HUD's copy report. Only after that should a
  capture-and-sample design be considered, and it would need its own decision.

## 6. Sources

- BitChord `b690dc1`: files listed in section 1.
- `liquid_glass_widgets` 1.16.1, commit `5911897`: `lib/widgets/shared/lightweight_liquid_glass.dart`, `lib/widgets/shared/adaptive_glass.dart`.
- Haze 1.3.1 and Kyant0/backdrop 2.0.0 (vendored in BitChord).

## 7. Addendum (2026-11-05, second review): native BitChord-style Glass feasibility

This addendum does not replace sections 1–6. Those record what was known when
the decision was made. The points below are new.

### 7.1 New evidence

- The user reports that BitChord runs smoothly on the same Android device that
  shows Sistrum's Flutter Glass frame-budget exceedance. BitChord's Liquid Glass
  and its extra Blur option were both enabled during normal use.
- This is an observation, not a measurement. BitChord's frame timings were not
  captured, and no trace was taken on either app. It is evidence that the
  effect is affordable on this device when implemented as BitChord does it. It
  is not evidence of the cause.

### 7.2 What BitChord does, re-checked

Checked against `b690dc1`, the same files as section 1:

- `LiquidGlass.kt`: `drawBackdrop` with `colorControls`, `blur`, and `lens`,
  `backdropScale = GLASS_RESOLUTION_SCALE (0.33f)`.
- `MainActivity.kt` (around lines 419–431): one `rememberLayerBackdrop`
  records the page. Glass surfaces sample it.
- `backdrop/effects/RenderEffect.kt` and `Blur.kt`: `android.graphics.RenderEffect`
  and AGSL `RuntimeShader`. `isRenderEffectSupported()` needs API 31, and
  `isRuntimeShaderSupported()` needs API 33 (`backdrop/Platform.kt`).
- `OptimizedHaze.kt`: `HazeInputScale.Fixed(0.33f)`.

All of this is Compose. The rendering is done by Android's RenderNode and
RenderEffect, on the Compose side of the window. Flutter's renderer is a
separate engine that draws into its own surface.

### 7.3 Feasibility of each approach

| Approach | Classification | Reason |
|---|---|---|
| A. Native Android overlay (a native glass View or window above Flutter) | NOT PRACTICAL | Flutter draws into its own surface (a `SurfaceView` or `TextureView`). Per the Android `SurfaceView` docs, the surface is "Z ordered ... behind the window" and the view hierarchy composites it. A native effect has no public way to read that surface's pixels. The only route to the pixels is a copy (`PixelCopy` or a GPU readback), once per frame. That is the per-frame readback the task rules out. The alternative, a compositor blur behind a window (`WindowManager.LayoutParams.setBlurBehindRadius`), blurs the window's rectangular area. It cannot follow a rounded shape, and it was not confirmed to behave that way here. |
| B. Flutter texture or GPU interop | NOT PRACTICAL | Flutter's `Texture` widget brings native frames into Flutter. It does not export Flutter's scene back out. The only public capture is `RenderRepaintBoundary.toImage`, which returns "uncompressed raw RGBA bytes" (Flutter docs, fetched). Per-frame capture is excluded by the task rules, and no public API turns a `ui.Image` into an Android `HardwareBuffer` or a `RenderNode` input. |
| C. Flutter-native adaptation of BitChord's optimisations | EXPERIMENTAL / UNPROVEN, and excluded by the rules as stated | Capturing the page once at reduced scale and blurring the small image would reproduce the shared-capture and one-third-resolution ideas. It needs a per-frame `toImage`, which the task rules exclude. `ImageFilter.blur` has no public input-resolution option (Flutter docs, fetched). So a reduced-resolution blur would need the custom pipeline the rules rule out. |

Unverified: whether `View.setRenderEffect` applies only to the view's own
content. The fetched page was too long to reach the method text. This matters
for A, but A is already NOT PRACTICAL for the readback reason above, so the
conclusion does not depend on it.

### 7.4 Decision: NO-GO for a native BitChord-style POC

- No credible approach exists that avoids per-frame readback and avoids
  rebuilding the UI in Compose.
- The one approach that would be credible on the device (reduced-resolution
  shared backdrop with a hardware blur) cannot be built on public Flutter or
  Android APIs without the excluded readback path.
- So no native POC is implemented, and no Profile APK is built for this step.
  The existing POC is unchanged.

### 7.5 What the same-device observation does and does not change

- It shows that a reduced-resolution, shared-backdrop design runs well on this
  device. It does not show that Sistrum's Flutter `BackdropFilter`s are the
  cause of the exceedance. That is still a hypothesis.
- The decision in section 4 stands. Keep `liquid_glass_widgets` 1.16.1 for the
  POC only. Production stays glass-free.

### 7.6 Remaining validation requirements

- Measure BitChord and Sistrum side by side with Perfetto on the same device,
  same scene, and same refresh rate. Compare GPU time per frame and the
  composition path, not only Flutter `FrameTiming`. A Flutter-only number
  cannot show native composition costs.
- Measure Sistrum's Reference and Liquid modes in the scenes listed in section 5
  before any production decision.
- Confirm whether `View.setRenderEffect` applies to the view's content only
  (Android docs, full method text). Record the answer here.
- If a production glass is still wanted, the lowest-risk option to test is one
  surface only (the bottom bar or mini player) in Liquid Glass standard. Test it
  against the baseline on the device. This is a product call and is not
  recommended by this addendum.

### 7.7 Sources used in this addendum

- BitChord `b690dc1` (checked again): files named in sections 1 and 7.2.
- Android `SurfaceView` reference (fetched): composition and Z-order wording.
- Android `View.setRenderEffect` and `WindowManager.LayoutParams.setBlurBehindRadius`
  references: fetched but not fully read. Their conclusions are not relied on.
- Flutter `RenderRepaintBoundary.toImage` and `ImageFilter.blur` references
  (fetched): the RGBA and no-downsampling wording above.

## 8. Addendum (2026-11-05, third review): shared backdrop in liquid_glass_widgets 1.16.1

Sections 1–7 are unchanged. This section records what was checked in the
pinned source (commit `5911897`), what the POC now does, and what remains
unverified.

### 8.1 APIs verified in 1.16.1

- `GlassBackdropGroup({child, enabled, joinEnclosing})`
  (`lib/src/renderer/glass_backdrop_group.dart`, exported). Its doc comment
  states it applies to premium glass only: "Premium glass surfaces that read the
  backdrop together". On Impeller, a shared read is taken for the blur and frost
  passes of premium surfaces, and matching filters run once for all of them.
  Refraction stays per surface.
- `GlassBackdropGroup.keyOf(context)`: returns the group's `BackdropKey`.
- `LiquidGlassLayer` (`lib/src/engine/liquid_glass_layer.dart`, around lines
  224–267 and 520–545): each layer owns `_backdropKey`, and uses
  `GlassBackdropGroup.keyOf(context) ?? _backdropKey`. Sharing needs an enclosing
  group with at least two members, no render pass between the layer and the
  group, and no backer.
- `BackdropGroup` / `BackdropKey` (the package's internal backdrop group,
  `lib/src/renderer/glass_backdrop_group_boundary.dart`).
- Standard lightweight glass (`lib/widgets/shared/lightweight_liquid_glass.dart`):
  no reference to `BackdropKey`, `BackdropGroup` or `keyOf`. It cannot join a group.
- `GlassTabBar` and `GlassAppBar` group their own glass internally. They are not
  used by the POC.

Doc-stated limits that apply here: a group with one member changes nothing; glass
that overlaps another glass in the same group shows the content behind both;
`Opacity`, `FadeTransition` or a save-layer clip keeps glass out of the group.

### 8.2 Which modes can use a shared read

| Mode | Path (1.16.1) | Can share a read? | Why |
|---|---|---|---|
| Basic Blur | This app's own `BackdropFilter(ImageFilter.blur)` | No | Not package glass. The group reaches only package premium glass. |
| Liquid Glass | Package standard, lightweight shader per surface | No | Lightweight path does not read the key. |
| Reference Glass | Package premium, own layer per surface | Yes | Reads `keyOf` and joins the group. |

So the switch can only change Reference Glass. The two modes whose device costs
were measured (Basic Blur 21 ms, Liquid Glass 6–9 ms) cannot be changed by
grouping in this package version.

### 8.3 Rendering tree (current POC)

```
ClipRect
  SistrumGlassScope(mode)
    Stack
      background CustomPaint        (repaints every frame when animated)
      ListView                       (scrolling content)
      header row
        glass circle (back)          surface 1
        glass capsule (search, more) surface 2
      column (bottom)
        mini player                  surface 3
        tab bar                      surface 4
```

- Only the active mode is mounted. Changing mode changes the surface subtree,
  so the previous mode's backdrop filters or layers are unmounted.
- No two glass surfaces overlap. Surfaces 1 and 2 are in the header row; 3 and 4
  are stacked with a 10 px gap. Overlap with the list is expected and intended.
- No glass sits inside another glass surface, under an `Opacity`, or in a
  save-layer clip.

Cost structure per mode:

- Basic Blur: 4 independent `BackdropFilter` passes, each at full resolution.
  Four unique reads, no sharing.
- Liquid Glass: 4 lightweight `BackdropFilter` passes with a shader. Unique
  reads, no sharing. The shared `LiquidGlassLayer` wrapper exists only in this
  mode and is not a backdrop read.
- Reference Glass, switch off: 4 own layers, each with its own `BackdropKey`,
  so 4 unique reads.
- Reference Glass, switch on: 4 members in one `GlassBackdropGroup` key. The
  blur and frost reads can be shared, since all four use the same settings.
  Refraction stays per surface.
- Animated background: the background repaints every frame, so every glass
  surface re-samples every frame. Sharing does not remove that. Static
  background: no background repaint.

### 8.4 Implementation (commit `f8312b7`)

- `lib/widgets/glass_poc/sistrum_glass_surface.dart`:
  `SistrumGlassScope(sharedBackdrop: …)` wraps its child in `GlassBackdropGroup`
  only for Reference Glass with the switch on (`sharedBackdropApplies`). Other
  modes are unchanged.
- `lib/providers/performance/glass_poc_mode_provider.dart`:
  `glassPocSharedBackdropProvider` (in-memory, default off) and
  `glassPocPathLabel`, which names "(shared backdrop)" only where the group applies.
- `lib/screens/settings/developer/glass_poc_page.dart`: switch "Shared backdrop
  group (Reference Glass only)". Developer-only.
- HUD (`perf_hud_overlay.dart`) and copied reports (`developer_options_page.dart`):
  the `Glass` row and `glass_mode=` line use `glassPocPathLabel`.
- Geometry, quality, blur, tint, background and animation are unchanged. Only
  one path renders at a time.

### 8.5 Visual correctness check

Linux Impeller harness (Mesa GLES, Xvfb 1280×800), Reference Glass, outlines on,
same content:

- Switch off and on: the screenshots are identical in every glass and header
  region. The only changed pixels (bounding box 1200–1252 × 148–181) are the
  switch's own toggle.
- The surfaces are visible in both captures, with the same blur and tint.

This shows the grouped path does not change the drawn result on this renderer. It
does not show that it is faster. The harness is a CPU (llvmpipe) renderer, so
its frame times say nothing about the device.

### 8.6 Tests

- `test/widgets/glass_poc/glass_shared_backdrop_test.dart`: the group applies only
  to Reference with the switch on; the path label; the switch default and toggle;
  the page switch adds the group for Reference only.
- Full `flutter test`: All tests passed, 2,537 tests, exit 0. `flutter analyze`:
  no issues.

### 8.7 Plan B: `liquid_glass_renderer` (not adopted)

Checked from pub.dev archive `liquid_glass_renderer-1.0.0-dev.2` (published
2026-10-27):

- SDK: `>=3.13.0 <3.14.0`, Flutter `>=3.47.0`. Sistrum's Dart is 3.13.5, so the
  SDK constraint is compatible.
- Dependencies: `flutter_gpu`, `flutter_gpu_shaders`, `flutter_shaders`, `hooks`
  (native assets), `motor`, plus smaller packages.
- Full glass needs Impeller and Flutter GPU, which the README calls "still in
  preview". Flutter GPU is enabled with `--enable-flutter-gpu` or the Android
  manifest meta-data `io.flutter.embedding.android.EnableFlutterGPU`. Sistrum's
  manifest does not set it, so a production build would need a preview flag.
- The README calls the package "Experimental: not yet battle-tested in production
  apps", and lists a limit of 16 shapes per layer.
- Its shared-capture API (`LiquidGlassCapture`, `BackdropGroup`, `useBackdropGroup`
  in `fake_glass.dart`) is the closest published match to the shared-backdrop idea.
  Its behaviour on device is unmeasured here.

Decision: NO-GO for adopting it now. The GPU API is in preview, the package is
experimental, and a migration is outside this task. A GO would need a separate,
device-only spike, with the preview flag, and a comparison against the baseline.

### 8.8 Remaining real-device validation

Use the profile APK (`sistrum-shared-backdrop-profile.apk`, SHA-256
`ba829e91ad4b4556610422ac6c80e915c047f06b0fb8d9272b3ec72104ad0b7e`):

1. Developer Options > Glass POC > Reference Glass. Switch "Shared backdrop
   group" off. Scroll the list for 20 seconds. Copy the HUD report.
2. Switch it on. Repeat the same scroll. Copy the report.
3. Compare Raster P50/P90/P99 and frame-budget exceedance between the two runs.
   The HUD `Glass` row and `glass_mode=` line show which path ran.
4. Repeat both with the animated background on.
5. Confirm by eye that the surfaces look the same in both runs.

A result counts only if the difference is clear and repeated across runs. Basic
Blur and Liquid Glass are not affected by this switch. Their device costs remain
as measured in section 2.

## 9. Addendum (2026-11-05, fourth review): `liquid_glass_renderer` comparison POC

Sections 1–8 are unchanged. This section records the comparison POC. It is
developer-only and reversible, and nothing in production uses it.

### 9.1 Library and compatibility

- Package: `liquid_glass_renderer` **1.0.0-dev.2** (pinned in `pubspec.yaml`,
  published 2026-10-27 on pub.dev). Dependencies added by the solver:
  `flutter_gpu`, `flutter_gpu_shaders`, `flutter_shaders`, `motor`; plus `hooks`
  (native assets). Verified with `dart pub add --dry-run`, which changed no files.
- SDK: the package needs Dart `>=3.13.0 <3.14.0` and Flutter `>=3.47.0`.
  Sistrum uses Dart 3.13.5 and Flutter 3.47.7. **Compatible.** No upgrade needed.
- Android: `minSdk` is 24 (the Flutter default). The package names no minimum
  API of its own. Impeller on Android falls back to GLES, so a minimum of 24 is
  **not verified** for full glass.
- Flutter GPU is a preview API. It is enabled by the meta-data key
  `io.flutter.embedding.android.EnableFlutterGPU`. It is set only in
  `android/app/src/profile/AndroidManifest.xml`, so release builds are unchanged.
  Verified: the key is in the built profile manifest. The release manifest has
  no change.
- Native assets are on by default in this Flutter (`features.dart`, stable).
  The package's shader hook built on Linux and Android.

### 9.2 Rendering architecture (verified in source, `5911897`-style check on the 1.0.0-dev.2 archive)

- Public exports (`lib/liquid_glass_renderer.dart`): `LiquidGlassLayer`,
  `LiquidGlass`, `LiquidGlassCapture`, `FakeGlass`, `LiquidGlassBlendGroup`,
  `LiquidGlassSettings`, `LiquidRoundedSuperellipse` and others. Presets:
  `LiquidGlassSettings.ios27RegularLight/Dark`, `ios27Clear`, `ios27Regular`.
- `LiquidGlass.auto` creates its own layer when none encloses it. A
  `LiquidGlassLayer` holds many `LiquidGlass` shapes (the README limits this to 16
  per layer).
- `FakeGlass` is the fallback without Flutter GPU. The library's own log says so:
  "Flutter GPU is unavailable; LiquidGlassLayer is using FakeGlass."
- Shared backdrop: `LiquidGlassCapture`, `BackdropGroup`, and `useBackdropGroup` /
  `backdropKey` on `FakeGlass` and `LiquidGlass.auto` (`lib/src/fake_glass.dart`).
  **Not used in this POC.** Its cost on device is unmeasured.
- Resolution: the library reduces blur cost by Impeller's own Gaussian
  downsampling, and raises a frost floor to Impeller's downsample point
  (`lib/src/liquid_glass_settings.dart`, around lines 110–135 and 233–246). This
  is **not** a fixed 0.33 factor. The BitChord 0.33 technique is **not** claimed
  here.
- GPU readback: not verified. The library describes its capture as a GPU pass
  (`LiquidGlassCapture`). No CPU readback is documented, and none was measured.

### 9.3 POC changes (commit `3c7b1a6`)

- `lib/widgets/glass_poc/sistrum_glass_mode.dart`: `rendererGlass`, labelled
  "New renderer (liquid_glass_renderer)". `usesRenderer` is true for it only.
- `lib/widgets/glass_poc/sistrum_renderer_glass.dart`: the only file that imports
  the renderer (prefix `lgr`, because the class names clash with the widgets
  package). Each surface is `LiquidGlass.auto` with `ios27Regular{Dark,Light}`.
- `lib/widgets/glass_poc/sistrum_glass_scene.dart`: scenes A–D (surface count,
  background animation, list scrolling).
- `lib/providers/performance/glass_poc_mode_provider.dart`: scene state, and
  `glassPocReportLabel`, which names renderer, scene, animation and shared state.
- `lib/screens/settings/developer/glass_poc_page.dart`: scene chips, Reset and Copy
  metrics, a scrolling control block, and the stage kept below it.
- HUD and Developer Options reports: the full label.
- Tests: `test/widgets/glass_poc/renderer_comparison_test.dart` (mode selection,
  scene configuration, label, renderer tree per scene, animation and scroll
  state) and updates to the existing page and shared-backdrop tests. Full
  `flutter test`: All tests passed, 2,548 tests, exit 0.

### 9.4 Deviation: per-surface layer for the renderer

The library's example puts many shapes in one `LiquidGlassLayer`. In the Linux
Impeller harness, a shared layer drew **none** of its shapes. A standalone
`LiquidGlass.auto` drew its glass, using `FakeGlass` (the render without Flutter
GPU). So the renderer mode uses one layer per surface, as Reference Glass does.
This is a deviation from the library's pattern, and the cause is not diagnosed.

### 9.5 Visual correctness: what is and is not verified

| Check | Result |
|---|---|
| Standalone renderer shape draws (Linux, Impeller, no Flutter GPU) | Verified: frosted, tinted surface; text behind it is blurred. `FakeGlass` path. |
| Shared `LiquidGlassLayer` with several shapes (Linux) | **Failed**: nothing drawn. Reason not diagnosed. |
| Full Flutter GPU shader path (Linux, `flutter run --enable-flutter-gpu`) | **Not verified**: no fallback message, but the glass is still not visible in the capture. |
| Full Flutter GPU path on Android device | **Not verified**: needs the profile APK on the device. |
| Rounded clipping, edge highlight, refraction, hit testing | **Not verified** on the full path. Hit testing: the widget tests tap the child. |
| Shader compile on Android | **Not verified**. The hook built, but the device run has not been checked. |

A low raster time with missing glass is an invalid result. Until the full path is
visible on the device, the renderer's timings are not evidence of anything.

### 9.6 HUD frame-budget audit (formula documented, not changed)

Source: `lib/services/performance/perf_frame_window.dart` (`snapshot`) and
`perf_frame_monitor.dart`. Flutter definitions: `dart:ui`
`FrameTiming` (`root/bin/cache/pkg/sky_engine/lib/ui/platform_dispatcher.dart`).

- Window: the last **300 frames** (rolling), regardless of time.
- `build` and `raster` percentiles (P50/P90/P99): from `buildDuration` and
  `rasterDuration` of the window's frames.
- **`frame_budget_exceedance`** = (count of window frames with `totalSpan` >
  `1e6 / hz` µs) ÷ (window frames) × 100. `totalSpan` is "the timespan between
  vsync start and raster finish" (Flutter docs). It is **not** the raster time.
- `fps_estimate` = (frames − 1) ÷ (newest raster-finish timestamp − oldest), in
  frames per second. It counts frames delivered inside the window, so during idle
  periods it reflects old frames, not the display's current rate.

The apparent inconsistency is resolved. Raster P50 of 18.8 ms with exceedance of
84–100% is consistent, because a raster time above the budget implies a span above
the budget. The one assumption is that raster starts after vsync start, which the
docs do not state outright. Under it, exceedance is at least the fraction of frames
whose raster time is above the budget. The definition is documented here and was
not changed.

### 9.7 Benchmark methodology

- Scenes (identical geometry in every renderer): A one surface; B four surfaces,
  static; C four surfaces, animated background; D four surfaces, list scrolling
  at one pass per 20 s.
- Renderers: Transparent Baseline; Liquid Glass (widgets, standard); New renderer
  (`liquid_glass_renderer`, per-surface); Reference Glass (widgets, premium own
  layer). Basic Blur is unchanged.
- Fairness limits: the renderer uses its own iOS 27 preset, not the widgets
  settings. Blur and refraction models differ, so the look is matched by
  intent only. The renderer's per-surface layers differ from the library's
  shared-layer example. The shared-backdrop switch applies to Reference only.
- Use the HUD's Reset metrics and Copy metrics buttons between runs. Each copied
  report names the renderer, scene, animation and shared state.

### 9.8 Decision and remaining measurements

No recommendation to adopt the renderer. The decision criteria in the task need
device evidence that has not been collected:

1. Visible full-path glass on the device (not `FakeGlass`), in each scene.
   Confirm rounded clipping, edge highlight and refraction by eye.
2. Raster P50/P90/P99 and frame-budget exceedance for A, B, C and D, for each of the
   three renderers, on the profile APK
   (`sistrum-liquid-glass-comparison-profile.apk`, SHA-256
   `e757326ab134d8be6467507569fb5116b540b74b73b90e9e6fa9356cc55f53fa`).
3. Repeat each run at least twice. Judge only clear, repeated differences.
4. Compare the same scenes against Transparent Baseline, to see the glass cost.
5. Treat the library as a viable candidate only if its full path is visible,
   raster P90 is below 16.67 ms with headroom in the scrolling and animated scenes,
   and it stays stable. If Liquid Glass and this renderer both exceed the budget
   under equivalent conditions, recommend against production integration.

Until that is done, `liquid_glass_widgets` 1.16.1 remains the only glass
dependency with device-collected numbers, and it remains POC-only.

## 10. Addendum (2026-11-05, fifth review): Full Glass, FakeGlass and the scroll benchmark

This section does not change sections 1-9. Earlier results are historical: they
were collected with the "New renderer" mode and the 20-second scroll pass, not
the speed presets below, so they are not controlled comparisons with this
benchmark.

### 10.1 Package rendering architecture (verified in `liquid_glass_renderer` 1.0.0-dev.2)

- `LiquidGlassLayer(fake: ...)` decides the path per layer. `fake: true` builds
  FakeGlass for every shape in the layer.
- `fake: false` builds the real path only when all of these hold: the
  `ImageFilter.isShaderFilterSupported` check passes, and the
  `FlutterGpuGeometryRenderer` loads. The load is asynchronous, runs after a
  post-frame callback, and is retried on no later frame. Until it completes, and
  if it fails, the layer builds FakeGlass.
- Failure is silent in profile and release builds. The package logs a fallback
  message only under `kDebugMode`, so a profile run has no log to read.
- The package exposes no public accessor for its effective mode. Its
  `LiquidGlassLayer` state is private. So the effective path cannot be read from
  the API and must be inferred.
- `LiquidGlass.withOwnLayer(shape:, settings:, fake:, child:)` is the public
  per-surface entry point. The POC uses it for both renderer modes, so the
  `fake` value is passed explicitly and not inherited.

### 10.2 Actual rendering-path detection

`lib/widgets/glass_poc/sistrum_glass_render_path.dart` reads the mounted stage
(read-only, no tree mutation) and counts widget types:

| Evidence in the tree | Meaning |
|---|---|
| `_RawShapes` on every `LiquidGlassLayer` | real GPU layer: `full_gpu` |
| `FakeGlass` widgets (`RawFakeGlass`, consolidated layer) | `fake_backdrop` |
| `BackdropFilter` on every surface | Basic Blur, `backdrop_filter` |

Rules:
- New Full Glass reports `full_gpu` only when every layer is real and no FakeGlass
  is mounted. A Full Glass request that mounted FakeGlass is
  `fake_backdrop` with `glass_fallback=true` and a reason.
- New FakeGlass reports `fake_backdrop` only when every layer is FakeGlass.
- Anything else (blank, initializing, mixed) is `unverified`. Blank and
  initializing are not glass.
- Old Liquid Glass and Reference Glass come from `liquid_glass_widgets`, which
  is not instrumented. They always report `unverified`.

Timing: the page re-probes every 500 ms (a timer, not a ticker) and reports
changes on screen. Sampling starts only after warm-up and only once a verifiable
path is confirmed. If the path changes between the start of measurement and the
copy, the report says `unverified`.

Limits of this method:
- It uses `runtimeType` names. Profile builds keep them. A build with
  `--obfuscate` may rename the private `_RawShapes`, and the probe would then
  report `unverified` rather than guess. It must be checked on any obfuscated build.
- It proves the widget tree, not GPU work. A real layer means the Flutter GPU
  path was taken; it does not measure that path's cost.
- Verified in the flutter_test VM (no Flutter GPU): New Full Glass is reported as
  a fallback to FakeGlass, and the test asserts it is never `full_gpu`.

### 10.3 Scroll implementation

- One scroller, `SistrumAutoScroller` (`sistrum_auto_scroll.dart`), drives the
  page's single list for every mode. It uses a `Ticker`, so each frame's offset
  is `speed x elapsed frame time`. It never uses `animateTo`, so no animations
  overlap.
- Speed presets are logical pixels per second: Slow 150, Normal 400 (default),
  Fast 900.
- Boundary behaviour: reverse. The offset is a triangle wave over the distance
  travelled, from 0 to the maximum extent and back. Each end is a turn, not a
  reset, so the content never jumps. The report records `reverse`.
- Turns are counted in the sample window (`scroll_boundary_transitions`), so a
  window containing a turn can be identified. Per-frame spike attribution is not
  available: the HUD does not link a frame to a turn.
- Stop keeps the offset and the active time, so resuming continues from the same
  point. Changing speed, changing renderer, or Reset benchmark starts a fresh run
  from offset 0.
- No ticker runs while stopped. The page's background `AnimationController`
  (Scene C) is separate and unchanged.

### 10.4 Measurement method

- Warm-up is 2 s of active scrolling. Frames during warm-up are not counted: the
  HUD monitor is held (`setCollecting(false)`) after each fresh run and released
  when warm-up ends.
- Sampling also waits for a verifiable render path. For New Full Glass, a blank
  or initializing tree holds the sample, so shader initialization is not measured.
- `scroll_speed_actual` is the displacement per second of the list's applied
  offset over the last 300 scroll samples (about one HUD window at 60 Hz). It is
  `unavailable` when there are too few samples or the span is under 0.5 s. It is
  never the target.
- Frame-budget exceedance is unchanged from section 9: the share of window
  frames whose total span (vsync start to raster finish) exceeds the budget.
  Estimated FPS is not Android display FPS.
- Each configuration needs at least 300 counted frames. The report shows
  `frames=` and `scroll_samples=`; check that both are 300 or more.

### 10.5 Matrix and visual differences

Matrix: Scene D, speeds Slow, Normal, Fast, for Old Liquid Glass, New Full
Glass, New FakeGlass and Basic Blur (12 runs). Transparent Baseline is a
reference only; Reference Glass is not in the matrix.

Visual differences the comparison cannot remove:
- Full Glass refracts the background. FakeGlass does not; it applies frost and
  tint analytically. The POC does not disable Full Glass refraction to match,
  and does not add refraction to FakeGlass.
- Each renderer uses its own package and settings. Matching is by intent.
- Old Liquid Glass shares one layer; the two renderer modes use one layer per
  surface. This is the deviation recorded in section 9.

### 10.6 Running the 12-run matrix

1. Build and install the profile APK: `flutter build apk --profile --dart-define=SISTRUM_PERF_HUD=true` (with the JDK 25 environment from `/root/toolchains/env.sh`).
2. Developer Options > Glass POC. Select scene D.
3. For each renderer (New Full Glass, New FakeGlass, Old Liquid Glass, Basic Blur):
   a. Select the renderer, then check the `glass_render_path` line on screen.
      New Full Glass must show `full_gpu`. If it shows FALLBACK or `unverified`,
      record that result as a fallback and do not count it as a Full Glass result.
   b. For each speed (Slow, Normal, Fast): select the speed, let it run for at
      least 8 seconds (2 s warm-up, then about 300 frames), then Copy metrics.
   c. Check `frames`, `scroll_samples`, `scroll_speed_actual` and `scroll_warmup=complete`.
4. Keep the copied reports as the record. Do not average runs whose render path differs.

### 10.7 Known limitations and remaining verification

- Not verified on a device in this session: no device run and no visual check of
  the full Flutter GPU path. The Linux harness is not used for this section.
- The probe is written against `liquid_glass_renderer` 1.0.0-dev.2. A version
  change can rename the widgets it counts; re-check the classifier first.
- Boundary turns are counted, not separated from steady-state percentiles.
- Old Liquid Glass and Reference Glass paths are unverified by design.
- Still required on the Android device: (1) confirm `full_gpu` on the real device
  for New Full Glass and see refraction; (2) run the 12-run matrix; (3) confirm
  the window shows at least 300 frames with no `scroll_warmup=waiting` after the
  first run.
