# Sistrum Hybrid: raster bottleneck diagnosis (developer POC)

Status: **instrumented, not yet measured on a device.** This environment has
no Android device. Nothing here claims 120 FPS or names a measured cause; the
device matrix below is empty until it is run.

## 1. The measurement that started this

Moto g75 5G, 120 Hz (8.33 ms budget), Scene D (four surfaces, fast scroll),
animated background off, shared backdrop off:

| Metric | Value |
|---|---|
| Raster P50 / P90 / P99 | 11.43 / 12.89 / 13.69 ms |
| Budget exceedance | 100% |
| Estimated frame production | 83.9 /s |
| Render path | UNVERIFIED |

It came from the HUD's Copy metrics while Sistrum Hybrid was shown. That
report did not say which Hybrid tier was active (the default is Frosted), and
the render path was `unverified` because Hybrid had no instrumentation.

### Blur 0 versus blur 1 (device, Scene D, shared off)

| Blur sigma | Raster P50 | Raster P99 | Exceedance |
|---|---|---|---|
| 0 | 4.35 ms | 5.47 ms | 0.7% |
| 1 | 10.36 ms | 13.75 ms | 100% |

The minimal nonzero blur adds 6.01 ms at the median. The engine explains why
sigma 0 is almost free: `DlBlurImageFilter::Make` returns `nullptr` when both
sigmas are near zero (`display_list/effects/image_filters/dl_blur_image_filter.cc`),
so the `BackdropFilterLayer` reaches Impeller with no filter and
`Canvas::SaveLayer` never calls `FlipBackdrop`. At sigma 1 a real filter
exists, and each of the four surfaces flips the whole frame (C1 below). So
the jump measures the four backdrop reads switching on, not the Gaussian
strength. That matches C1; it is one device's data, not yet the A–E matrix.

Sistrum no longer relies on the engine dropping the filter: at blur 0 Frosted
builds no `BackdropFilter` at all, and Full builds one only when the lens is
active (then the lens alone, without a composed no-op blur). Telemetry reports
it as `effective_path=tint` with `fallback_reasons=zero_blur_bypass`, so a blur-0
run can no longer be mistaken for a blur run.

### Bounded filter regions

The blur work is already bounded: each `BackdropFilter` sits in its surface's
`ClipRRect`, so the blur covers that rectangle plus its kernel. The oversized
part is the flip, which always copies the full render target; Flutter exposes
no way to bound it. Sharing (variant E, or Frosted with Shared backdrop on) is
the only public-API way to reduce the number of flips. Fewer flips than two in
Scene D would let the tab bar's blur miss the mini player above it, which is
a visual change, so the planner does not do it.

## 2. Render-path telemetry (Task 1)

`lib/widgets/glass_poc/sistrum_hybrid_telemetry.dart`. Each Hybrid surface
records the decision it hands to the engine at the place it builds its
filter: the Opaque, Lightweight and Frosted branches in
`SistrumHybridSurface`, and the Full branch in `SistrumLensGlass` (only it
knows whether the lens program is loaded). A surface removes its entry when it
leaves the tree. Reading is a scan of four map entries: no tree walk, no
per-frame logging, no rebuild.

Reported fields (`hybrid_*` lines in Copy metrics, the matrix report and the
path line on the POC page):

| Field | Meaning |
|---|---|
| `hybrid_requested` / `requested_tiers` | Configured tier and settings |
| `effective_path` | `opaque`, `tint`, `blur`, `lens` or `mixed(...)` |
| `backdrop_filter_surfaces` | Surfaces whose decision is a `BackdropFilter` |
| `shader_filter_surfaces`, `lens_shader_active` | Surfaces whose filter includes the lens |
| `fallback_blur_surfaces` | Full-tier surfaces drawing the blur instead |
| `fallback_reasons` | `shader_filters_unsupported`, `lens_program_loading`, `lens_program_failed`, `invalid_size`, or the requested `refraction_off` |
| `shared_backdrop_active` (groups, members) | Keys shared by two or more filters |
| `backdrop_reads_per_frame` | Engine backdrop flips implied by the decisions (see C1) |
| `decision_changes` | Changes of an already-reported surface's decision |
| `lens_program` | `loaded load_ms=…`, `loading`, `failed error=…`, `unsupported` |

The page now classifies Hybrid's `glass_render_path` from this telemetry
(`opaque`, `tint`, `backdrop_filter`, `lens_shader`), and a fallback is shown
as `FALLBACK: lens requested, blur drawn: <reason>`.

Limit: these are the filters handed to the engine. Whether the GPU executed
them is not observable from Dart.

## 3. Comparable baselines (Task 2)

| Variant | Tier | What it adds over the previous |
|---|---|---|
| A | Opaque | Cost floor: opaque fill, same shape and hairline, no backdrop read |
| B | Lightweight | Translucent tint, highlight and hairline (still no read) |
| C | Frosted | One `BackdropFilter` blur per surface (four reads) |
| D | Full | Lens shader composed after the same blur (four reads) |
| E | Full, shared backdrop | D with one shared read where it is safe |

Every variant uses blur sigma 8, tint 0.40, refraction and chromatic on.
Surface count, geometry, scroll speed, background and animation are the same:
`glass_poc_hybrid_page_test.dart` checks the stage size and all four surface
rectangles across A to E (the stage is an `Expanded` beside a loose
`Flexible`, so the Hybrid controls never resize it).

Run it from Developer Options > Glass POC > **Run Hybrid A–E Matrix**: five
variants, three counterbalanced rounds, 2 s transition, 5 s warm-up and 60 s
measured each (about 17 minutes). A Full run measures only once the telemetry
shows the lens on every surface; a run whose decisions change while measuring
is invalid. The report gives per-variant medians and the step costs A→B, B→C,
C→D and D→E.

## 4. Raster-cost review (Task 3)

### Confirmed by the code and the engine source

**C1. Every independent `BackdropFilter` copies the whole frame.** Impeller
`Canvas::SaveLayer` calls `FlipBackdrop()` for each backdrop filter without a
shared key (`impeller/display_list/canvas.cc`). `FlipBackdrop` ends the current
render pass, takes its full-size colour texture as the filter input, opens a
new pass and redraws the whole previous frame into it (the "MSAA backdrop"
entity, `Rect::MakeSize(input_texture->GetSize())`), then replays the clips.
The size is the render target's, not the surface's: a 48 dp back button costs
a full-screen copy. Variants C and D therefore do four full-frame
store-and-redraw cycles per frame on top of A/B. Only the last flip may use the
onscreen texture, and only with framebuffer fetch.

**C2. The Full tier adds two passes per surface.** For a runtime-effect filter
whose input is a blur, `RuntimeEffectFilterContents` re-rasterizes the blurred
snapshot into a new texture (`ShouldRasterizeForRuntimeEffects`; the engine
comment names this exact case, `ComposeBackdropRuntimeOuterBlurInner`) before
the shader pass draws. The lens itself samples three times per pixel with
chromatic on.

**C3. A shared key removes flips.** With a `backdropGroupKey` used by two or
more filters, Impeller caches the first flip's texture and reuses it for the
rest of the group. In Scene D the planner (`appGlassBackdropGroups`, now fed
Hybrid's reach: 3 sigma + half the lens band + 1 px) shares one read between
the back button, trailing capsule and mini player. The tab bar keeps its own
read: its blur reaches the mini player painted just above it. Result: two
flips instead of four (tested).

**C4. Equal lens filters must not share a key.** When every filter on a
shared key is equal, Impeller renders it once over the whole cached texture
(`all_filters_equal`; runtime-effect equality is same effect and same uniforms).
Correct for a blur, wrong for the lens, whose geometry comes from its input
size. `appGlassSplitEqualFilters` gives a repeated lens size its own key. Scene
D's equal-size pair (mini player and tab bar) was already apart.

**C5. Hybrid was not observable.** No tier in the copied metrics and an
`unverified` path (fixed by section 2).

**C6. The tint was never painted.** `BoxDecoration` ignores `color` when a
`gradient` is set, so the tint colour and the tint slider had no effect on
Lightweight, Frosted or Full. The tint is now its own fill under the highlight.
A visual defect; one extra rounded-rect fill per surface.

### Checked and not a cause of the P50

- **Overlapping filters:** none of the four surfaces overlap.
- **Filter bounds:** each blur is bounded by its `ClipRRect`; the oversized
  part is the full-frame flip of C1, not the blur.
- **Shader compilation:** the program loads once, asynchronously; runs warm
  up for 5 s, and a Full matrix run waits for the lens. A first-use pipeline
  build could cause a spike, not a 60-second median.
- **Repaint regions:** the list scrolls under all four surfaces, so the whole
  stage changes every frame in every mode, A included.
- **Render-path probe:** the existing 500 ms tree census is UI-thread work, not
  raster. Hybrid no longer uses it.

### Hypotheses (need the device matrix)

- **H1.** C1's four flips are most of the 11.43 ms. Test: C−B and D−E.
- **H2.** The flips are memory-bandwidth bound. Estimate only: a 1080 x 2388
  RGBA8 target is about 10.3 MB, each flip is at least one full store plus one
  full redraw, so four flips are on the order of 80 MB per frame, about
  10 GB/s at 120 Hz, before MSAA. Not measured.
- **H3.** FrameTiming raster includes waiting for the GPU or the swapchain
  (earlier New Full Glass traces were blocked in `vkQueuePresentKHR`), so GPU
  cost shows up as raster time without naming a pass.
- **H4.** Frosted with a shared key blurs the whole cached frame once (equal
  filters, no input hint in the engine). That may cost more or less than four
  small blurs. Not part of A–E; select Frosted plus Shared backdrop manually.

## 5. Changes made (Task 4)

| Change | Why |
|---|---|
| Telemetry and render-path classification for Hybrid | C5 |
| Opaque tier (A) and the A–E matrix plan and report | Task 2 baselines |
| `backdropGroupKey` on Frosted and Full, planned by the existing planner | C1, C3: removes two of four flips in Scene D (variant E) |
| Equal-lens split rule | C4 correctness |
| Tint painted as its own fill | C6 |
| Zero-blur bypass (no `BackdropFilter` at sigma 0 without the lens) | Blur 0/1 evidence; honest telemetry |

The shared read is a selectable variant, off by default, so D and E can be
compared on the same device before it becomes the Hybrid default.

## 6. Device matrix (to fill from the matrix report)

Profile APK built with `--dart-define=SISTRUM_PERF_HUD=true`. Unlock: Settings
> About, tap the version 7 times. Record thermal state before and after
(`adb shell dumpsys thermalservice`).

| Variant | Valid runs | Raster P50 | P90 | P99 | Exceedance | Backdrop reads | Path |
|---|---|---|---|---|---|---|---|
| A Opaque | | | | | | 0 | opaque |
| B Tint | | | | | | 0 | tint |
| C Frosted | | | | | | 4 | blur |
| D Full | | | | | | 4 | lens |
| E Full, shared | | | | | | 2 | lens |

For per-pass GPU cost, capture D and E with Android GPU Inspector or Perfetto
GPU counters.
