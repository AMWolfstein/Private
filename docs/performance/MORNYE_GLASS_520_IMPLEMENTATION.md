# Mornye Liquid Glass 5.2.0: implementation record

Branch: `mornye-reboot`. Scope: Mornye theme only. The Material theme, its
styling, components and glass behaviour are unchanged.

## Status

Source changes, commits and automated checks are complete. **No measured
performance result exists for these changes.** Every expected mechanism below
is a design hypothesis from reading the package and the app source. The
baseline numbers at the end were measured before this work and are not
post-change results.

## Package

| Package | Before | After | Notes |
| --- | --- | --- | --- |
| `liquid_glass_easy` | 5.1.0 | 5.2.0 | Only pin and lock entry changed. |

Breaking-change review (5.2.0 changelog and source diff against 5.1.0):

- New `LiquidGlassLens.opacity` defaults to `1`: no visual change.
- The shader's rim lift is controlled by `rimLiftOnDark`, default `true`:
  the same as 5.1.0.
- Tab bar defaults changed in 5.2.0. Mornye does not use `LiquidGlassTabBar`,
  `LiquidGlassScaffold` or `LiquidGlassBlender`, so those defaults do not apply.
- Shader source line endings and comments changed; numeric behaviour did not.

## Commits, in order

| Stage | Commit | Message | Paths |
| --- | --- | --- | --- |
| 1 | `0e120b6` | chore(glass): upgrade liquid_glass_easy to 5.2.0 | `pubspec.yaml`, `pubspec.lock` |
| 2 | `7232920` | refactor(glass): centralize renderer configuration without visual changes | `lib/widgets/mornye_liquid_backdrop.dart`, `lib/widgets/mornye_chrome.dart`, `lib/widgets/mornye_glass_preparation.dart`, `lib/widgets/mornye_selection_pill.dart`, `test/mornye_bottom_bar_test.dart`, `test/mornye_glass_level_test.dart`, `test/widgets/mornye_glass_rules_test.dart` |
| 3 | `4c85283` | perf(glass): add verified batched blur renderer options | `lib/models/settings.dart`, `lib/models/settings.g.dart`, `lib/providers/settings_provider.dart`, `lib/widgets/mornye_liquid_backdrop.dart`, `lib/widgets/mornye_chrome.dart`, `lib/screens/settings/performance_hub_page.dart`, `test/widgets/mornye_glass_batch_renderer_test.dart` |
| 4 | none | skipped, see below | |
| 5 | `580604a` | test(glass): pin clear-path mapping and held-lens clarity | `test/widgets/mornye_clear_path_test.dart` |
| 6 | none | skipped, see below | |
| 7 | none | skipped, see below | |
| 8 | this commit | docs(glass): record implementation and phone verification checklist | `docs/performance/MORNYE_GLASS_520_IMPLEMENTATION.md` |

Stage 5 is a test-only commit. The source review found nothing that could be
streamlined without evidence, so the commit does not claim any optimisation.

## What changed, and the expected mechanism

### Stage 2: one place for the glass mapping (behaviour preserved)

`MornyeGlassRules` now owns the clarity-to-render mapping that was spread over
the chrome, the glass preparation gate and the held lens:

- backdrop sampling thresholds: above 0.2 for liquid, above 0.5 for frosted;
- blur budget index and sigmas: frosted uses sigma 3; liquid uses sigma 16
  below 0.6, 6 from 0.6, and 2 from 0.9;
- shared blur filters, so a clarity animation never rebuilds them;
- tint strength `(1 - c)^2`, clear-fill mix `clamp((c - 0.2) / 0.8)`, and
  dispersion `1.32 * c * effect`;
- the shader-lens support check, with the test override.

Mechanism: none. This is a readability and drift guard. Unit tests cover
0, .2, .25, .5, .6, .75, .9 and 1.

### Stage 3: renderer options for batched lenses

`LiquidGlassBatch` now receives an explicit `mode` and `blurMethod` from the
selected option. The default (`separate_pass`) passes the same values the
package already uses, so the default look is unchanged.

| Option (`glassBatchRenderer`) | Batch mode | Blur method | Source-verified behaviour | Hypothesis |
| --- | --- | --- | --- | --- |
| `separate_pass` (default) | `separatePass` | `engine` | One read for the batch, a blur pass over that copy, then a shader pass per member. | Reviewed look; the reference for comparisons. |
| `single_pass` | `singlePass` | `engine` | Blur folded into each member's keyed pass (`ImageFilter.compose`). | May reduce passes; not measured. |
| `shader_blur` | `separatePass` | `shader` | Blur inside the lens shader; no blur pass. | Fewest passes; grain differs from the Gaussian, so it is a diagnostic, not a visual match. |

The selector is in **Performance Hub > Glass batch renderer**. It persists
as `glassBatchRenderer` in settings. Unknown values fall back to the default.

### Stage 4: bottom bar and mini player (skipped)

Read from source, not measured:

- The bar already wraps the player and the tabs in one `LiquidGlassBatch`
  with a `BackdropGroup`. Those surfaces already share one backdrop read.
- The folding capsules take `LiquidGlassBatch(child: surface)` on purpose:
  they cross the tab bar, so they need their own read. Merging them into the
  outer batch would change the overlap.
- The held lens uses `LiquidGlassBatch.exclude` so it refracts the page and
  the icons, not the batch copy.
- `LiquidGlassBlender(smoothness: 0)` would fuse separate capsules into one
  shape. That changes the look, so it was not used.

No redundant read was found that could be removed without changing the look.

### Stage 5: clear-path analysis (tests only)

Differences between clarity 0.75 and 1.0 (the only inputs that change):

- blur budget sigma 6 to 2;
- dispersion 0.99 to 1.32;
- tint strength 0.0625 to 0;
- clear-fill mix 0.69 to 1.0.

The held lens is forced to clarity 1 and no blur, so it is identical at every
slider position. Nested glass does not sample again (`insideGlass`), and the
custom rim is skipped while the optical lens draws its own. No duplicate
filter or layer was found. No toggle was added because nothing is ambiguous.

### Stage 6: artist and album headers (skipped)

- The header glass pieces (back button, action capsule, circle buttons) are
  in a `SliverAppBar` `leading` and `actions`. A non-sliver `LiquidGlassBatch`
  cannot wrap those slots alone. Wrapping the whole scroll view would put every
  lens in the page into one batch, including any overlapping glass, which
  risks the refraction fidelity the brief protects.
- `ImageFiltered` on the artist artwork is an artwork blur driven by collapse
  and fade, not by the clarity slider. It is not attributed to the slider and
  was not changed.
- Animated artwork and `ShaderMask` were not changed.

### Stage 7: search, Now Playing, overlays (skipped)

- `lens.opacity` (5.2.0) could fade a glass surface, but the current
  reveal-driven fade lerps the fill and scales refraction, so using `opacity`
  would change the transition look. Not visually equivalent; not used.
- Overlays keep their existing sampling decisions. Context menus and sheets
  still isolate their backdrop; they are not batched with the page.
- The crude symbol sweep of the changed glass files found no unused wrapper
  to remove.

## Chosen defaults and switch paths

- Default renderer: `separate_pass` (the package default, reviewed look).
- Diagnostic switch: Performance Hub > Glass batch renderer. Change it
  without rebuilding; it applies when a batch builds.
- Unchanged defaults: `LiquidGlassConfiguration.blurMethod` (engine),
  `batchBlurMethod` (engine), `batchMode` (separatePass), `shapeCache` (true).

## Verification

- `flutter analyze`: run in stage 8 (see the final report).
- Targeted tests: the glass widget tests, the rules and renderer tests, the
  clear-path tests, the Performance Hub and settings tests.
- Full `flutter test` on the completed source: see the final report.
- Release APK: built only in the final stage, after this commit.

## Phone verification checklist (manual, not run by the agent)

Use the final APK on the Moto g75. Each row needs a yes/no and a note.

| Area | Check |
| --- | --- |
| Home | Clarity 0 / .25 / .5 / .75 / 1.0: tint, refraction, blur look, no flicker when the slider moves |
| Artist | Same five positions; header buttons and action capsule; collapse and expand |
| Album | Same five positions; header buttons; collapse and expand |
| Clear swipe | Slide clarity to 1.0 and back while the bar is visible |
| Hold / drag | Hold the selection pill and drag across tabs at 0.75 and 1.0 |
| Collapse | Bottom bar fold and expand at 0.75 and 1.0 |
| Motion artwork | Animated artwork on and off on Artist and Album |
| Search | Search field at 0.75 and 1.0; results over artwork |
| Now Playing | Surfaces and controls at 0.75 and 1.0 |
| Menus | Context menu and bottom sheet at 0.75 and 1.0 |
| Light / dark | Repeat the main rows in both themes |
| Renderer | Compare `separate_pass`, `single_pass`, `shader_blur` on Home and Artist; note the look, not only speed |
| FPS HUD | Optional: enable the HUD and record frame cost per renderer |
| Perfetto | Optional, only if you choose to capture later |

## Known baseline (measured before this work, not post-change)

Device: Moto g75, Android 16, 60 Hz, ARM64 release. Median raster P95 ms
across Clarity 0 / .25 / .5 / .75 / 1:

| Screen | Clarity 0 / .25 / .5 / .75 / 1 | Slow-frame % |
| --- | --- | --- |
| Home | 4.3 / 17.4 / 17.4 / 16.7 / 21.4 | 0 / 10.7 / 8.7 / 5 / 59.5 |
| Artist | 11.3 / 39.6 / 39.5 / 33.5 / 38.8 | 1.1 / 100 / 100 / 95.2 / 100 |
| Album | 4.0 / 29.3 / 29.3 / 24.4 / 27.9 | 0 / 91.7 / 92.3 / 90.2 / 91.8 |

Search, active Now Playing and Sheets/Menus were not fully measured.

## Reverting a stage

Each stage is its own commit. To undo one, revert only that commit, then run
`flutter pub get`, `flutter analyze` and the affected tests:

```sh
git revert 4c85283   # stage 3: renderer options (also remove the setting if needed)
git revert 7232920   # stage 2: mapping refactor
git revert 0e120b6   # stage 1: back to liquid_glass_easy 5.1.0
git revert 580604a   # stage 5: clear-path tests only
```

Revert in reverse order when several are undone. Stage 3 also changed
`settings.g.dart`; revert it with its commit so the generated code matches.
