# Spec 001-android-arm64-only: Android arm64 only

Status: Clarified (v2: owner decisions on update check, Link and database)
Created: 2026-11-09
Input: The owner works only on the Android arm64 APK. Remove everything else from the source: desktop, iOS, and
32-bit ARM (armeabi-v7a). Keep only arm64 in the source. Discord SDK removal comes later, in a separate change.
Binding decisions: none

## User scenarios

### Story 1: Release APK is arm64 only (Priority: P1)

The owner runs the release build and gets exactly one Android APK that runs on arm64 devices, with no 32-bit
library and no universal APK.

Why this priority: this is the only product the owner builds now.
Independent test: run the release APK build; inspect the produced APK and build output.

Acceptance:
1. Given the source tree after this change, When the release APK build runs, Then exactly one arm64-v8a APK is
   produced and no armeabi-v7a library or universal APK is produced.
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

Every Android feature that stays keeps its behaviour. The two intended changes are: Mornye Link is removed from the
Android app, and the update check picks only arm64 APKs.

Why this priority: the removal must not break the product that remains.
Independent test: the Android test suite runs for every kept feature; removed tests are listed with a reason.

Acceptance:
1. Given the change, When the Android test suite runs, Then every test for a kept feature passes, and no test is
   skipped, weakened or deleted except those listed in the test inventory with a reason.
2. Given the database after the change, When an existing user's database is opened, Then the Link sync tables are
   dropped by a migration and the rest of the data is unchanged.

## Edge cases

- Shared Dart code that branched on Platform for both Android and another platform: keep the Android branch and
  remove the other.
- Plugins whose only platform support is removed: remove their non-Android registration, not their Android code.
- Rust crates used by both mobile and desktop (core, network, providers, extensions): keep them when the mobile
  backend needs them; remove only the desktop-only crate and its build paths.
- Discord SDK: stays as it is in this change, including its Android integration and its Lite switch.
- Generated files (CMake, Xcode project, pod lock) for removed platforms: removed with their platform folder.

## Requirements

- FR-001: The release build MUST produce one arm64-v8a APK and MUST NOT produce an armeabi-v7a or universal APK.
- FR-002: The Rust Android build MUST target only aarch64-linux-android and MUST NOT build armv7-linux-androideabi.
- FR-003: The repository MUST NOT contain the ios/, macos/, windows/ or linux/ Flutter platform folders.
- FR-004: The repository MUST NOT contain the desktop Rust crate, desktop build or packaging scripts, or iOS, macOS
  and Windows build scripts.
- FR-005: Dart code MUST NOT contain branches for iOS, macOS, Windows, Linux or desktop platforms.
- FR-006: CI workflows MUST NOT build iOS, desktop or armeabi-v7a targets.
- FR-007: The Discord SDK integration MUST remain unchanged in this change.
- FR-008: The Android app behaviour MUST remain unchanged for every kept feature, except as set out in FR-009 to FR-011.
- FR-009: The update check MUST select only arm64-v8a APKs. Devices without arm64 get no update match and the app
  says so. Tests for arm32 and universal matching are removed with a stated reason.
- FR-010: Mornye Link MUST be removed from the Android app: its client, sync, transfer, playback, UI, settings and
  tests. Its database tables are dropped (FR-011).
- FR-011: A database migration MUST drop the Link sync tables on existing installs, bump the schema version, keep
  every other table and row, and be covered by a migration test on a database created by the previous version.
- FR-012: Persisted preference keys and backup JSON fields that Android still reads MUST be kept unchanged. Keys that
  only desktop or Link read MAY be left as stored data with a shortcut comment.

## Success criteria

- SC-001: The release build produces exactly one APK file, named for arm64-v8a, verified by the APK audit script.
- SC-002: Searching the repository for iOS, macOS, Windows, Linux and desktop platform references returns no
  matches outside the change records and documentation of this change.
- SC-003: The Android test suite and static analysis pass after the change, with no test skipped, removed or
  loosened.
- SC-004: The Rust workspace builds and passes its tests with the desktop crate removed.

## Out of scope

- Removing the Discord SDK (the owner will do this later as a separate change).
- Any new iOS, macOS, Windows, Linux or desktop support.
- Rewriting git history or force-pushing (commits are added on top of the current branch).
- Device testing on real hardware (listed as pending until the owner runs it).

## Assumptions

- The owner accepts a full removal of the desktop Rust crate and its dependencies, not only its build scripts.
- Lite (MORNYE_DISCORD_SDK=0) remains the build path used for verification, as in CI today.
- Signing and release configuration for Android stay unchanged.

## Clarifications

Session 2026-11-09
- Q: Remove the Dart branches for other platforms in shared code? → A: Yes, remove them (applied to FR-005 and Edge cases).
- Q: Remove the Discord SDK now? → A: No, later as a separate change (applied to Out of scope and FR-007).
- Q: How should the commits be made? → A: On mornye-reboot3 as new commits, pushed without force push (applied to Out of scope).
- Q: Start after the spec? → A: Yes, proceed with plan and build (applied to Status).
- Q: Update check on devices without arm64 (arm32 or universal APK)? → A: arm64 only, remove the branches (FR-009).
- Q: Mornye Link on Android? → A: Remove Link too (FR-010).
- Q: Link sync tables and existing user data? → A: Drop the tables with a migration; the schema version is bumped and a migration test is required (FR-011, FR-012).
