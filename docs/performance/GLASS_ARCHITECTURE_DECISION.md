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
