# Theme Layer

The app has one visual design: the retained Mornye design. Its theme is
`AppTheme`, a `ThemeExtension` with a `ThemeData` builder. There is no style
choice; saved preferences for the removed alternative design are read as
inert input and never written again.

The design still produces a Flutter `ThemeData` with `useMaterial3: true`, so
widgets read `Theme.of(context).colorScheme` and `textTheme` the same way.
The design maps its colors onto Material 3 `ColorScheme` roles.

## Files

| File | Role |
| --- | --- |
| `lib/theme/app_theme_wrapper.dart` | `AppThemeWrapper`, used by `lib/app.dart`. Builds the light and dark `ThemeData` from the saved mode, font, accent and glass outlines |
| `lib/theme/app_theme.dart` | `AppTheme`: the design's `ThemeExtension`, its `ThemeData` builder, `AppAccent`, and `AppSettingsTheme` |
| `lib/theme/app_tokens.dart` | `AppTokens`, a `ThemeExtension` with the shared radii, spacing, cover sizes and header metrics |
| `lib/theme/app_icons.dart` | `appIconFor` (Material icon to Cupertino icon) and `context.adaptiveIcon` |
| `lib/theme/material_expressive.dart` | `MaterialExpressiveScope`, the bridge to the Material UI and Material 3 Expressive packages used by the expressive components |
| `lib/theme/app_motion.dart` | `AppMotionSpec`, `SpringCurve` and `AppMotion` spring presets. The call site's fallback spec is used |
| `lib/theme/cover_palette.dart` | `CoverPalette`, `HeaderPalette`, `CoverPaletteBuilder` and `CoverSourceColorBuilder`: colors extracted from artwork |
| `lib/theme/player_artwork_theme.dart` | `PlayerArtworkTheme`: the current track's artwork scheme for the player surfaces, through a local `Theme` |

## How the Theme Is Built

`AppThemeWrapper` watches `themeProvider` and the custom font provider.

`AppTheme.build(brightness, ...)` takes the accent (`AppAccent`, blue by
default), the system-font and custom-font choices, and the glass outlines. It
seeds a `ColorScheme` from the accent and overrides the roles with grouped
colors (for example `#F2F2F7` and `#1C1C1E`). Text uses Cupertino styles. The
font is the custom font when one is set; otherwise the Cupertino system font
when the system font is chosen, and Inter by default. It registers its own
`AppTheme.tokens`, a copy of `AppTokens.standard` with its own radii and
large title sizes.

`AppTheme.build` caches up to 16 base themes; changing only the glass outlines
reuses the cached theme. Use `AppTheme.fromContext` to rebuild a local surface
(another brightness or chrome color) without losing the user's preferences.

## Using the Layer in Widgets

- Read tokens with `context.tokens`, not `Theme.of(context).extension`. It
  falls back to `AppTokens.standard` outside a themed subtree.
- Keep `Icons.*` at call sites and pass them through `context.adaptiveIcon`;
  the design then shows the Cupertino glyph from `appIconFor`.
- Wrap settings pages in `AppSettingsTheme` for inset grouped surfaces.

## Stored Preferences

Keys and values for accent, theme mode, fonts, lyrics and glass outlines are
unchanged. Keys from the removed options (`theme_style`, `use_dynamic_color`,
`seed_color`, `use_amoled`) are read as inert input and never written again.
The Dart constants keep their stored literal values; see
`lib/models/theme_settings.dart`.

## Tests

`test/design_system_test.dart` checks the shared components on the design, and
`test/theme_storage_contract_test.dart` pins the stored keys, defaults and the
one-time accent move.
