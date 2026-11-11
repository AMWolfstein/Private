# Single app design with neutral theme names

Status: Clarified
Input: Remove the alternative Material visual theme throughout the app, make the current Mornye design the only design, and use generic app-theme/component names rather than mornye_ names. The owner requests WORKFLOW PLANNING ONLY; no app changes or task execution now.
Binding decisions: preserve current Mornye appearance/behavior and light/dark/system mode, accents, fonts and glass preferences. Flutter Material infrastructure may remain. No APK or push is authorized. Existing offline-library plan001 is a separate draft, neither a prerequisite nor implementation authority for this change.

## User scenarios

### Story1: One consistent design (P1)
Acceptance:
1. Given a fresh install or previously selected Material/Mornye style, when the app starts, then only the existing Mornye visual system appears, without a Material first frame or theme selector.
2. Given an existing Mornye setup, when opening library/detail/settings/player surfaces or using notifications, then colors, typography, layout, gestures, animations and actions match its current behavior.
3. Given light/dark/system mode, custom/system fonts, accent and glass preferences, when changing them or restarting, then retained options work without switching designs.

### Story2: Neutral names and safe compatibility (P1)
Acceptance:
1. Given a developer uses the app design system, then theme-specific files/types/helpers use app_/App names with one canonical implementation, not two conflicting classes or retained Material fallbacks.
2. Given old saved preferences or supported settings JSON containing material/mornye style values, when read, then the sole design loads and existing supported preferences retain their current compatibility semantics.
3. Given product branding, package/channel IDs, notification action IDs and persisted keys, then internal theme renaming does not break those identities.

## Requirements

- FR-001: The app MUST have one visual design, derived from the current Mornye implementation; remove Material-style selection, defaults and rendering branches throughout the app.
- FR-002: The app MUST use neutral app theme/component identifiers and paths, merging name collisions rather than duplicating implementations or applying a blind text replacement.
- FR-003: The app MUST preserve current Mornye appearance, artwork-derived surfaces, typography, reduced-motion behavior, accessibility, RTL, tablet/TV layout and low-end glass rendering choices.
- FR-004: The app MUST retain light/dark/system mode, accent, fonts, glass settings and lyrics presentation preferences, with safe loading of old stored values and existing asynchronous persistence behavior.
- FR-005: The app MUST remove Material-only controls, settings, helpers, dependencies/assets and tests only when no retained behavior uses them; retain Flutter framework infrastructure and shared algorithms still required.
- FR-006: The app MUST preserve app identity, native/channel/persistent IDs and media/notification actions; this task changes presentation, not playback, library, networking or backup formats.
- FR-007: The app MUST retain tests for shared/retained behavior, update import/asset/part references atomically with renames, and prove the removed design cannot be restored via old settings.

## Edge cases

Cold start while preferences/fonts load; edits during async load/save; missing/invalid old style; legacy accent migration marker; nested theme/overlay contexts; light/dark changes; custom fonts; reduced motion; flat/frosted/liquid glass; RTL; tablet/TV; shader loading/fallback; background playback before Activity; old settings input.

## Success criteria

- SC-001: App shell and representative screen/player/widget tests always render the sole design for material/mornye/missing/invalid legacy style inputs; no style picker or dynamic-wallpaper startup request remains.
- SC-002: Characterization fixtures and interaction tests preserve retained geometry, text/icons, colors, motion/contrast, navigation and local player/notification actions.
- SC-003: A scoped symbol/import/asset inventory finds no theme-specific Mornye identifiers/paths, style selector or Material-style renderer; explicit brand/wire/storage exemptions remain documented.
- SC-004: Analyzer, complete feasible Flutter tests and Android unit/native compilation pass relative to recorded baseline; device-only shader/notification observations remain distinct from host verification.

## Out of scope

Removing Flutter MaterialApp/ThemeData/ColorScheme/Scaffold/framework widgets by name; renaming product/package/channel IDs, media IDs or user storage keys; changing playback/library/network behavior; implementing offline-library plan001; redesigning Mornye; publishing or APK builds.

## Assumptions and authorization

The request authorizes only a complete plan and its independent review, recorded in one planning-document commit. Implementation requires a later instruction. Generic model/constant names may change while their persisted string keys remain unchanged for compatibility. Product branding stays Mornye.
