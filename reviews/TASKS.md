# Fix tasks from the audit

The audit left 139 open findings in `FINDINGS.md` (1 P1, 54 P2, 84 P3). Every one of them
is assigned to one of the 12 tasks below, so finishing them all closes the audit. T1-T8 fix
bugs (each also carries the P3 findings in the same code), T9-T10 are performance, and
T11-T12 are UI polish and build/test cleanup. Do them in order. Three findings are already
gone and need no task (see the last section).

## Instructions for opencode (read first, follow exactly)

You fix the tasks below one at a time, in order (T1 first). Each task goes through these
steps. Do not skip, merge or reorder steps, and do not start the next task before the
current one is pushed.

### Hard rules

- **Never build an APK.** Do not run `flutter build`, `gradlew assemble*` or `bundle*`, and
  do not sign anything.
- **Never force-push**, rebase, amend or rewrite commits. Never use `git add -A` or `git add .`.
- **Do not run tests while you work.** No `flutter test`, `flutter analyze` or check scripts
  until step 6. Write the tests you need, but run them only in step 6.
- **No commit before review.** Nothing is committed until the reviewer agents in step 5 have
  checked the code and every real finding from them is fixed.
- **Use graphify to move around the project.** Before opening or editing any file, find it
  with graphify. Use `grep` only to cross-check what graphify showed you, never as the first
  search.
- Read `AGENTS.md` once before T1 and keep to its product rules: Mornye only, RTL,
  semantics, 0.5 disabled opacity, offline only, and no new glass package.
- Only change what the task's findings need. Make no unrelated refactors and no renames.
- Never report a device test as passed. Device testing belongs to the owner.

### Steps for each task

1. **Read.** Open `FINDINGS.md` and read every finding ID in the task, including the
   "Also" ones. The line numbers there are old, so go by the function names.
2. **Locate with graphify.** For each finding run
   `graphify explain "<function or class name>"` and `graphify query "<what the finding is
   about>"`. Use `graphify path "<A>" "<B>"` when you need to know how two parts connect, for
   example a Dart caller and a Kotlin channel. This tells you the files, callers and
   dependents. Read only those files.
3. **Confirm.** Check that each finding is still real in the current code.
   - If it is already fixed or gone, change nothing for it and note it for the docs commit.
   - A finding marked `NEEDS VERIFICATION` must be shown to happen, by tracing the path or
     writing the failing test, before you fix it. If it cannot happen, it is rejected; note
     why.
   - Performance findings: record the "before" number first, using `EXPLAIN QUERY PLAN`, a
     timed host test or a rebuild count. A finding marked "only if measured" that shows no
     real cost is rejected with that number.
4. **Fix.** Make the smallest fix for each real finding, and add a regression test for each
   one. Do not run anything yet.
5. **Review with the agents.** Run the reviewer agents listed under the task in **Reviewers**.
   - The reviewers are OpenCode subagents in `.opencode/agents/`, generated from
     `.claude/agents/` by `scripts/sync_opencode_agents.py`. They follow
     `reviews/PROTOCOL.md`, can only read code, and run only read-only git and graphify
     commands.
   - Call each one by name, for example `@kotlin-android-auditor`, or through the `task`
     tool with that agent. Give it a brief: the uncommitted diff (`git diff`), the files and
     symbols changed, the graphify dependents from step 2, and the finding IDs.
   - Run the fixes from the `build` agent. The default `plan` agent cannot edit files.
   - Fix every real P0, P1 or P2 they report, then run the same reviewer again on the new
     diff. Repeat until it reports none.
   - A P3 from them is fixed now if it is in code this task changed. Otherwise add it to
     `FINDINGS.md` as a new open finding.
6. **Test once.** Now run all of these:
   - `flutter analyze`, which must report `No issues found!`.
   - The full `flutter test`, once.
   - `bash scripts/check_rust_backend.sh` if Rust changed.
   - `bash scripts/check_android.sh` if Kotlin or Android changed.

   If a test fails because it was already stale, or because the fix legitimately changed the
   expected behaviour, fix that test and re-run only its file. If a failure is caused by your
   fix, fix the code, repeat step 5 for that change, and re-run only the failing files. Never
   skip, disable or delete a test to get green. For performance findings, record the "after"
   number.
7. **Commit**, as three separate commits in this order. Stage each path explicitly.
   1. Code: `lib/`, `test/`, `android/`, `rust_backend/` and so on, with a message like
      `fix(<area>): <what> (T<n>: <IDs>)`. Never include `graphify-out/`, `reviews/` or
      `LOCAL_OFFLINE_MIGRATION_PLAN.md`.
   2. Graph: run `graphify update .`, then commit only the tracked `graphify-out/` files as
      `chore(graphify): refresh code graph after T<n>`.
   3. Docs: `reviews/FINDINGS.md`, `reviews/TASKS.md` and `LOCAL_OFFLINE_MIGRATION_PLAN.md`,
      as `docs: record T<n> fixes`.
      - In `FINDINGS.md`, move each fixed finding to `## Resolved` with the code commit hash,
        and each rejected one to `## Rejected` with the reason.
      - Tick the task's box here.
      - Record the test results exactly (passed, failed and skipped counts), and for
        performance tasks the before and after numbers.
8. **Push** with `git push -u origin <current branch>`. Then check that
   `git rev-parse HEAD` equals `git rev-parse origin/<branch>`. Report the push only after
   that check passes, and retry only on network errors.

### Reviewers

| Task | Reviewer agents |
|---|---|
| T1 | kotlin-android-auditor, data-integrity-auditor |
| T2 | data-integrity-auditor, test-auditor |
| T3 | data-integrity-auditor, rust-safety-auditor; add kotlin-android-auditor for DATA-306 |
| T4 | rust-safety-auditor, api-compat-auditor (the library and cover ID change) |
| T5 | api-compat-auditor, bug-hunter |
| T6 | rust-safety-auditor, bug-hunter |
| T7 | concurrency-auditor, flutter-dart-auditor |
| T8 | bug-hunter, security-auditor |
| T9 | code-optimization-auditor, data-integrity-auditor (the schema upgrade) |
| T10 | code-optimization-auditor, rust-safety-auditor |
| T11 | ux-auditor, flutter-dart-auditor |
| T12 | dependency-auditor, test-auditor |

Always add security-auditor when a change touches file deletion, SAF permissions, intents
or exported components.

## Tasks

- [ ] **T1: SAF scans must not wipe or miss library rows** (Kotlin)
  - Findings: DATA-501 (P1), KT-201, KT-202, KT-203, KT-102.
  - Files: `android/.../MainActivitySafScan.kt` (`querySafChildrenOrThrow`,
    `scanSafTreeIncremental`, `scanSafTree` resume), `MainActivity.kt`
    (`safTreeLauncher`).
  - Goal: a provider error during a scan aborts it without deleting that folder's rows.
    Incremental scans pick up changed CUE sheets and removed files, and a resumed scan
    keeps the correct state.
  - Also: KT-103, KT-104, KT-105, KT-204, KT-205, DATA-204.

- [ ] **T2: Make CUE delete and split safe**
  - Findings: DATA-001, BUG-301, TEST-301, BUG-001, BUG-002.
  - Files: `lib/widgets/local_song_file_actions.dart` (`isCueSong`, `deleteLocalSong`,
    `splitLocalCue`), `lib/services/local_track_batch_actions.dart`
    (`deleteLibraryTracks`).
  - Goal: deleting a virtual CUE row never deletes the backing CUE or audio, from any
    screen or batch delete. A failed cover embed on one file no longer aborts the whole
    split. Tapping Split twice does not start two jobs.
  - Also: UX-001, UX-002, UI-001, BUG-003, DATA-305, SEC-003, SEC-201, TEST-001, TEST-002,
    TEST-003.

- [ ] **T3: Make tag writing and the metadata editor correct**
  - Findings: DATA-301, DATA-302, DATA-303, DATA-306, RUST-101, RUST-102, RUST-402.
  - Files: `lib/services/ffmpeg_metadata.dart` (MP3/M4A embed),
    `lib/widgets/local_song_menu.dart` (`editLocalSongMetadata`),
    `lib/controllers/metadata_editor_controller.dart`, `MainActivitySafIo.kt`
    (`writeUriFromPath`), `rust_backend/crates/core/src/tags/id3.rs`,
    `tags/write/id3.rs`, `crates/mobile/src/native_id3.rs`.
  - Goal: MP3 and M4A edits keep every field. SAF write-back really replaces the file.
    ID3 text decodes correctly, and the truncating `break` in ID3 frame reading and
    writing is fixed in both places.
  - Also: BUG-104, RUST-103, RUST-104, RUST-105, RUST-106, DATA-304, DATA-307, DATA-401,
    DATA-402.

- [ ] **T4: Fix Rust CUE parsing, library IDs and the cover cache**
  - Findings: RUST-202, RUST-203, RUST-204, DATA-502, CONC-101, CONC-102.
  - Files: `rust_backend/crates/core/src/cue.rs`, `core/src/tags/library.rs`
    (`library_id`), `core/src/cover/library.rs`, `crates/local/src/backend/library.rs`
    (`resolve_cue_audio`, `cue_library_rows`), `crates/local/src/backend/cover.rs`
    (`cache_cover`).
  - Goal: CUE FILE lines and timestamps parse correctly. Library and cover IDs no longer
    collide (if the stored ID format changes, keep old databases working). CUE audio lookup
    ignores case. Concurrent cover caching is safe.
  - Also: CONC-103, CONC-104, RUST-001, RUST-002, RUST-301.

- [ ] **T5: Fix backup restore, settings restore and startup**
  - Findings: API-001, API-002, API-201, API-202, API-203, UX-003.
  - Files: `lib/services/backup_service.dart`, `lib/providers/settings_provider.dart`
    (`restoreFromBackup`), `lib/main.dart` (`_prepareAndroidInstallationState`),
    `lib/screens/main_shell.dart` (`_repairSafAccessIfNeeded`), `lib/models/settings.dart`.
  - Goal: history restore and the backup archive stay consistent. An old backup no longer
    sends the user back to setup or imports another device's folder path. The
    download-era settings, the SAF repair dialog and the migration prompt are removed or
    corrected, and startup no longer waits up to 2 s for them. Keep old backup files
    importable.
  - Also: API-003, API-204, API-205, UX-204, DATA-101, DEAD-702, DEAD-806, TEST-303.

- [ ] **T6: Fix lyrics parsing**
  - Findings: BUG-101, RUST-401, RUST-403.
  - Files: `lib/utils/lyrics_parser.dart` (`parse`, `_parseTtml`),
    `rust_backend/crates/mobile/src/native_lyrics.rs` (`parse_ttml`, `parse_lrc`).
  - Goal: untimed TTML shows as plain lyrics instead of being dropped, in both the Dart and
    Rust parsers, and the LRC edge cases parse correctly.
  - Also: BUG-102, BUG-103, UI-102.

- [ ] **T7: Fix playback and visible UI bugs**
  - Findings: CONC-001, CONC-002, UI-101, UI-201, UX-201, BUG-201, BUG-202.
  - Files: `lib/services/music_player_service.dart` (`seek`, `skipToPrevious`,
    `onSourceDeleted`), `lib/widgets/mini_player.dart` (`_dismissedItemId`),
    `lib/widgets/batch_progress_dialog.dart` (`dismiss`),
    `lib/screens/settings/cache_management_page.dart`,
    `lib/providers/local_artist_provider.dart` (`localArtistPopularProvider`),
    `lib/providers/library_search_provider.dart`.
  - Goal:
    - No seek or restart race, and deleting the playing file is handled.
    - The mini player no longer hides on pause after one swipe-dismiss.
    - Back during batch progress closes only the dialog.
    - The Cache page shows its error instead of spinning forever.
    - Artist Popular stays stable while the page is open.
    - Search honours the Local Library setting.
  - Do not rewrite the playback engine.
  - Also: CONC-003, CONC-004, KT-001, KT-002, SEC-101, SEC-303, BUG-302, DEAD-604.

- [ ] **T8: Fix library queries, search, duplicates and file-access scope**
  - Findings: DATA-002, DATA-003, DATA-004, DATA-201, DATA-203, SEC-001, SEC-002, BUG-203,
    BUG-204, UI-202, UI-401.
  - Files: `lib/services/library_database.dart` (`getAll`, `getQueueLocalAlbumTracks`),
    `library_queue_store.dart`, `library_search.dart`, `library_duplicates.dart`,
    `lib/utils/duplicate_cleanup_policy.dart`, `lib/utils/file_access.dart`
    (`deleteFile`), `lib/utils/local_library_scan_prefs.dart`,
    `lib/providers/local_library_provider.dart`, `lib/screens/queue_tab*.dart`,
    `lib/screens/settings/log_screen.dart`.
  - Goal:
    - Shuffle no longer loads the whole library (DATA-002; only `shuffleLibrary` is
      left).
    - Albums are found by key, not by name.
    - Singles and albums are counted correctly.
    - Search tokenization works beyond letters and numbers.
    - Duplicate keep-best picks correctly.
    - `deleteFile` cannot reach outside the library.
    - The scan-prefs read is safe.
    - Selection counts, the log list and library reloads stay correct.
  - Also: DATA-202, BUG-205, UX-203.

- [ ] **T9: Make library queries and screen rebuilds cheaper**
  - Findings: PERF-401, PERF-402, PERF-404 (P2); also PERF-201, PERF-202, PERF-301,
    PERF-405, PERF-601, PERF-602, PERF-603, PERF-604.
  - Files: `lib/services/library_schema.dart` (`_createNormalizedIndexes`),
    `library_queue_store.dart`, `library_genres.dart`, `library_database.dart`
    (`getLookupIndex`), `lib/providers/local_library_provider.dart`,
    `local_artist_provider.dart`, `lib/screens/queue_tab.dart`,
    `queue_tab_filter_widgets.dart`, `library_tracks_folder_screen.dart`,
    `home_tab_feed.dart`, `lib/theme/cover_palette.dart`, `lib/main.dart`.
  - Goal:
    - Artist pages and the Artists shelf use an `album_artist_norm` index instead of
      scanning the whole library. The index is added in a schema upgrade.
    - Genres are split once per library version instead of on every page.
    - The unused lookup sets and `getLookupIndex` are removed.
    - Artist Popular gets its top 20 with one query.
    - Songs, Home and playlist screens stop rebuilding or recomputing lists they do not
      use.
    - At startup, the orientation call runs in parallel with the other startup steps.
  - Do PERF-301, PERF-405, PERF-603 and PERF-604 only if the measurement shows a cost.

- [ ] **T10: Make scanning and cover caching cheaper**
  - Findings: PERF-501, PERF-502 (P2); also PERF-503, PERF-504.
  - Files: `rust_backend/crates/local/src/backend/cover.rs` (`cache_cover`),
    `crates/local/src/files.rs` (`StagedFile::publish`),
    `crates/local/src/backend/library.rs`, `core/src/tags/containers.rs`,
    `MainActivitySafIo.kt` (`acceptRead`), `SafMetadataReadPolicy.kt`,
    `MainActivitySafScan.kt`.
  - Goal:
    - Tracks with the same embedded cover write one cover file, and covers are written
      without an fsync per file.
    - Files with unreadable tags are no longer copied whole on every scan.
    - Ogg/Opus covers are assembled once.
    - Incremental scans stop re-copying unchanged CUE sheets.
  - Do this after T4, which changes the same cover cache.

- [ ] **T11: Polish the UI and accessibility**
  - Findings (all P3): UX-102, UX-103, UX-105, UX-106, UX-107, UX-202, UX-207, UI-203,
    UI-204, UI-205, UI-206, BUG-303, BUG-304.
  - Files: `lib/screens/local_artist_screen.dart` (Popular dots, row height),
    `local_album_screen.dart`, `lib/widgets/album_detail_header.dart`,
    `listening_statistics_screen.dart`, `settings/cache_management_page.dart`,
    `library_tracks_folder_screen.dart`, `queue_tab_navigation.dart`,
    `playlist_picker_sheet.dart`, `duplicate_review_sheet.dart`,
    `lib/utils/clickable_metadata.dart`, `lib/services/app_orientation.dart`.
  - Goal: each finding's fix as written. Keep the current header sizes (48 dp controls,
    22 dp icons), RTL and the AGENTS.md Popular rules (five songs per page, at most four
    dots).

- [ ] **T12: Clean up build, dependencies and tests**
  - Findings (all P3): SEC-302, DEP-001, DEP-002, TEST-101, TEST-203, TEST-205.
  - Files: `android/app/build.gradle.kts` (release signing), `pubspec.yaml`,
    `rust_backend/NOTICE`, `test/library_collections_hydration_test.dart`,
    `test/support/library_collections_benchmark.dart`, and the tests that TEST-205 lists.
  - Goal:
    - A release build without a keystore warns or fails instead of silently using the
      debug key.
    - Unused packages and stale NOTICE lines are removed.
    - Timing-based test asserts are made stable.
    - Bare `length` and `isEmpty` asserts become matchers that print what went wrong.
    - TEST-101 is closed if the dead-code sweep it served is finished.
  - Do not build or sign an APK.

## What is already fixed (checked 2026-10-22 against `89bf53b`)

The audit's fixed and removed findings are already under `## Resolved` in `FINDINGS.md` and
are not in these tasks: the DEAD-* cleanup, all MORN-*, HOME-*, PLAY-*, RUST-201, TEST-201,
TEST-202, TEST-204 and TEST-304.

Every P1/P2 finding was re-checked in the current code and is still present, with one
exception. DATA-002 is half fixed: the Home recent-album tap it named was removed with
`home_tab_recent.dart`, so only the `shuffleLibrary` whole-library `getAll()` remains. No
commit since the audit names any other finding ID. Fixes since then (for example the dead-code
batch) did not touch the code these findings point at. The `NEEDS VERIFICATION` items
(DATA-001, DATA-004, BUG-203, BUG-204, UI-202, UI-401, CONC-001, API-002, DATA-303, RUST-204,
RUST-403) still have the code they describe, but each still needs proof that it happens before
it is fixed.

Re-checked on 2026-10-22 for T9-T12 and the P3 findings: the code for three of them was
removed by the dead-code batch, so close them as resolved with that note instead of fixing
them:
- RUST-205: the Hi-Res WAV analyser (`core/src/media/hires`) no longer exists.
- BUG-105: `lyrics_metadata_helper.dart` no longer exists.
- SEC-004: `saf_display_path.dart` (`_safDocumentId`) no longer exists. The same
  double-decode pattern may exist at `local_library_provider.dart` (`Uri.decodeComponent` on
  `pathSegments`); check it in T1.

Everything else in T9-T12 still has the code it describes. PERF-401's index is still
missing: `album_artist_norm` is a column, but `_createNormalizedIndexes` does not index it.
