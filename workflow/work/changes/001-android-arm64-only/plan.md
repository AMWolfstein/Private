# Plan 001-android-arm64-only: Android arm64 only (v2)

v2 answers the design review (13 findings) and applies the owner's decisions: update check arm64-only, Link removed
from Android with a migration that drops its tables, Discord untouched. The per-file list is in `inventory.md`.

## Summary

Keep the Android app and its arm64-v8a Rust backend. Remove the Flutter iOS, macOS, Windows and Linux projects, the
desktop and Link Rust crates, the armeabi-v7a target, the universal APK, the desktop/iOS/macOS/Windows build, packaging
and CI definitions, the desktop-only Dart code, Link on Android (with a migration that drops its tables), and the
plugins only those platforms use. The Discord code is not changed.

## Current system

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
- Contracts across Dart, Kotlin and Rust (methods, fields, units, errors): unchanged. The MethodChannel contract keeps its
  tests on the Dart side. Its Kotlin side is run by the Android unit check, which is BLOCKED (see Verification).
- State, threads, lifecycle and cancellation: unchanged on Android for kept features. Link's lifecycle goes with Link.
- Failure: unchanged for kept features. The update check returns "no match" for non-arm64 devices instead of an arm32
  or universal asset (FR-009).
- Data compatibility:
  - Database: a migration drops the Link sync tables and bumps the schema version. All other tables and rows are kept
    (FR-011). A migration test runs on a database created by the previous version.
  - Preference keys and backup fields that Android still reads are kept (FR-012). Keys read only by desktop or Link
    stay as stored data with a `shortcut:` comment.
  - Song IDs and backup archive format: unchanged for kept features.
- Removal: every row of `inventory.md` is an action. The proof is the SC-002 search with the exception list, and
  `flutter analyze` with no unresolved import.
- Build: release produces one `app-arm64-v8a-release.apk`. Gradle has no universal APK and no armeabi target.

## Characterization before edit (R8, R9)

- `sqlite_helpers.dart`: a test with `debugDesktopPlatformOverride = false` asserts the documents directory on Android and
  that the sqflite factory is unchanged. It runs before the edit and must pass after it.
- Settings JSON: a round-trip test over the current settings and backup fields runs before the edit and must pass after it.

## Decisions

- PD-1: Remove `crates/desktop` and `crates/link` from the workspace and delete them. Alternatives considered: excluding them
  from the build (rejected: dead code kept in the source).
- PD-2: Build the Android Rust library for `aarch64-linux-android` only. Alternatives: keep armeabi-v7a behind a flag
  (rejected: owner asked for arm64 only).
- PD-3: Keep the Discord code unchanged, including its desktop branch and iOS check, and keep `lib/utils/desktop_platform.dart`
  (its `isDesktopPlatform` helper) only because Discord imports it. Marked `shortcut:` and removed with the Discord change.
- PD-4: Remove `RustFfiBackend` and `FfiBackendTransport`. Keep only `MethodChannelBackend`.
- PD-5: Update check: arm64 only (owner decision).
- PD-6: Link: remove Android Link and drop its tables with a migration (owner decision).
- PD-7: Keep stored settings fields and keys that Android reads (FR-012). Alternatives: remove them (rejected: changes the
  backup format, constitution VII).

## Constitution check

- [x] I. Owner decisions respected: update check, Link, database, Discord untouched
- [x] II. Every step has a check; device-only behaviour listed as pending; BLOCKED checks not counted as passed
- [x] III. Root cause: removal, not a bug. Smallest complete change; the shortcuts are recorded above
- [x] IV. Characterization before edit for database and settings; migration test; no test weakened
- [ ] V. Failures typed: not yet verified for the update check (test in T021 must show a typed no-match result)
- [x] VI. Boundary: MethodChannel contract unchanged; its Kotlin side is BLOCKED until android/gradlew exists
- [x] VII. Database migration and backup fields handled as FR-011 and FR-012
- [x] VIII. Independent review: two clean design rounds required before build; code review before ship
- [x] IX. No speculative layers; deviations recorded below
- [x] X. Commits: records and code separate; no push or APK without the owner

## Complexity tracking

| Deviation | Why needed | Simpler option rejected because |
|---|---|---|
| Discord desktop branch and `lib/utils/desktop_platform.dart` helper kept | FR-007: owner said Discord is removed later | Editing Discord code would break the owner's decision |
| Stored settings fields and keys kept | Backup format and user settings must survive (VII) | Removing them would change the backup format |

## Verification plan

- Host checks (work.py check): `analyze`, `dart-tests`, `rust` (cargo workspace test with `--locked`), `workflow`.
  - `android-unit` requires `android/gradlew`, which the repository does not contain. It is BLOCKED until the owner adds the
    wrapper or the check is changed. The Kotlin side of the MethodChannel contract is therefore not verified.
- Searches (SC-002): the removed platform and Link names have no match except the exceptions (Discord, `mornye_discord/ios`,
  `desktop_platform.dart`) and the change records.
- Migration test (FR-011) and characterization tests (FR-012) listed in tasks.
- Pubspec.lock review: the Android-resolved package versions are unchanged after `flutter pub get`.
- Owner-run checks (pending, constitution X): the release APK build (`scripts/build_android.sh --lite`) and
  `scripts/check_backend_apk.py` on the arm64 APK; installing it on an arm64 device and opening library, playback and
  settings.

## Open choices for the owner

- none
