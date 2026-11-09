# Tasks 001-android-arm64-only: Android arm64 only

<!-- Format: - [ ] T001 [P] [US1] What changes, in which file (FR-001) — check: <command or observable result>
     Mark [x] only after the check passed, and log the evidence in log.md. -->

## Phase 1: Foundation (build, native, CI and dependencies)

- [ ] T001 Delete the Flutter platform folders ios/, macos/, windows/, linux/ (FR-003) — check: `test ! -d ios -a ! -d macos -a ! -d windows -a ! -d linux`
- [ ] T002 [P] Remove crates/desktop from rust_backend/Cargo.toml members and delete the crate (FR-004) — check: `cargo test --manifest-path rust_backend/Cargo.toml --workspace`
- [ ] T003 [P] Keep only aarch64-linux-android in scripts/build_rust_backend.sh and scripts/check_rust_backend.sh; delete the desktop and iOS branches (FR-002, FR-004) — check: `bash -n` and grep for armv7/ios/desktop
- [ ] T004 [P] Keep only arm64-v8a in scripts/build_android.sh, scripts/check_backend_apk.py and their tests (FR-001) — check: `python3 -m unittest discover -s scripts -p 'test_build_android.py'` and `test_check_backend_apk.py`
- [ ] T005 [P] Keep only arm64-v8a in android/app/build.gradle.kts, the CMake ABI list and the Gradle property (FR-001) — check: grep for armeabi
- [ ] T006 [P] Delete iOS, macOS, Windows and desktop scripts (scripts/build_ios.sh, check_backend_ios.py and test, embed_*, package_*, fetch_desktop_ffmpeg.sh, setup_macos_signing.sh, build_rust_backend_windows.ps1, and their tests) (FR-004) — check: grep for references
- [ ] T007 [P] Delete .github/workflows/desktop.yml and remove iOS, desktop and armeabi jobs and steps from ci.yml and release.yml (FR-006) — check: YAML parses and grep finds no iOS/desktop jobs
- [ ] T008 Remove desktop-only dependencies from pubspec.yaml (desktop_drop, media_kit*, smtc_windows, path_provider_windows, sqflite_common_ffi, audioplayers_darwin, flutter_secure_storage_darwin) and their third_party copies (FR-005) — check: `flutter pub get`

## Phase 2: Dart (backend and desktop code)

- [ ] T009 Remove RustFfiBackend and FfiBackendTransport and make backend_channel.dart always use MethodChannelBackend (PD-4, FR-005) — check: `flutter analyze`
- [ ] T010 Delete desktop-only Dart files and their tests (lib/widgets/desktop, lib/services/link/desktop, desktop_*, media_session_desktop, ffmpeg_desktop, windows_path_identity, iOS-only files) (FR-005) — check: `flutter analyze`
- [ ] T011 Remove iOS, macOS, Windows, Linux and desktop platform branches from the remaining Dart code (FR-005) — check: `flutter analyze` and grep for Platform.is(IOS|MacOS|Windows|Linux) and isDesktopPlatform
- [ ] T012 Fix integration_test/ and test/ after the removals; keep Android tests, do not weaken any (SC-003) — check: `flutter test`

## Phase 3: Verification and records

- [ ] T013 Run the host checks: analyze, dart-tests, rust and workflow (SC-003, SC-004) — check: `work.py check auto`
- [ ] T014 Grep proof of removal (SC-002) — check: search returns no platform references outside change records

- [ ] T015 Keep the Discord SDK integration unchanged (FR-007) — check: `git diff --stat` shows no change under third_party/mornye_discord, lib/services/discord*, scripts/*discord*, and the Discord Android code
- [ ] T016 Keep Android behaviour: no Android test removed, skipped or loosened (FR-008, SC-003) — check: `git diff` of test/ and android/ shows only removals of desktop/iOS-only tests

## Convergence
