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

- 2026-11-09: Correction to the pre-existing failure entry above: the `mornye-extensions` cover test was fixed by
  applying upstream commit 4831b065 during the work (part of a26367d); its pass is confirmed by the rust check below
- 2026-11-09: Scope added by the owner: Discord removed completely (PD-3 v3), Windows path identity and the other
  non-Android remnants removed (PD-9), dead code removed after an audit with a reference search per item (PD-10);
  inventory in plan.md, all in a26367d
- 2026-11-09: Release APK built in the sandbox with `scripts/build_android.sh` from the tree of a26367d:
  `check_backend_apk.py` OK, arm64-v8a only, 18 native libraries, signed with the debug key,
  sha256 38392d546e91f6422e9a798bdfa562f58d463a51a8c7c3b3337c88493fc8a59e. Sandbox-only build setup (not in the
  repository): Maven Central through Google's mirror, NDK 28.2.13676358 for the jni plugin, FLAC, Oboe and WavPack
  sources from git clones whose archives match the pinned SHA-256 values
- 2026-11-09: Owner rewrote the history on request: base 0912a8e and e02860c kept, then 365dcae (workflow),
  a8301fc (this record), a26367d (the change), force-pushed with lease after the owner approved
- 2026-11-09: Owner reported that the APK works on their device; device model and Android version not given yet
- 2026-11-09: `test/update_checker_test.dart` had been deleted with the removed platforms; restored for arm64 only
  (468c100), 16 passed
- 2026-11-09: Design review round 2 (goldfish-reader, design-critic): dirty, 15 major and 3 nit findings
  (F-002 to F-019), resolved in spec.md, plan.md, assurance.json, state.json and commit 4fac672
- 2026-11-09: Pre-work baseline for the skipped tests, worktree at e02860c with the patched SDK: the 3
  album_detail_header blur tests, the 2 listening_rewind_backdrop blur tests and the material_player_backdrop
  band-mask cases fail there too; the semantics regression test passes
- 2026-11-09: Correction: the semantics regression test had been skipped as an SDK failure; it fails only on an
  unpatched SDK and guards the project's patch applied by `scripts/prepare_flutter_sdk.dart`; unskipped in 4fac672
- 2026-11-09: Update check no longer reads the device ABIs (4fac672); regression test failed before the fix and
  passes after; state.json base set to 365dcae, an ancestor of HEAD

## Close

- Drift: [FILL: what the final code does that spec.md or plan.md does not say, and which side was updated; or "none"]
- Not verified: [FILL: device checks and paths no test covers; or "none"]
- Lessons: [FILL: a mistake seen twice and the check that now catches it; or "none"]
