# Bundled Arabic font (historical)

**Superseded by the owner on 2026-11-02:** the bundled Inter/Noto files and font preferences have been removed. Arabic and Latin now use system fonts and platform fallback. See [Fixed Appearance defaults](APPEARANCE_DEFAULTS.md). The remainder records the earlier implementation and its verification, not current behavior.

Requested 2026-11-02: use Noto Sans Arabic for Arabic while retaining Inter for
Latin text in the default Sistrum theme.

## Implementation

`assets/fonts/NotoSansArabicVariable.ttf` is bundled in `pubspec.yaml` under the
family **Noto Sans Arabic**. The body and display styles in
`lib/core/theme/app_theme.dart` explicitly list that family as a fallback; the
base ThemeData also supplies it to inherited control styles. Existing light/dark
roles, sizes, weights, tracking, line heights and text scaling are retained.
Under the default Inter setting, Latin glyphs remain Inter and missing Arabic
glyphs resolve to the bundled Noto font. No per-string language detection or
text-span rewriting is needed. This covers mixed Latin/Arabic labels through
normal Flutter shaping and bidi handling.

Existing system/custom-font preferences retain their precedence: a chosen primary
font that already contains Arabic can render those glyphs itself. The bundled
family handles missing glyphs rather than overriding a user's imported font.
Scripts not covered by either family can continue through platform fallbacks.
There is no runtime font download or new package dependency.

## Provenance and licensing

Downloaded from the Google Fonts repository, pinned to the most recent commit
for `ofl/notosansarabic` at the time of this change:
`8b0a1d0f5983c89bc2b93f1b5fb55f9e252744b5`.
Original file: `ofl/notosansarabic/NotoSansArabic[wdth,wght].ttf`.
The bundled font is unmodified.

Font SHA-256:
`63111b5b2e074dd48cc67692e0a2726d86ee94c1c37fe8598257b7b4e87e869e`.

Copyright 2022 The Noto Project Authors; SIL Open Font License 1.1.
The complete license is bundled as `assets/fonts/NotoSansArabic-LICENSE.txt`
and registered with Flutter's existing LicenseRegistry in `lib/main.dart`.

## Verification

FontTools inspection verifies Arabic letter coverage, GSUB/GPOS shaping tables,
and variable axes: weight 100–900, width 62.5–100. A Pillow/Raqm specimen at weights
400/600/700 was generated and visually inspected; it is a font specimen, not an
Android/Flutter screenshot or device acceptance result. Source checkpoint: `32c2e26d`. `flutter analyze`: **No issues found**; full
Flutter suite: **2,419 passed / 3 skipped / zero failures** (5m44s). Graph
`e83ce260`: **29,054 unique nodes / 55,506 links / zero dangling endpoints**,
built from `32c2e26d`; existing extraction limitations remain.

No APK, push or physical-device run is part of this change.
