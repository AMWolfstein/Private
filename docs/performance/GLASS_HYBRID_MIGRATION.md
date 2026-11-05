# Sistrum Hybrid: first-party glass migration map

Status: developer-only Glass POC. Not used by production screens.

## Ownership

| Piece | Owner | Notes |
|---|---|---|
| Lightweight tier | Sistrum | DecoratedBox only; no backdrop read. |
| Frosted tier | Sistrum (Flutter SDK) | `BackdropFilter(ImageFilter.blur)` + material. |
| Full tier lens | Sistrum | `shaders/sistrum_lens.frag` via `ImageFilter.shader`, composed after a blur. |
| Full tier fallback | Sistrum | Blur-only when refraction is off, the program is not loaded, or shader filters are unsupported. |
| Tint, edge, highlight | Sistrum | Plain `BoxDecoration`. |
| `liquid_glass_renderer` | third party | Still used by the POC's New Full / New FakeGlass modes only, not by Hybrid. |
| `liquid_glass_widgets` | third party | Still used by Liquid Glass and Reference Glass POC modes only. |

## Rendering primitives

- Blur, tint, border, highlight: Flutter public APIs.
- Lens refraction and chromatic split: custom fragment shader (`shaders/sistrum_lens.frag`). Impeller only.
- Saturation: not implemented. Flutter has no colour-matrix stage for backdrop filters.

## Reduced-resolution sampling

Not implemented. `BackdropFilter` cannot downsample its input, so the "0.33" scale used by BitChord's Haze is not reproduced. A real reduced-resolution pass needs a capture to an image at a lower pixel ratio (`RepaintBoundary.toImage`), which costs a GPU readback and is out of scope for this step.

## Blockers

- Shader filters need Impeller; on other engines the Full tier falls back to blur.
- The shader is compiled at build time, so a shader compile error will appear only on a device or in an Impeller build. Not verified on hardware yet.
- No device measurements exist for Hybrid. Do not claim 120 FPS.

## Licensing

- BitChord's Liquid Glass and Haze references (Apache-2.0 per source header) were used as concepts only. No source was copied into the shader.
- `liquid_glass_renderer` is MIT; `liquid_glass_widgets` licence was not confirmed in this audit.

## Next steps

1. Measure Full tier on a device in the standard scene before any production use.
2. Decide whether to keep the Full tier's blur at the native size or add a capture pass.
3. Replace or retire the POC's package modes only after their usages are audited.
