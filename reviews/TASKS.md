# Fix tasks from the audit

The audit left 139 open findings in `FINDINGS.md` (1 P1, 54 P2, 84 P3). This file groups
the P1 and P2 findings into 8 tasks, ordered by risk. Do them in order. The P3 findings,
and the performance findings that need measuring first, are listed at the end as optional:
each can join the task that already touches its file.

## What is already fixed (checked 2026-10-22 against `89bf53b`)

The audit's fixed and removed findings are already under `## Resolved` in `FINDINGS.md` and
are not in these tasks: the DEAD-* cleanup, all MORN-*, HOME-*, PLAY-*, RUST-201, TEST-201,
TEST-202, TEST-204 and TEST-304.

Every finding in T1-T8 was re-checked in the current code and is still present, with one
exception. DATA-002 is half fixed: the Home recent-album tap it named was removed with
`home_tab_recent.dart`, so only the `shuffleLibrary` whole-library `getAll()` remains. No
commit since the audit names any other finding ID. Fixes since then (for example the dead-code
batch) did not touch the code these findings point at. The `NEEDS VERIFICATION` items
(DATA-001, DATA-004, BUG-203, BUG-204, UI-202, UI-401, CONC-001, API-002, DATA-303, RUST-204,
RUST-403) still have the code they describe, but each still needs proof that it happens before
it is fixed.

## Rules for every task

- Read each finding in `FINDINGS.md` (search for its ID) before changing anything. The line
  numbers there are older than the current code, so find the code by the function name.
- First check the finding is still real on the current code. If it is already fixed or no
  longer reproduces, change nothing for it and write that down.
- For a finding marked `NEEDS VERIFICATION`, show it happens (a test or a traced path)
  before you fix it. If it does not happen, mark it rejected and give the reason.
- Make the smallest fix, and add a regression test for each fix. Do not refactor unrelated
  code. Keep RTL, semantics and the Mornye-only rules in `AGENTS.md`.
- Per task: run `flutter analyze` (must report `No issues found!`) and the full `flutter
  test` **once**. If a test was already stale, fix that test and re-run only its file. Rust
  changes also need `bash scripts/check_rust_backend.sh`; Kotlin changes also need
  `bash scripts/check_android.sh`. Do not build an APK.
- Make three commits per task, in this order: code, then `graphify update .` (commit only
  `graphify-out/`), then docs. The docs commit moves the fixed findings to `## Resolved` in
  `FINDINGS.md`, ticks the task here and adds a line to `LOCAL_OFFLINE_MIGRATION_PLAN.md`.
  Stage paths explicitly and never use `git add -A`.
- Push with `git push -u origin <branch>`. Never force-push.
- Device testing belongs to the owner, so never report a device test as passed.

## Tasks

- [ ] **T1: SAF scans must not wipe or miss library rows** (Kotlin)
  - Findings: DATA-501 (P1), KT-201, KT-202, KT-203, KT-102.
  - Files: `android/.../MainActivitySafScan.kt` (`querySafChildrenOrThrow`,
    `scanSafTreeIncremental`, `scanSafTree` resume), `MainActivity.kt`
    (`safTreeLauncher`).
  - Goal: a provider error during a scan aborts it without deleting that folder's rows.
    Incremental scans pick up changed CUE sheets and removed files, and a resumed scan
    keeps the correct state.

- [ ] **T2: Make CUE delete and split safe**
  - Findings: DATA-001, BUG-301, TEST-301, BUG-001, BUG-002.
  - Files: `lib/widgets/local_song_file_actions.dart` (`isCueSong`, `deleteLocalSong`,
    `splitLocalCue`), `lib/services/local_track_batch_actions.dart`
    (`deleteLibraryTracks`).
  - Goal: deleting a virtual CUE row never deletes the backing CUE or audio, from any
    screen or batch delete. A failed cover embed on one file no longer aborts the whole
    split. Tapping Split twice does not start two jobs.

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

- [ ] **T4: Fix Rust CUE parsing, library IDs and the cover cache**
  - Findings: RUST-202, RUST-203, RUST-204, DATA-502, CONC-101, CONC-102.
  - Files: `rust_backend/crates/core/src/cue.rs`, `core/src/tags/library.rs`
    (`library_id`), `core/src/cover/library.rs`, `crates/local/src/backend/library.rs`
    (`resolve_cue_audio`, `cue_library_rows`), `crates/local/src/backend/cover.rs`
    (`cache_cover`).
  - Goal: CUE FILE lines and timestamps parse correctly. Library and cover IDs no longer
    collide (if the stored ID format changes, keep old databases working). CUE audio lookup
    ignores case. Concurrent cover caching is safe.

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

- [ ] **T6: Fix lyrics parsing**
  - Findings: BUG-101, RUST-401, RUST-403.
  - Files: `lib/utils/lyrics_parser.dart` (`parse`, `_parseTtml`),
    `rust_backend/crates/mobile/src/native_lyrics.rs` (`parse_ttml`, `parse_lrc`).
  - Goal: untimed TTML shows as plain lyrics instead of being dropped, in both the Dart and
    Rust parsers, and the LRC edge cases parse correctly.

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

## Optional, later

- Performance (measure first): PERF-401, PERF-402, PERF-404, PERF-501, PERF-502, then the
  P3 PERF items. `FIX_PLAN.md` Tier 2b gives their order.
- P3 findings (UX, accessibility and minor KT/RUST/SEC/TEST items): fix one only inside the
  task that already touches its file. Do not open a separate task for them.
