# Retire the alternative design, preserve the current app presentation

## Summary

The code currently combines two theme builders and many shared widgets/screens that select style locally. Renaming only the obvious files leaves the alternative design, persistence/defaults and dependencies alive. Promote the current Mornye implementation to the canonical App theme, migrate names with collisions handled explicitly, make bootstrap/settings select it unconditionally, then remove inactive alternative branches and proven-exclusive dependencies. This document authorizes no execution.

## Current system (target20ff0a7c)

- lib/models/theme_settings.dart:34 defines AppThemeStyle;:45 and:73 default to Material. ThemeSettings:127 serializes theme_style and current Mornye preference keys. lib/providers/theme_provider.dart:82 owns the existing accent migration marker;:99 loads bootstrap state;:137-158 replays edits made during async load, and:173 persists snapshots.
- lib/theme/app_theme.dart:6 currently defines the Material AppTheme builder. lib/theme/mornye_theme.dart:10 is a separate ThemeExtension with a cached builder(:120), its own tokens(:88), palette/typography and context.isMornye(:474). These names collide if the latter is blindly renamed AppTheme.
- lib/theme/dynamic_color_wrapper.dart:43 switches builders. lib/providers/theme_provider.dart:15-65 owns dynamic-wallpaper requests. lib/app.dart:15 imports the wrapper and:272 registers material_ui localization. Removing a picker alone does not remove these paths.
- lib/theme/material_expressive.dart:9 gates an alternative component/motion stack. lib/theme/app_motion.dart imports that package, but the existing Mornye path uses the call-site fallback motion. lib/widgets/app_icon.dart:64 has a separate Material-symbol path; Mornye preserves normal glyphs unless explicitly adaptive. Keep that distinction.
- lib/providers/runtime_profile_provider.dart:35 defines flat/frosted/liquid glass choices. These are performance variants within the retained design, not obsolete style selection.
- lib/main.dart:321 and lib/providers/playback_notification_provider.dart:23 select notification presentation; lib/services/playback_notification.dart:8 stores the Dart style flag. Its custom action IDs remain mornye.favorite/mornye.shuffle and its Mornye icons already use existing Android drawable IDs. No native message-schema change is necessary.
- lib/models/settings.dart:412 selects the player-cover default by style; preserve the current Mornye default and explicit supported cover choices rather than retaining the Material fallback.
- pubspec.yaml:136 registers assets/shaders/mornye_selection_mask.frag; lib/widgets/mornye_selection_pill.dart:95 loads the exact asset path. These references must move together.
- Dedicated files and rename/collision candidates are listed in inventory.md. The initial text search finds300files across lib/test matching isMornye/AppThemeStyle/MornyeTheme/MaterialExpressive; that is a search scope, not a claim every file needs editing or proof of reachability.

## Design

### Canonical theme and collision strategy

Canonical lib/theme/app_theme.dart / AppTheme will contain the present Mornye ThemeExtension and builder, not the existing Material builder. During the compilable rename step, move the existing Material builder to temporary lib/theme/legacy_material_theme.dart / LegacyMaterialTheme and update only its current callers. The temporary implementation is removed with the alternative branch before completion. Never commit two AppTheme definitions or a compatibility facade that preserves Material selection indefinitely.

Rename MornyeAccent to AppAccent, MornyeSettingsTheme to AppSettingsTheme and theme-specific provider/helper/field names to neutral names. Existing AppTokens/AppMotion and app_ widgets are reused, not replaced wholesale. Their final canonical/default values must reproduce current Mornye behavior, including a safe unthemed test/preview fallback; do not accidentally retain Material token geometry when the marker extension disappears.

Rename the wrapper to app_theme_wrapper.dart / AppThemeWrapper. It watches retained preferences/custom font state and builds the current light/dark app themes directly. Remove dynamic-wallpaper request/settle startup and Material color conversion. Keep the same stable parent/provider lifetime, no duplicate root rebuild or resetting Navigator/player state.

### Component, screen, asset and test names

Use the inventory's path map: mornye_*.dart → app_*.dart for theme widgets/controllers/screens; matching Mornye-prefixed theme classes → App-prefixed classes; runtime glass provider/enum names also become neutral. track_metadata_mornye.dart becomes track_metadata_layout.dart with its part directives updated. Rename the selection shader and every pubspec/FragmentProgram/test reference in the same task. Recheck target path/symbol collisions at task start.

Where app_ components already exist, keep their API and promote the current retained branch inside them. Dedicated promoted widgets can remain separate if responsibilities differ; do not merge unrelated slider/player structures merely to reduce file count. Product entry class MornyeApp, package:mornye, Android com.zarz.mornye, brand/logo files, deep-link schemes and compatibility strings are not alternate-theme implementations and remain unchanged.

### Single-design startup and saved settings

After neutral renames, make every bootstrap path use the App theme immediately, including fresh/default, legacy Material, unknown/missing style, foreground and headless notification presentation. Retire AppThemeStyle, the style setter/selector and style-based default lookups after consumers no longer need them. Intermediate rename commits may still select the two builders; the final tree cannot.

Retain theme_mode, fonts, accent, glass outlines and lyrics scale/blur/offset using their existing stored string keys. Rename Dart constants/fields/setters only. Preserve the current accent resolver: migrated-marker=true preserves the selected valid accent, marker=false keeps the current one-time legacy red→blue behavior, invalid/missing accent uses the current blue fallback. Test that identifier renames do not rerun or reset the migration. Preserve async edit replay and serialized snapshot saves, with failed writes leaving last usable values.

Treat theme_style, use_dynamic_color, seed_color and use_amoled as ignored legacy input, not active selection. Do not bulk-clear preferences; old persisted values may remain inert. ThemeSettings.fromJson accepts older supported payloads without restoring Material. Its new output emits supported retained fields, not an active style selector; no new backup/export feature is introduced. Existing library/backup formats are unchanged. The color/AMOLED options used only by the removed design disappear from Appearance; retained font/lyrics/glass/mode/accent controls remain.

### Retained behavior and branch elimination

Pin the current Mornye visual/interaction behavior before replacing it. Collapse isMornye / AppThemeStyle branches by retaining their present Mornye arm, then remove the predicate/selector code once no consumer requires it. Do not simply turn a boolean getter into true and leave both designs. Preserve real conditionals for brightness, orientation, contrast, disabled controls, reduced motion, user cover choice and runtime glass level.

Promote the current Mornye player portrait/landscape, artwork surfaces, menus, sheets, loading/chrome, search/library/detail/settings and metadata layout branches. Preserve shared playback/media actions, selection/file operations, back/overlay order, TV focus, touch targets and semantics. Keep ordinary vs adaptive icon mapping identical; do not convert every Icons.* glyph just because Material-style symbol rendering is removed.

Notification appearance uses the existing Mornye icon selection unconditionally; remove the internal style flag and background style read, keeping custom action IDs, controls ordering, extras, Android drawable IDs and audio-handler ownership unchanged. No native API/channel rename or playback-engine edits are planned.

### Dependency and deletion proof

Remove Material-only material_ui/material_3_expressive adapters, Material-symbol conversion, old builder/wrapper paths and exclusive settings/localizations only after import and caller checks. app_motion.dart must retain the exact current Mornye fallback specs/reduced-motion semantics; do not delete physics or a shared helper if a retained component actually uses it. PlayerArtworkTheme and artwork palette code are inspected separately: remove only the Material-only wrapper and keep palette/HCT/contrast algorithms used by retained screens.

Recheck all imports and pubspec asset/font consumers before dropping dependencies. material_color_utilities, Flutter Material SDK imports, uses-material-design and default Icon inputs may still be required. Fonts exposed through retained custom-font selection remain even if once used as a Material default. Remove a font/asset/package only with an explicit retained-consumer disposition; generated registrants/lockfiles are regenerated by supported tooling, not hand-edited to hide dependencies.

Tests for Material-only visuals may be retired with a documented replacement/disposition. Keep and adapt shared interaction, persistence, player/lyrics/notification and accessibility assertions; failures are not permission to drop tests. Rename dedicated theme tests/imports with the source. Add a scoped residual check on theme identifiers/import paths/asset paths; exempt actual branding and the exact persisted/wire literals, not broad substrings that hide leftovers. Do not ban the word Material in framework APIs or historic documents.

### Ownership, compatibility and boundaries

ThemeNotifier still owns preferences and asynchronous edits/saves; the app theme wrapper owns ThemeData selection and its existing bounded cache identity. Glass widgets/controllers retain their listeners/render-resource disposal and performance behavior. Renames do not add services, threads, network calls, data writes to media, or a second settings store. No Dart/Kotlin/Rust channel or serialization contract changes are planned; native notification action identifiers remain intact. If implementation discovers a necessary native contract change, update the plan/assurance before touching it.

The separate offline-library plan001 remains untouched. Execute one approved change at a time; if either is implemented first, refresh the other's map/context/naming inventory before starting its tasks. Do not merge or execute that plan as part of this one.

## Decisions

- PD-1: Promote the actual current Mornye theme to AppTheme and preserve visuals; default Material builder is retired, not renamed as the app's lasting design.
- PD-2: Keep compatibility storage/wire IDs and product branding; neutral code names do not justify user-data or package-ID migration.
- PD-3: Temporary LegacyMaterialTheme exists only to keep the rename task compilable, then is deleted; a monolithic unsafe search/replace and indefinite dual-theme compatibility were rejected.
- PD-4: Dependency removal follows retained-consumer evidence, not name matching. Flutter Material infrastructure remains wherever needed.
- PD-5: Planning only. No execution, push or APK now; the standing owner no-APK instruction also overrides the generic future APK-task template.

## Constitution check

- [x] I. One retained design, no unrelated feature changes, plan-only scope.
- [x] II. Baseline and final checks distinguished from device evidence.
- [x] III. Reuse current components and resolve actual collisions; no redesign.
- [x] IV. Characterization/persistence/import/interaction regression tests precede replacement.
- [x] V. Existing failure behavior retained; no new untyped domain result.
- [x] VI. Same preference/render owners; native contracts unchanged.
- [x] VII. Saved keys, actions, media/library/backup IDs preserved.
- [x] VIII. Independent design reviews and future per-task/final reviews required.
- [x] IX. No general replacement framework or speculative abstraction.
- [x] X. One planning commit; later one reviewed commit per task, no push/APK.

## Complexity tracking

| Deviation | Reason | Simpler alternative rejected |
|---|---|---|
| Temporary legacy builder in rename task | AppTheme name is already occupied; intermediate commits must compile | Blind overwrite breaks the still-connected Material call sites before branch retirement |
| No generic [APK] task | Owner explicitly prohibited APK builds | Template cannot override scope; native/unit checks remain available |

## Verification plan

T001 later records baseline and pins retained light/dark, accent/font/glass levels, representative geometry/semantics and actions with existing tests plus meaningful gaps. Use current test/design_system_test.dart, mornye_theme_identity_test.dart, theme_provider_persistence_test.dart, appearance_settings_test.dart, mornye_* widget suites, player/lyrics, navigation and notification assertions; inspect exact test ownership at task start.

During implementation, task start refreshes map/context; targeted checks run while editing, then task check enforces existing automatic analyzer/Flutter/domain checks, independent review(max3), and one commit before the next task. Before final acceptance: complete feasible flutter analyze/test, scoped identifier/import/dependency/asset checks, Android unit/native compile (no APK), old preference/JSON startup, headless notification tests, shader resolution and reduced-motion/RTL/TV behavior. Record pre-existing failures separately.

No runtime tests are needed to claim this document is only a plan. Planning checks are workflow lint and two consecutive clean fresh-context design rounds. Actual hardware glass/shader/notification acceptance is pending until executed; no screenshot/device success is inferred from source or host tests.

## Open choices and execution gate

No unresolved product-scope questions. Show the completed plan to the owner; no implementation task starts without a later execution instruction. The unapproved offline-library plan is unrelated scope.
