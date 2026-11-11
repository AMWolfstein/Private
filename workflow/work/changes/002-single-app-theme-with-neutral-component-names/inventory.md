# Theme migration inventory

Scope is only the theme design system. These are candidate renames, not runtime changes. Recheck against the current map before execution.

| Current path | Intended neutral path | Disposition |
|---|---|---|
| `assets/shaders/mornye_selection_mask.frag` | `assets/shaders/app_selection_mask.frag` | rename candidate |
| `lib/controllers/mornye_glass_warmup.dart` | `lib/controllers/app_glass_warmup.dart` | rename candidate |
| `lib/screens/mornye_library_screen.dart` | `lib/screens/app_library_screen.dart` | rename candidate |
| `lib/screens/track_metadata_mornye.dart` | `lib/screens/track_metadata_layout.dart` | rename candidate |
| `lib/theme/mornye_icons.dart` | `lib/theme/app_icons.dart` | rename candidate |
| `lib/theme/mornye_theme.dart` | `lib/theme/app_theme.dart` | COLLISION: merge/choose responsibility |
| `lib/widgets/mornye_artist_header.dart` | `lib/widgets/app_artist_header.dart` | rename candidate |
| `lib/widgets/mornye_artwork_contrast.dart` | `lib/widgets/app_artwork_contrast.dart` | rename candidate |
| `lib/widgets/mornye_bottom_bar.dart` | `lib/widgets/app_bottom_bar.dart` | rename candidate |
| `lib/widgets/mornye_chrome.dart` | `lib/widgets/app_chrome.dart` | rename candidate |
| `lib/widgets/mornye_context_menu.dart` | `lib/widgets/app_context_menu.dart` | rename candidate |
| `lib/widgets/mornye_glass_lens_fade.dart` | `lib/widgets/app_glass_lens_fade.dart` | rename candidate |
| `lib/widgets/mornye_glass_preparation.dart` | `lib/widgets/app_glass_preparation.dart` | rename candidate |
| `lib/widgets/mornye_glass_press.dart` | `lib/widgets/app_glass_press.dart` | rename candidate |
| `lib/widgets/mornye_landscape_player.dart` | `lib/widgets/app_landscape_player.dart` | rename candidate |
| `lib/widgets/mornye_level_slider.dart` | `lib/widgets/app_level_slider.dart` | rename candidate |
| `lib/widgets/mornye_liquid_backdrop.dart` | `lib/widgets/app_liquid_backdrop.dart` | rename candidate |
| `lib/widgets/mornye_metadata_row.dart` | `lib/widgets/app_metadata_row.dart` | rename candidate |
| `lib/widgets/mornye_mix_banner.dart` | `lib/widgets/app_mix_banner.dart` | rename candidate |
| `lib/widgets/mornye_playback_button.dart` | `lib/widgets/app_playback_button.dart` | rename candidate |
| `lib/widgets/mornye_playback_time.dart` | `lib/widgets/app_playback_time.dart` | rename candidate |
| `lib/widgets/mornye_player_actions_sheet.dart` | `lib/widgets/app_player_actions_sheet.dart` | rename candidate |
| `lib/widgets/mornye_player_artwork.dart` | `lib/widgets/app_player_artwork.dart` | rename candidate |
| `lib/widgets/mornye_player_background.dart` | `lib/widgets/app_player_background.dart` | rename candidate |
| `lib/widgets/mornye_player_details_sheet.dart` | `lib/widgets/app_player_details_sheet.dart` | rename candidate |
| `lib/widgets/mornye_player_favorite_button.dart` | `lib/widgets/app_player_favorite_button.dart` | rename candidate |
| `lib/widgets/mornye_player_layout.dart` | `lib/widgets/app_player_layout.dart` | rename candidate |
| `lib/widgets/mornye_player_queue.dart` | `lib/widgets/app_player_queue.dart` | rename candidate |
| `lib/widgets/mornye_player_slider.dart` | `lib/widgets/app_player_slider.dart` | rename candidate |
| `lib/widgets/mornye_selection_pill.dart` | `lib/widgets/app_selection_pill.dart` | rename candidate |
| `lib/widgets/mornye_squircle_border.dart` | `lib/widgets/app_squircle_border.dart` | rename candidate |
| `test/mornye_artist_capsule_test.dart` | `test/app_artist_capsule_test.dart` | rename candidate |
| `test/mornye_artwork_contrast_test.dart` | `test/app_artwork_contrast_test.dart` | rename candidate |
| `test/mornye_bottom_bar_test.dart` | `test/app_bottom_bar_test.dart` | rename candidate |
| `test/mornye_collection_sheets_test.dart` | `test/app_collection_sheets_test.dart` | rename candidate |
| `test/mornye_context_menu_test.dart` | `test/app_context_menu_test.dart` | rename candidate |
| `test/mornye_detail_headers_test.dart` | `test/app_detail_headers_test.dart` | rename candidate |
| `test/mornye_glass_interaction_test.dart` | `test/app_glass_interaction_test.dart` | rename candidate |
| `test/mornye_glass_layout_test.dart` | `test/app_glass_layout_test.dart` | rename candidate |
| `test/mornye_glass_level_test.dart` | `test/app_glass_level_test.dart` | rename candidate |
| `test/mornye_glass_press_test.dart` | `test/app_glass_press_test.dart` | rename candidate |
| `test/mornye_icons_test.dart` | `test/app_icons_test.dart` | rename candidate |
| `test/mornye_landscape_player_test.dart` | `test/app_landscape_player_test.dart` | rename candidate |
| `test/mornye_library_actions_test.dart` | `test/app_library_actions_test.dart` | rename candidate |
| `test/mornye_library_browse_test.dart` | `test/app_library_browse_test.dart` | rename candidate |
| `test/mornye_loading_and_chrome_test.dart` | `test/app_loading_and_chrome_test.dart` | rename candidate |
| `test/mornye_menu_motion_test.dart` | `test/app_menu_motion_test.dart` | rename candidate |
| `test/mornye_playback_button_test.dart` | `test/app_playback_button_test.dart` | rename candidate |
| `test/mornye_playback_time_test.dart` | `test/app_playback_time_test.dart` | rename candidate |
| `test/mornye_player_background_test.dart` | `test/app_player_background_test.dart` | rename candidate |
| `test/mornye_player_queue_test.dart` | `test/app_player_queue_test.dart` | rename candidate |
| `test/mornye_search_glass_test.dart` | `test/app_search_glass_test.dart` | rename candidate |
| `test/mornye_theme_identity_test.dart` | `test/app_theme_identity_test.dart` | rename candidate |
| `test/widgets/mornye_clear_path_test.dart` | `test/widgets/app_clear_path_test.dart` | rename candidate |
| `test/widgets/mornye_glass_lens_fade_test.dart` | `test/widgets/app_glass_lens_fade_test.dart` | rename candidate |
| `test/widgets/mornye_glass_rules_test.dart` | `test/widgets/app_glass_rules_test.dart` | rename candidate |

## Core collisions and branches

- `lib/theme/mornye_theme.dart` → `lib/theme/app_theme.dart`: occupied by the outgoing Material builder; plan.md defines the temporary LegacyMaterialTheme transition.
- `dynamic_color_wrapper.dart` → `app_theme_wrapper.dart`; retain wrapper lifecycle, remove wallpaper acquisition.
- `MornyeAccent`, settings helpers, runtime glass types/providers and theme-specific fields become neutral; persisted strings retain old values.
- Shared `app_*.dart` files and generic screens contain style branches and are not listed as simple file renames. Inspect callers; retain the existing Mornye branch, not a constant-true selector.
- `material_expressive.dart`, `material_symbols.dart`, Material-only player wrappers/dependencies/assets: remove only after actual retained-consumer verification.

## Preserved identity and compatibility

- Product/brand Mornye, MornyeApp, `package:mornye`, Android package, app links, logos and old source provenance are not theme identifiers to replace.
- Persistent literals include `mornye_accent`, `mornye_accent_moved_to_blue`, `mornye_glass_outlines`; legacy `theme_style` and removed Material-setting keys are tolerated inert input.
- Media actions `mornye.favorite` and `mornye.shuffle`, drawable IDs, local data and backup keys/formats stay unchanged.

## Coverage and tests

- Text search matched300 lib/test files for `isMornye|AppThemeStyle|MornyeTheme|MaterialExpressive`; not all are edits and this does not prove reachability.
- Existing characterization/persistence/design-system/glass/player/layout tests are adapted or renamed. Material-only visual assertions may be retired with explicit replacement/disposition; shared behavioral assertions remain.
- Preserve icon mapping distinction between ordinary AppIcon and adaptive AppIcon, reduced-motion fallback specs, shader registration and custom font availability.
- No tests, source files or assets were changed while preparing this inventory.
