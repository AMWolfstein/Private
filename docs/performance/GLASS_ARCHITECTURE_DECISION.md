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
