# Plan 001-android-arm64-only: Android arm64 only (v3)

v3 applies the owner's later decisions (spec, Clarifications v3): Discord is removed completely, the app is treated
as a first install with no data migration, and the work finishes in one change. It also records the scope the owner
added during the work: removing Windows path identity and every remaining non-Android remnant, and removing dead
code found by an audit. The per-file list of the original scope is in `inventory.md`.

## Summary

Keep the Android app and its arm64-v8a Rust backend. Remove the Flutter iOS, macOS, Windows and Linux projects, the
desktop and Link Rust crates, the armeabi-v7a target, the universal APK, the desktop/iOS/macOS/Windows build, packaging
and CI definitions, the desktop-only Dart code, Discord with everything related to it, Mornye Link on Android, Windows
path identity, and the plugins only those platforms use. Then remove the dead code the removal left behind.

## Current system (at the base commit)

- Backend selection: `lib/services/backend/backend_channel.dart:46` chooses `RustFfiBackend.shared` on desktop and
  `MethodChannelBackend.shared` otherwise. Android always uses the MethodChannel path. The FFI path is desktop only.
- Update check: `lib/services/update_checker.dart:14` (`_ApkVariant` arm64, arm32, universal), variant mapping
  around :634-638 and fallbacks around :668-688. Tests: `test/update_checker_test.dart`.
- Android build: `android/app/build.gradle.kts:37` (default ABI list arm64-v8a,armeabi-v7a), :40, :167
  (`isUniversalApk = true`), `scripts/build_rust_backend.sh` (Android branch with the armeabi case),
  `scripts/build_android.sh` (ABI check, APK loop with a universal target), `scripts/check_backend_apk.py`,
  `scripts/check_android_statx.sh:9-10`.
- CI and release: `.github/workflows/desktop.yml` (desktop only), `ci.yml:363-366` and `release.yml:179, 228`
  (armeabi and iOS/desktop steps).
- Rust: `rust_backend/Cargo.toml` members include `crates/desktop` and `crates/link`. `crates/mobile` does not depend
  on either (verified by the design review). `crates/link` is used only by `crates/desktop`.
- Link on Android: `lib/services/link/**` (client, sync, transfers, playback, features), `lib/widgets/link/**`,
  `lib/screens/settings/link_*.dart`, plus about 100 importers across lib, test and integration_test. The database
  uses Link's sync schema: `lib/services/library_collections_database.dart:12` and
  `lib/services/listening_statistics.dart:5` (`link_collection_sync_schema.dart`, `link_history_sync_schema.dart`).
- Persisted settings: `lib/models/settings.dart:116-120` (exclusive output, desktop-only), link keys in
  `link_desktop_host.dart:43, :46` and `desktop_commands.dart:270`.
- Platform checks: about 147 Dart files (inventory rows `edit`).
- Discord: `lib/services/discord_presence_service.dart` contains a desktop branch (~124) and an iOS check (~128),
  and `third_party/mornye_discord/ios` is Discord iOS code. Both are exceptions (FR-007).
- Third party: `third_party/audioplayers_darwin` (whole plugin, pubspec override), `third_party/media_kit_libs_windows_audio`,
  and the non-Android subfolders of `third_party/ffmpeg_kit_flutter_new_audio` and `third_party/audio_service`.
- Docs: `README.md:34, :68, :96`, `rust_backend/README.md:93-96, :144`; launcher icon config in `pubspec.yaml`
  (ios, macos, windows, around :169-190).

## Design

- Ownership and dependency direction: unchanged for kept code. Dart calls the backend only through
  `MethodChannelBackend`. Kotlin and the Android Rust library keep their owners.
- Contracts across Dart, Kotlin and Rust (methods, fields, units, errors): unchanged for kept features. Removed
  features take their channel methods with them on both sides; the shared native library path-key contract loses
  its Windows `windows-file:` keys on the Dart and Rust sides together.
- State, threads, lifecycle and cancellation: unchanged on Android for kept features. Link's and Discord's
  lifecycles go with them.
- Failure: unchanged for kept features. The update check returns a typed no-match (`noCompatibleApk`) for a
  device without arm64 instead of an arm32 or universal asset (FR-009).
- Data compatibility: the app is treated as a first install (spec v3). There is no database migration, Link sync
  tables are never created, and settings fields of removed features are removed. Song IDs and the backup archive
  format are unchanged for kept features.
- Removal: every row of `inventory.md` is an action; the later scope (Discord, Windows path identity, dead code) is
  proven by searches and an audit. The proof is the SC-002 search and `flutter analyze` with no unresolved import.
- Build: release produces one `app-release.apk` that contains arm64-v8a only. Gradle keeps no ABI split because
  AGP 9.5 rejects the split together with the NDK ABI filter, and it keeps `scripts/flutter_git_commit.sh`, which it
  calls for the build revision.

## Characterization before edit

Superseded by spec v3: with no migration and no preserved settings (FR-011, FR-012 superseded) the database and
settings characterization tests (T001, T002, T004) are not needed. The update check is pinned by the restored
`test/update_checker_test.dart` (T003, T031).

## Decisions

- PD-1: Remove `crates/desktop` and `crates/link` from the workspace and delete them. Alternatives considered: excluding them
  from the build (rejected: dead code kept in the source).
- PD-2: Build the Android Rust library for `aarch64-linux-android` only. Alternatives: keep armeabi-v7a behind a flag
  (rejected: owner asked for arm64 only).
- PD-3 (v3, supersedes v2): Remove Discord completely, including its desktop branch, iOS check, SDK and
  `lib/utils/desktop_platform.dart` (owner decision).
- PD-4: Remove `RustFfiBackend` and `FfiBackendTransport`. Keep only `MethodChannelBackend`.
- PD-5: Update check: arm64 only (owner decision).
- PD-6 (v3, supersedes v2): Remove Mornye Link from Android without a migration; the app is a first install
  (owner decision).
- PD-7 (v3, supersedes v2): Settings fields and keys of removed features are removed; nothing stored needs to
  survive (owner decision).
- PD-8: One non-split release APK containing arm64-v8a only. Alternatives: an ABI split with one arm64 output
  (rejected: AGP 9.5 rejects it together with the NDK ABI filter).
- PD-9: Remove Windows path identity from Dart, Rust and the shared path-key contract, and every other remnant
  that is not Android (owner decision). Kept: Linux as the build host in scripts, `cap-primitives` (used by the
  Android file code), `*_desktop.frag` asset names inside `liquid_glass_easy`, and the Windows/Linux/Darwin
  options of the `file_picker` platform interface that the test fake must override.
- PD-10: Remove dead code after an audit, each removal checked by reference search and `flutter analyze`
  (owner request).

## Constitution check

- [x] I. Owner decisions respected: arm64 only, update check, Discord and Link removed, first install
- [x] II. Every step has a check; device-only behaviour listed as pending; BLOCKED checks not counted as passed
- [x] III. Root cause: removal, not a bug. Smallest complete change; the deviations are recorded below
- [x] IV. No test weakened to pass: tests of removed features are deleted, kept behaviour keeps its tests, skips
  carry a reason
- [x] V. Failures typed: the update check's no-match is `noCompatibleApk`, tested in `test/update_checker_test.dart`
- [x] VI. Boundary: kept MethodChannel methods unchanged; the Kotlin side runs in the android-unit check
- [x] VII. Data: no migration needed (first install, spec v3)
- [x] VIII. Independent review: two clean design rounds and two clean code rounds
- [x] IX. No speculative layers; deviations recorded below
- [x] X. Commits: records and code separate; push and APK only when the owner asks

## Complexity tracking

| Deviation | Why needed | Simpler option rejected because |
|---|---|---|
| `test/semantics_geometry_regression_test.dart` skipped | It fails inside the pinned Flutter SDK (`rendering/object.dart`) and uses no project code | Changing the pinned SDK is outside this change |
| Blur and pixel tests in `album_detail_header`, `listening_rewind_backdrop`, `material_player_backdrop` skipped | They failed before this change; the header blur stays live while music plays and needs its own fix | Fixing `SettledBlur` changes rendering behaviour outside this change |
| One permission test in `cover_cache_info_repository_test.dart` skipped as root | Root bypasses permission bits in the sandbox; it runs for non-root users | No unreadable-but-existing file can be made as root |

## Verification plan

- Host checks (`work.py check auto`): `analyze`, `dart-tests`, `android-unit`, `rust` (cargo workspace test with
  `--locked`), `workflow`. `android/gradlew` is generated by Flutter during a build and is git-ignored.
- Searches (SC-002): the removed platform, Discord and Link names have no match except the kept items in PD-9 and
  the change records.
- Update check: `test/update_checker_test.dart` (arm64 APK, armeabi-v7a typed no-match, release page fallback).
- Release APK built with `scripts/build_android.sh` and audited by `scripts/check_backend_apk.py`: arm64-v8a only.
- Owner-run check (pending): install the APK on an arm64 device and open library, playback and settings.

## Open choices for the owner

- none
