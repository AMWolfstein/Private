# Glass Engine V2 — GPU investigation and two looks (2026-11-04)

## Rendering architecture

- `AppGlass` (`lib/widgets/glass/thumb/app_glass_surface.dart`) is the only glass renderer. It has
  four modes: GROUND (a pre-blurred artwork ground, no live read), FROSTED (a clipped
  `BackdropFilter`), LIQUID (g1455 `GlassSurface`, refracting the host capture) and TINT (fill only).
- g1455 `GlassHost` (in `app.dart`) records one capture of the painted tree whenever its layer
  watch reports a change. Each LIQUID surface samples its own slot of that capture.
- Artist and album pages are wrapped in `AppArtistSurface`. When a saved video cover plays,
  `liveBackdrop` is true. The surface then skips `AppPageGround` and places `AppLiveVideoBackdrop`
  (a shared `BackdropKey`) and `AppLiveVideoBand` (whether the header band covers the controls).
- The header band (`AppHeaderBacking`) is one `ClipRect` + `BackdropFilter` over the pinned
  toolbar's flexible space. It is shown only while content scrolls under, and it fades in 180 ms.
- Header controls (`AppHeaderCircle`, `AppHeaderActions`, profile placeholder) are LIQUID. They
  are scoped by `AppHeaderControls`.

## Confirmed expensive paths

1. **A video is invisible to the host capture.** g1455 records a `TextureLayer` as a hole
   (`proxy_walk.dart`), so LIQUID over a video refracts the still cover underneath it. The video's
   header controls therefore fall back to FROSTED, which reads the live page.
2. **Every FROSTED read copies the whole screen while the video plays.** In Impeller each
   `BackdropFilter` ends the render pass and copies the backdrop (`Canvas::SaveLayer`,
   `FlipBackdrop`). The clip bounds the blur, not the copy. The copy repeats every frame because
   the video changes every frame.
3. **The video makes the host recapture every frame.** g1455's layer watch reports an unknown
   layer (`TextureLayer`) as changed on every frame (`proxy_layer_watch.dart`). This is
   independent of Sistrum's glass mode: it also happens with Artist glass disabled, which measured
   3.9–4.4 ms raster P95. So it is not the dominant cost.

## Changes and expected effect

| Step | Commit | Copies per frame (video on, scrolled under) |
|---|---|---|
| LIQUID → FROSTED fallback, unshared | `8fbf597` | band 1 + controls 3 = 4 |
| Controls share one key (`BackdropGroup`) | `d9d4658` | band 1 + controls 1 = 2 |
| Controls inside a fully shown band draw fill only | `87456a9` | band 1 = 1 |

With Band blur off, or while the band is hidden, the controls keep their single shared copy.

The device measurements after `d9d4658` were 10.8 ms raster P95 with Band off and 18.2 ms with
Band on. They are consistent with the cost scaling with the number of page copies. The effect of
`87456a9` is not measured yet.

## Counter semantics (performance HUD)

- `reads`: `BackdropFilterLayer`s in the last composited layer tree, across every view. It counts
  layers, not GPU work.
- `copies`: an estimate of the engine's page copies. Unkeyed reads count one each; reads that share
  a `BackdropKey` count one per key. That is Impeller's rule for shared backdrops: one copy, plus
  one shared blur when all filters are equal. It is derived from the layer tree, not measured on
  the GPU.
- `host snapshots`: g1455 `GlassProxyHandle.snapshots`, the `toImageSync` rasterizations of the host
  capture (one per recorded frame, or two with a split blur pass). It is counted from the last
  window restart over wall time, not over the 300-frame window. These are real GPU rasterizations,
  but at the proxy's reduced resolution.

## Two looks, one engine

`AppGlassLook` (`app_glass_look.dart`): BitChord-inspired (the default since the owner's 2026-11-04 decision) and Sistrum's own. Both use the
same modes, capture, shaders and surfaces. The BitChord look is read from BitChord's
`ui/components/LiquidGlass.kt`, which uses blur 8 dp at 0.33 resolution, saturation 1.5, a lens
of 0.5 × 48 dp height and amount, tint 0.4, `Highlight.Default`, and a 0.5 dp white 10% edge. It
is translated as follows:

- LIQUID lens: g1455 `GlassOptics(thickness: 24, strength: -50)` (default 21 / −58.2).
- Blur: sigma 5 for FROSTED, LIQUID and the header band. BitChord's 8 dp is a `RenderEffect`
  radius, which is sigma 0.57735 × 8 + 0.5 = 5.1. This look is allowed below Sistrum's sigma 6 by
  an owner override (2026-11-04).
- Tint: BitChord's surface tint, 0.4 of `#121212` (dark) or `#FAFAFA` (light), replaces the fill
  of light glass (controls, chips, header buttons). Slabs that hold text or navigation
  (`strongTint`: menus, sheets, the bottom bar) keep their own opaque fill, as BitChord's own menus
  keep a 0.80 slab (`MENU_FROST_ALPHA`); the contrast tests over black and white pages require it.
  Nested glass keeps its own fill.
- FROSTED: the saturation 1.5 matrix is composed onto the same blur. It stays one read, with a
  colour matrix over the blurred pixels.
- Rim: a white 10% hairline replaces the dark contact edge.
- Chromatic aberration: BitChord's lens samples red and blue at different refraction offsets,
  weighted by `x * y` so the effect is strongest at the corners. g1455's shader has no dispersion,
  so the rim paints an approximation: a warm stroke just inside the edge and a cool one a step
  further in, additive, faded toward the middle by a radial mask. It is strokes only, with no read
  and no new shader. It does not bend the image apart the way BitChord's does.

Every launch starts in the BitChord look. The developer HUD can switch to Sistrum's look for
comparison; the switch is never persisted, because Appearance has no glass controls (`AGENTS.md`).

## Regression risks

- During the band's 180 ms fade the controls switch between their own read and fill only. The
  band reports after each frame, so they switch one frame late.
- Inside the band, the blur under the controls is the band's sigma 6, not their own sigma 6 over
  the band (about 8.5 combined). This is a slight difference, visible only side by side.
- Impeller's shared-backdrop blur covers the whole screen once, not three small regions.

## Profiling procedure (device)

Profile build, same device, same artist and video, warm-up past the HUD's 30 frames, 300 frames
per run, three runs. Configurations:

- Video ON, Glass NORMAL, Band ON;
- Video ON, Glass NORMAL, Band OFF;
- Video ON, Artist glass DISABLED.

Run each with Look: Sistrum, then Look: BitChord. Record build and raster P50/P95/P99, jank,
`reads`, `copies` and host snapshots from the HUD's Copy line.

## Band blur over a live video: phase investigation (2026-11-04)

### What the device numbers already show

The HUD line's `build=` and `raster=` figures are **average/P90/P99**, not P50/P95/P99
(`AppPhaseStats`).

| Test | reads/copies (last frame) | raster avg/P90/P99 | jank |
|---|---|---|---|
| A: glass normal, Band on | 5/1 | 7.1/17.4/24.4 | 11.3% |
| B: glass normal, Band off | 5/1 | 3.9/5.0/7.3 | 0.0% |
| C: artist glass disabled | 0/0 | 3.7/4.6/5.4 | 0.0% |

- B is within 0.4 ms of C, so the five grouped reads over the video (toolbar controls, Favorite,
  Shuffle; one shared copy) cost almost nothing.
- A and B differ only in the band's `BackdropFilter`, and in the toolbar controls switching
  between their shared read and fill-only as the band settles (`AppLiveVideoBand`).
- `reads`/`copies` describe the **last** frame only. A ended with the band hidden.
- A's average is low (7.1) while its P90 is high (17.4). So most frames were cheap and roughly one
  in ten was expensive. That fits frames during the band's presence or its 180 ms fades. It
  doesn't fit a uniformly expensive state.

### Candidate causes, from the code

1. **The fade blurs at full resolution.** The band animates its sigma (`sigma × amount`).
   Impeller picks the blur's downsample from the physical sigma
   (`GaussianBlurFilterContents::CalculateScale`):
   - sigma ≤ 4 px: no downsampling;
   - 1/2 resolution until about 11 px;
   - 1/4 beyond that.

   At sigma 6 dp on a ~2.75× screen, the first third of each fade blurs the band at full
   resolution and the next third at half. The settled band blurs at a quarter.
2. **Two reads during the fade.** The toolbar controls keep their own read until the band is
   fully shown, and resume it as soon as it starts to leave. During the 180 ms there are two page
   copies, not one.
3. **The steady band read itself.** One unkeyed full-screen copy and a blur clipped to the band,
   every frame while the band shows.

None of these is established by measurement yet, so this commit makes no rendering change.

### Phase split (developer HUD)

While the HUD is open, every frame is filed under the band's phase at the time it was built:
`hidden`, `transition` (fading in or out), or `stable` (fully shown). Each is tagged `+scroll`
while a vertical scroll is active (`AppBandPhaseDiagnostics`). The HUD shows raster
P50/P95/P99 and raster-jank per bucket, and Copy appends them.

How frames are matched: frames are matched to their timing by the engine's vsync target time,
which is what `onBeginFrame` receives; each `FrameTiming` carries the matching vsync start. Frames
the engine drew without a Dart frame (a new video frame redraws the last scene) take the phase in
effect at the time and are counted as `unmatched`.

These are Dart-side frame timings split by phase. They are not GPU copy or pass counts.

### Procedure

On a profile or release build, open the artist page with its video playing and open the HUD.
Leave Band blur on, press Reset, and wait out the 30-frame warm-up. Then:

1. Scroll down until the band is shown and hold still for ~3 s.
2. Scroll up and down across the band threshold slowly ~5 times.
3. Scroll back to the top and hold ~3 s.

Press Copy. Repeat three times.

How to read the result:

| Result | Cause | Fix it points to |
|---|---|---|
| `transition` P95 high, `stable` low | 1 or 2 | Keep the fade off the full-resolution blur, or stop the controls switching back mid-fade |
| `stable` high | 3 | The band read itself |

For GPU-level proof (render passes, texture copies), capture a Perfetto system trace with GPU
render stages, or use Android GPU Inspector on the same steps.

### Result of the phase split and the fix (2026-11-04)

Device, Glass normal, Band on, video on (raster P50/P95/P99 per phase):

| Phase | Frames | Raster P50/P95/P99 | Jank |
|---|---|---|---|
| hidden+scroll | 154 | 4.5/14.3/17.9 | 2.6% |
| **transition+scroll** | 169 | **13.9/22.7/24.7** | **34.3%** |
| stable+scroll | 253 | 3.1/4.3/7.8 | 0% |

Controls:

| Condition | Transition+scroll P95 |
|---|---|
| Band off | 4.3 |
| Artist glass disabled | 4.1 |

The settled band read is cheap; frames while it fades are expensive, and their P50–P95 spread is
wide. That points to a cost that varies within the fade itself. The band animated its blur
**sigma** (`sigma × amount`). Impeller chooses the blur's resolution from its sigma
(`CalculateScale`: ≤ 4 px full resolution, then 1/2, then 1/4 for the settled sigma 6). So most
of each fade ran a full- or half-resolution blur over the backdrop.

**Fix** (`appHeaderBandFilter`, `app_floating_header.dart`):

- The blur keeps its settled sigma for the whole fade.
- The 180 ms fade is the blurred backdrop's alpha (`ImageFilter.compose` with an alpha-scaling
  colour matrix).
- Impeller draws the filtered backdrop into the band's layer and composites that layer over the
  page, so the alpha is a crossfade from sharp to blurred.
- A settled band reuses one plain blur per sigma.

Visual difference: during the 180 ms the band crossfades from sharp to blurred instead of its blur
radius growing from zero. The duration, the tint fade and the settled look are unchanged.

### HUD windows

- The main line (`build=`/`raster=`, avg/P90/P99) covers the **last 300 frames**.
- The band phase lines cover **every frame since the last Reset** (or mode or video change). That
  is why their counts add up to more than 300. The HUD labels them "since Reset" and Copy adds
  `band window=since-reset`.
- Both skip the 30 warm-up frames.
