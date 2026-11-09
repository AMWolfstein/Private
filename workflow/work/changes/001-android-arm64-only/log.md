# Log 001-android-arm64-only: Android arm64 only

<!-- Append-only. One line per decision, step or result: date, what, evidence (commit, command and result,
     file:line). Never rewrite an earlier line; add a correction below it. -->

## Entries

- 2026-11-09: change created
- 2026-11-09: owner clarified v3: Discord removed completely, first install (no migration), finish in one change
- 2026-11-09: Dart lib cleaned: `flutter analyze` reports no issues (commits 5704de4, db72649, eee0c18, acc024c)
- 2026-11-09: Android Gradle: arm64-v8a only, no universal APK, Discord SDK and pickFirsts removed; Link service
  and manifest entries removed (`android/app/build.gradle.kts`, `AndroidManifest.xml`, `MainActivity.kt`)
- 2026-11-09: Build and CI: `scripts/build_android.sh`, `build_rust_backend.sh`, `check_backend_apk.py` and their
  tests rewritten for arm64 only; `python3 -m unittest` for build and APK audit: 10 tests OK; CI and release
  workflows reduced to the Android arm64 job (iOS, desktop, Discord jobs removed); YAML parses
- 2026-11-09: Rust workspace: desktop and link crates removed from members; `Cargo.lock` regenerated (182 deletions,
  no version changes)
- 2026-11-09: Tests: test files that exercised removed desktop, Link, Discord, exclusive output, remote playback,
  FFI backend and iOS paths are deleted or their cases removed; `flutter analyze` reports no issues over test
  and integration_test
- 2026-11-09: Pre-existing failure, not caused by this change: `mornye-extensions`
  `backend::cover::tests::android_names_share_one_file_per_picture_and_keep_legacy_references` fails at 29cf460
  (the commit before this work) with the same assertion

## Close

- Drift: [FILL: what the final code does that spec.md or plan.md does not say, and which side was updated; or "none"]
- Not verified: [FILL: device checks and paths no test covers; or "none"]
- Lessons: [FILL: a mistake seen twice and the check that now catches it; or "none"]
