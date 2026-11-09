# Tasks 001-android-arm64-only: Android arm64 only (v2)

<!-- Format: - [ ] T001 [P] [US1] What changes (FR-xxx) — check: <command or observable result>
     Mark [x] only after the check passed, and log the evidence in log.md. Per-file actions are in inventory.md. -->

## Phase 0: Characterization before edits

- [x] T001 Characterization test for the sqflite factory and the Android documents directory with debugDesktopPlatformOverride=false (FR-012, R9) — check: `flutter test test/<new file>` passes before any edit — superseded by spec v3 (first install, FR-012): not run
- [x] T002 Settings and backup JSON round-trip characterization over the current fields and keys (FR-012, R8) — check: `flutter test` passes before any edit — superseded by spec v3 (FR-012): not run
- [x] T003 Update-check characterization: arm64 asset matches, no-match result is typed (FR-009) — check: test written and failing on the arm32 expectation before edit (the arm64 path passes) — done: test/update_checker_test.dart restored for arm64 only (468c100, 4fac672), 17 passed
- [x] T004 Migration test scaffold: database created by the previous schema version, Link tables dropped, other tables and rows kept (FR-011) — check: test written and failing before the migration — superseded by spec v3 (FR-011, no migration): not run

## Phase 1: Build, native, CI, dependencies, docs

- [x] T010 [P] android/app/build.gradle.kts: arm64-v8a only, no isUniversalApk, no armeabi (FR-001) — check: grep armeabi/isUniversalApk returns nothing — done: no armeabi or isUniversalApk in android/app/build.gradle.kts; splits disabled, abiFilters arm64-v8a
- [x] T011 [P] scripts/build_rust_backend.sh: Android branch builds aarch64-linux-android only (FR-002) — check: `bash -n scripts/build_rust_backend.sh` and grep armv7 — done: bash -n passes; no armv7 in scripts/build_rust_backend.sh
- [x] T012 [P] scripts/build_android.sh and scripts/check_backend_apk.py: arm64-v8a only, no universal APK; update their tests (FR-001) — check: `python3 -m unittest discover -s scripts -p 'test_build_android.py'` and `test_check_backend_apk.py` — done: python3 -m unittest discover -s scripts, 16 tests OK; APK audit OK on the release APK
- [x] T013 [P] scripts/check_android_statx.sh: arm64 only (FR-001) — check: `bash -n` and grep armv7 — done: bash -n passes; no armv7 in scripts/check_android_statx.sh
- [x] T014 [P] Delete scripts for iOS, macOS, Windows, desktop: build_ios.sh, check_backend_ios.py and its test, embed_*.sh, package_linux.sh, package_macos_dmg.sh, fetch_desktop_ffmpeg.sh, setup_macos_signing.sh, build_rust_backend_windows.ps1 (FR-004) — check: `test ! -e` for each and grep for references — done: none of the listed scripts exist
- [x] T015 [P] Delete .github/workflows/desktop.yml; remove iOS, desktop and armeabi jobs and steps from ci.yml and release.yml (FR-006) — check: YAML parses; grep finds no iOS/desktop/armeabi — done: desktop.yml removed; ci.yml and release.yml parse and contain no iOS, macOS, Windows, desktop or armeabi job
- [x] T016 Delete crates/desktop and crates/link; prune workspace members and deps; regenerate Cargo.lock; run with --locked (FR-002, FR-004, PD-1) — check: `cargo test --manifest-path rust_backend/Cargo.toml --workspace --locked` — done: crates/desktop and crates/link removed; cargo test --workspace --locked in the rust check
- [x] T017 Delete the Flutter platform folders ios/, macos/, windows/, linux/ (FR-003) — check: `test ! -d` for each — done: ios/, macos/, windows/ and linux/ have no tracked files
- [x] T018 third_party: delete audioplayers_darwin and media_kit_libs_windows_audio; delete the non-Android subfolders of ffmpeg_kit_flutter_new_audio and audio_service; keep mornye_discord whole (FR-004, FR-007) — check: `git ls-files third_party | grep -v android` review — done: third_party holds audio_service, audioplayers_android and ffmpeg_kit_flutter_new_audio only; mornye_discord removed by v3 (FR-007)
- [x] T019 pubspec.yaml: remove desktop-only deps and overrides (desktop_drop, media_kit*, smtc_windows, path_provider_windows, sqflite_common_ffi, audioplayers_darwin, flutter_secure_storage_darwin, dependency_overrides for windows/linux) and the launcher icon entries for ios, macos, windows; remove icon_macos.png if unused (FR-004) — check: `flutter pub get` — done: desktop-only dependencies removed; sqflite_common_ffi stays as a dev dependency for host tests
- [x] T020 pubspec.lock review: Android-resolved package versions unchanged (SC-003) — check: diff of pubspec.lock lists only removed desktop packages — done: no Android-resolved version changed; 18 packages removed; flutter_secure_storage_darwin (Apple only) moved 0.4.3 to 0.3.2 after its override was removed
- [x] T021 README.md and rust_backend/README.md: remove desktop, iOS and armeabi instructions (constitution III) — check: grep finds no removed platform instructions — done: README.md and rust_backend/README.md describe Android arm64 only

## Phase 2: Dart

- [x] T030 Remove RustFfiBackend and FfiBackendTransport; backend_channel.dart always uses MethodChannelBackend (PD-4, FR-005) — check: `flutter analyze` — done: no RustFfiBackend or FfiBackendTransport in lib or test; flutter analyze clean
- [x] T031 update_checker.dart: arm64 only; remove arm32 and universal branches (FR-009) — check: T003 test passes; `flutter analyze` — done: update check offers only the arm64 APK and no longer reads the device ABIs (4fac672); test/update_checker_test.dart 17 passed
- [x] T032 Delete the Link tree (lib/services/link/**, lib/widgets/link/**, lib/screens/settings/link_*.dart) and the desktop-only lib files in inventory.md (FR-010) — check: `flutter analyze` after the edits below — done: lib/services/link, lib/widgets/link and lib/screens/settings/link_*.dart removed
- [x] T033 Edit the importers and shared files in inventory.md (rows marked edit) to remove Link, desktop, iOS, macOS, Windows, Linux and arm32 references; keep the Android path — check: `flutter analyze` — done: flutter analyze clean; the SC-002 search finds no Link, desktop, iOS, macOS, Windows or Linux branch
- [x] T034 Database migration: drop the Link sync tables, bump the schema version, keep every other table and row (FR-011, PD-6) — check: T004 test passes — superseded by spec v3 (FR-011, no migration): not run
- [x] T035 Keep Discord exceptions unchanged: discord_presence_service.dart and lib/utils/desktop_platform.dart (FR-007, PD-3) — check: `git diff` on those files is empty or shortcut-only — superseded by spec v3 (FR-007, Discord removed completely): not kept
- [x] T036 Delete the test files in inventory.md (rows marked delete) and edit the rows marked edit so they test the MethodChannel backend (FR-008, SC-003) — check: `flutter test` runs, no test skipped without reason — done: tests of removed features deleted; kept-feature tests pass or are skipped with a reason (plan Complexity tracking)

## Phase 3: Verification and records

- [ ] T040 Host checks: `work.py check auto` (analyze, dart-tests, rust, workflow) — check: each check PASS or BLOCKED is reported as such
- [x] T041 Searches for removed names with the exception list (SC-002) — check: search results are only exceptions and change records — done: the plan's SC-002 rg command returns no match outside the allowed places
- [ ] T042 Map update and scope: `work.py map update`, `work.py scope` — check: map current
- [ ] T043 Review rounds: fresh code review of the final tree, two clean rounds (constitution VIII) — check: `work.py round 001 code clean`

## Convergence

- [x] T050 Remove Discord completely: SDK, Android integration, settings, strings, tests (FR-007) — check: the SC-002 rg command finds no Discord — done: no match; a26367d
- [x] T051 Remove Windows path identity from Dart, Rust and the path-key contract, and the other non-Android remnants (FR-013) — check: SC-002 search; flutter test test/native_library_contract_test.dart; cargo test -p mornye-mobile — done: no match; contract test 3 passed; mornye-mobile 142 passed
- [x] T052 Remove dead code left by the removal, each item with a reference search (FR-014) — check: rg for each removed symbol finds no reference; flutter analyze — done: no references; analyze clean (60e33c2, 64177ee, d092a31, now in a26367d)
- [x] T053 Release APK built and audited (FR-001, FR-002, SC-001) — check: scripts/build_android.sh then scripts/check_backend_apk.py — done: OK, arm64-v8a only, 18 native libraries
