# Tasks 001-android-arm64-only: Android arm64 only (v2)

<!-- Format: - [ ] T001 [P] [US1] What changes (FR-xxx) — check: <command or observable result>
     Mark [x] only after the check passed, and log the evidence in log.md. Per-file actions are in inventory.md. -->

## Phase 0: Characterization before edits

- [ ] T001 Characterization test for the sqflite factory and the Android documents directory with debugDesktopPlatformOverride=false (FR-012, R9) — check: `flutter test test/<new file>` passes before any edit
- [ ] T002 Settings and backup JSON round-trip characterization over the current fields and keys (FR-012, R8) — check: `flutter test` passes before any edit
- [ ] T003 Update-check characterization: arm64 asset matches, no-match result is typed (FR-009) — check: test written and failing on the arm32 expectation before edit (the arm64 path passes)
- [ ] T004 Migration test scaffold: database created by the previous schema version, Link tables dropped, other tables and rows kept (FR-011) — check: test written and failing before the migration

## Phase 1: Build, native, CI, dependencies, docs

- [ ] T010 [P] android/app/build.gradle.kts: arm64-v8a only, no isUniversalApk, no armeabi (FR-001) — check: grep armeabi/isUniversalApk returns nothing
- [ ] T011 [P] scripts/build_rust_backend.sh: Android branch builds aarch64-linux-android only (FR-002) — check: `bash -n scripts/build_rust_backend.sh` and grep armv7
- [ ] T012 [P] scripts/build_android.sh and scripts/check_backend_apk.py: arm64-v8a only, no universal APK; update their tests (FR-001) — check: `python3 -m unittest discover -s scripts -p 'test_build_android.py'` and `test_check_backend_apk.py`
- [ ] T013 [P] scripts/check_android_statx.sh: arm64 only (FR-001) — check: `bash -n` and grep armv7
- [ ] T014 [P] Delete scripts for iOS, macOS, Windows, desktop: build_ios.sh, check_backend_ios.py and its test, embed_*.sh, package_linux.sh, package_macos_dmg.sh, fetch_desktop_ffmpeg.sh, setup_macos_signing.sh, build_rust_backend_windows.ps1 (FR-004) — check: `test ! -e` for each and grep for references
- [ ] T015 [P] Delete .github/workflows/desktop.yml; remove iOS, desktop and armeabi jobs and steps from ci.yml and release.yml (FR-006) — check: YAML parses; grep finds no iOS/desktop/armeabi
- [ ] T016 Delete crates/desktop and crates/link; prune workspace members and deps; regenerate Cargo.lock; run with --locked (FR-002, FR-004, PD-1) — check: `cargo test --manifest-path rust_backend/Cargo.toml --workspace --locked`
- [ ] T017 Delete the Flutter platform folders ios/, macos/, windows/, linux/ (FR-003) — check: `test ! -d` for each
- [ ] T018 third_party: delete audioplayers_darwin and media_kit_libs_windows_audio; delete the non-Android subfolders of ffmpeg_kit_flutter_new_audio and audio_service; keep mornye_discord whole (FR-004, FR-007) — check: `git ls-files third_party | grep -v android` review
- [ ] T019 pubspec.yaml: remove desktop-only deps and overrides (desktop_drop, media_kit*, smtc_windows, path_provider_windows, sqflite_common_ffi, audioplayers_darwin, flutter_secure_storage_darwin, dependency_overrides for windows/linux) and the launcher icon entries for ios, macos, windows; remove icon_macos.png if unused (FR-004) — check: `flutter pub get`
- [ ] T020 pubspec.lock review: Android-resolved package versions unchanged (SC-003) — check: diff of pubspec.lock lists only removed desktop packages
- [ ] T021 README.md and rust_backend/README.md: remove desktop, iOS and armeabi instructions (constitution III) — check: grep finds no removed platform instructions

## Phase 2: Dart

- [ ] T030 Remove RustFfiBackend and FfiBackendTransport; backend_channel.dart always uses MethodChannelBackend (PD-4, FR-005) — check: `flutter analyze`
- [ ] T031 update_checker.dart: arm64 only; remove arm32 and universal branches (FR-009) — check: T003 test passes; `flutter analyze`
- [ ] T032 Delete the Link tree (lib/services/link/**, lib/widgets/link/**, lib/screens/settings/link_*.dart) and the desktop-only lib files in inventory.md (FR-010) — check: `flutter analyze` after the edits below
- [ ] T033 Edit the importers and shared files in inventory.md (rows marked edit) to remove Link, desktop, iOS, macOS, Windows, Linux and arm32 references; keep the Android path — check: `flutter analyze`
- [ ] T034 Database migration: drop the Link sync tables, bump the schema version, keep every other table and row (FR-011, PD-6) — check: T004 test passes
- [ ] T035 Keep Discord exceptions unchanged: discord_presence_service.dart and lib/utils/desktop_platform.dart (FR-007, PD-3) — check: `git diff` on those files is empty or shortcut-only
- [ ] T036 Delete the test files in inventory.md (rows marked delete) and edit the rows marked edit so they test the MethodChannel backend (FR-008, SC-003) — check: `flutter test` runs, no test skipped without reason

## Phase 3: Verification and records

- [ ] T040 Host checks: `work.py check auto` (analyze, dart-tests, rust, workflow) — check: each check PASS or BLOCKED is reported as such
- [ ] T041 Searches for removed names with the exception list (SC-002) — check: search results are only exceptions and change records
- [ ] T042 Map update and scope: `work.py map update`, `work.py scope` — check: map current
- [ ] T043 Review rounds: fresh code review of the final tree, two clean rounds (constitution VIII) — check: `work.py round 001 code clean`

## Convergence
