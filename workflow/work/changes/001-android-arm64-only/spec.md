# Spec 001-android-arm64-only: Android arm64 only

Status: Clarified (v3: owner decisions on first install, Discord and finishing in one change; requirements
rewritten to match v3 after design review round 2)
Created: 2026-11-09
Input: The owner works only on the Android arm64 APK. Remove everything else from the source: desktop, iOS, and
32-bit ARM (armeabi-v7a). Keep only arm64 in the source. (The first request kept Discord for a later change;
Clarifications v3 removes it in this change.)
Binding decisions: none

## Clarifications v3 (owner, later in the same session)

- Discord is removed completely in this change, with everything related to it. This supersedes the earlier
  decision to keep Discord (FR-007, Out of scope, PD-3). Android-related files that mention Discord are edited so
  they stay Android-only.
- The app is treated as a first install: nobody has installed it, so no database migration and no migration test
  are needed. This supersedes FR-011 and FR-012 and the drop-tables step in T004 and T034. Link sync tables are not
  created, and no existing user data is carried over.
- Desktop, iOS and armeabi-v7a are removed from the source; only arm64 remains.
- Run the work to the end in this change; the change is not split further. This supersedes the earlier answer to
  split it in three.
- Remove every other remnant that is not Android, including Windows path identity (FR-013), and remove the dead
  code the removal leaves behind (FR-014).
- The owner asked to rewrite the branch history into a few commits and force-push it. This supersedes the earlier
  answer about adding commits without force push.

## User scenarios

### Story 1: Release APK is arm64 only (Priority: P1)

The owner runs the release build and gets exactly one Android APK that contains arm64-v8a native libraries only,
with no 32-bit library and no universal APK.

Why this priority: this is the only product the owner builds now.
Independent test: run the release APK build; inspect the produced APK and build output.

Acceptance:
1. Given the source tree after this change, When the release APK build runs, Then exactly one APK is produced, it
   contains arm64-v8a libraries only, and no armeabi-v7a library or universal APK is produced.
2. Given the Rust backend build, When it runs for Android, Then it builds only aarch64-linux-android.

### Story 2: The source contains only Android code (Priority: P1)

A developer reading the repository finds no iOS, macOS, Windows, Linux or desktop project, build script, CI job
or Dart branch that the Android app cannot reach.

Why this priority: removing dead platform code is the point of the change.
Independent test: list the tree and search for the removed platform names.

Acceptance:
1. Given the repository after this change, When the owner lists platform folders, Then only android/ remains
   among the native platform projects.
2. Given the Dart code, When it is searched for iOS, macOS, Windows, Linux and desktop platform branches, Then
   none remain.

### Story 3: Everything the Android app keeps behaves as before (Priority: P2)

Every Android feature that stays keeps its behaviour. The intended changes are: Discord and Mornye Link are removed
from the Android app, Windows path identity is removed, and the update check offers only arm64 APKs.

Why this priority: the removal must not break the product that remains.
Independent test: the Android test suite runs for every kept feature; removed tests are listed with a reason.

Acceptance:
1. Given the change, When the Android test suite runs, Then every test for a kept feature passes or is skipped with
   a reason listed in the plan's Complexity tracking, no test of a kept feature is weakened, and only tests of
   removed features are deleted.
2. Given a first install after the change, When the app creates its databases, Then no Link sync table is created
   (no migration: the app is treated as a first install).

## Edge cases

- Shared Dart code that branched on Platform for both Android and another platform: keep the Android branch and
  remove the other.
- Plugins whose only platform support is removed: remove their non-Android registration, not their Android code.
- Rust crates used by both mobile and desktop (core, network, providers, extensions): keep them when the mobile
  backend needs them; remove only the desktop-only crate and its build paths.
- Discord: removed with everything related to it, including its Android integration and its Lite switch (v3).
- Generated files (CMake, Xcode project, pod lock) for removed platforms: removed with their platform folder.

## Requirements

- FR-001: The release build MUST produce one arm64-v8a APK and MUST NOT produce an armeabi-v7a or universal APK.
- FR-002: The Rust Android build MUST target only aarch64-linux-android and MUST NOT build armv7-linux-androideabi.
- FR-003: The repository MUST NOT contain the ios/, macos/, windows/ or linux/ Flutter platform folders.
- FR-004: The repository MUST NOT contain the desktop Rust crate, desktop build or packaging scripts, or iOS, macOS
  and Windows build scripts.
- FR-005: Dart code MUST NOT contain branches for iOS, macOS, Windows, Linux or desktop platforms.
- FR-006: CI workflows MUST NOT build iOS, desktop or armeabi-v7a targets.
- FR-007: The Discord integration MUST be removed completely: its SDK, Android integration, settings, strings and
  tests (v3).
- FR-008: The Android app behaviour MUST remain unchanged for every kept feature, except as set out in FR-007,
  FR-009, FR-010 and FR-013.
- FR-009: The update check MUST offer only the release's arm64 APK. The app runs only on arm64, so it does not
  read the device ABI. A newer release without an arm64 APK is a typed no-match (`noCompatibleApk`) and the update
  dialog says so. Tests for arm32 and universal matching are removed.
- FR-010: Mornye Link MUST be removed from the Android app: its client, sync, transfer, playback, UI, settings and
  strings and tests. No migration is needed (FR-011).
- FR-011: There is no database migration: the app is treated as a first install, and the Link sync tables are
  never created (v3).
- FR-012: Stored preference keys and backup fields of removed features are removed; nothing stored needs to
  survive (v3).
- FR-013: Windows path identity MUST be removed from Dart, Rust and the shared path-key contract, with every other
  remnant that is not Android. Items kept for a reason are listed in the plan (PD-9).
- FR-014: Dead code left by the removal MUST be removed after a reference search for each item.

## Success criteria

- SC-001: The release build produces exactly one APK file that contains arm64-v8a libraries only, verified by
  `scripts/check_backend_apk.py`.
- SC-002: The search in the plan's Verification plan for removed platform, Discord, Link and Windows path names
  returns no match outside the change records, the CHANGELOG and the exceptions the plan lists in PD-9.
- SC-003: Static analysis passes. Every test of a kept feature passes or is skipped with a reason recorded in the
  plan's Complexity tracking; no test of a kept feature is loosened; tests are removed only with their removed
  feature.
- SC-004: The Rust workspace builds with `--locked` and passes its tests with the desktop and link crates removed.

## Out of scope

- Any new iOS, macOS, Windows, Linux or desktop support.
- Device testing on real hardware (listed as pending until the owner runs it).

## Assumptions

- The owner accepts a full removal of the desktop Rust crate and its dependencies, not only its build scripts.
- Signing and release configuration for Android stay unchanged.

## Clarifications

Session 2026-11-09
- Q: Remove the Dart branches for other platforms in shared code? → A: Yes, remove them (applied to FR-005 and Edge cases).
- Q: Remove the Discord SDK now? → A: No, later as a separate change. Superseded by Clarifications v3: removed now.
- Q: How should the commits be made? → A: On mornye-reboot3 as new commits, pushed without force push. Superseded by
  Clarifications v3: the owner asked to rewrite the history and force-push.
- Q: Start after the spec? → A: Yes, proceed with plan and build (applied to Status).
- Q: Update check on devices without arm64 (arm32 or universal APK)? → A: arm64 only, remove the branches (FR-009).
- Q: Mornye Link on Android? → A: Remove Link too (FR-010).
- Q: Link sync tables and existing user data? → A: Drop the tables with a migration. Superseded by Clarifications v3:
  first install, no migration (FR-011, FR-012).
- Q: Split the change? → A: Split in three: (a) build, CI, Rust crates, platform folders, pubspec, third_party and docs for arm64 only; (b) Dart desktop and iOS removal, update check arm64-only, FFI backend removal; (c) Link removal with the database migration. Each part has its own change record and checks. Superseded by Clarifications v3: one change.
- Q: Translation keys for Link (lib/l10n/arb/*.arb)? → A: Remove the keys from every ARB file and regenerate the localizations (applied to FR-010; part (c)).

