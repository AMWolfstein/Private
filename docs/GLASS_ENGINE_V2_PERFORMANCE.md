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

`AppGlassLook` (`app_glass_look.dart`): Sistrum (the default) and BitChord-inspired. Both use the
same modes, capture, shaders and surfaces. The BitChord look is read from BitChord's
`ui/components/LiquidGlass.kt`, which uses blur 8 dp at 0.33 resolution, saturation 1.5, a lens
of 0.5 × 48 dp height and amount, tint 0.4, `Highlight.Default`, and a 0.5 dp white 10% edge. It
is translated as follows:

- LIQUID lens: g1455 `GlassOptics(thickness: 24, strength: -50)` (default 21 / −58.2).
- FROSTED: the saturation 1.5 matrix composed onto the same blur. One read; a colour matrix over
  the blurred pixels.
- Rim: a white 10% hairline instead of the dark contact edge.
- Not taken:
  - the blur radius: Sistrum keeps sigma 6, never lower;
  - the 0.4 tint: Sistrum's fills hold its contrast;
  - chromatic aberration: g1455 has no parameter for it.

The look is a developer HUD switch and is never persisted, because Appearance has no glass
controls (`AGENTS.md`).

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
