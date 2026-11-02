# Fixed Appearance defaults

Owner-approved simplification, 2026-11-02.

## Behavior

- The global accent is fixed in `AppTheme`: light `#CC2E33`, dark `#FF453A`, the previous red choice. The color picker, accent enum, mutators and search entry are removed. Artwork-derived palettes remain independent.
- All app typography follows the former system-font path. Flutter's platform typography and system glyph fallback render Latin, Arabic and mixed text. No bundled Inter/Noto font, font download, imported-font loader or custom-font picker remains. System monospace is retained for diagnostic text; icon fonts remain icon fonts. Existing text metrics, accessibility text scaling and light/dark roles are preserved.
- Hero controllers are always attached to the root and tab navigators. The mini player always supplies current geometry for the player's surface/artwork morph. The alternate preference-controlled slide is removed. Direct entries without geometry render in place; interactive dragging still follows the finger. Existing orientation/lifecycle guards remain, and reduced motion bypasses the morph.
- Appearance retains glass controls, light/dark/system mode, language, animated artwork, lyrics position and player view. Removed controls and their translations/search targets are deleted.

## Persistence and cleanup

Theme JSON and bootstrap preferences ignore retired accent/font fields. The notifier removes the four retired preference keys; app-owned imported font files under the application-support `custom_fonts` directory are deleted best-effort when the legacy ID key is present. Cleanup failure is logged and cannot reactivate a font or block settings migration. The cleanup never deletes music/library data or follows a link in place of the cache directory.

`AppSettings` and its generated serializer no longer model `heroAnimationsEnabled`. Older settings/backup payloads ignore it, and subsequent serialization omits it. New upstream ReplayGain fields are preserved.

## Verification

Source: `3f1b470b`. `flutter analyze --no-pub`: **No issues found**. Full `flutter test`: **2,448 passed / 3 skipped / zero failures** (6m04s). Focused settings/theme/search/migration coverage: **81 passed**; final Hero/route/controller coverage: **12 passed**.

Tests cover fixed colors in both modes and across reopening, system typography and absent controls/search entries, legacy settings serialization, early edits/disposal while preferences load, idempotent font-cache cleanup and failure handling, real tab Hero flights/controller disposal, player opening/dismissal with reduced motion, stale bounds on rotation and drag settling. Existing custom-font-only tests were removed; the retained menu integration scenario now uses system typography. An initial test assertion accidentally included transitions belonging to the underlying route; it was scoped to the player and the final focused/full runs passed.

Graph `6d6b67c2`, built from `3f1b470b`: **29,375 unique nodes / 56,011 links / zero dangling endpoints**. Deleted feature files own no graph nodes. Existing extractor limitations remain (vendored native syntax and sources without modeled symbols).

No APK build or physical-device/instrumentation run. Device-specific system font appearance is not visually verified here. The previous pending Library/artist commits and remote ReplayGain changes were merged and pushed first at `a43fb4fe`; this Appearance batch is committed locally.
