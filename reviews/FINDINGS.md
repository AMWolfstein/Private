# Findings

Format and severity: `reviews/PROTOCOL.md`. IDs are never reused. Move entries between
sections instead of deleting them; resolved entries keep the fixing commit SHA.

## Open

### BUG-001 [P2] [confidence: high] [VALIDATED]
- Location: lib/widgets/local_song_file_actions.dart:191 (`splitLocalCue`)
- Scenario: CUE album split where cover embed throws on one FLAC (native error) → loop aborts; earlier tracks already exported, rest never exported, snackbar says "CUE split failed".
- Root cause: `PlatformBridge.editFileMetadata` call has no per-file try/catch (old `_performCueSplit` caught and logged it).
- Impact: partial split reported as failure; user retries and gets duplicates.
- Fix: wrap the embed in try/catch and continue; ~5 lines + test.
- Evidence: old flow at `26f8e71^` wrapped the same call; current loop 189–201 is unguarded inside the outer catch at 209.

### BUG-002 [P2] [confidence: high] [VALIDATED]
- Location: lib/widgets/local_song_file_actions.dart:100 (`splitLocalCue`)
- Scenario: user reopens the menu during a long split and taps Split again → two FFmpeg jobs, two temp audio copies, duplicate files in the destination.
- Root cause: the `_isSplittingCue` re-entrancy guard from the old flow was dropped when moving to a top-level function.
- Impact: doubled CPU/storage, duplicate output files.
- Fix: module-level in-flight set keyed by the backing CUE path; ~6 lines + test.
- Evidence: old `_performCueSplit` returned early on `_isSplittingCue` (`26f8e71^`); no guard in the new function.

### DATA-001 [P2] [confidence: low] [NEEDS VERIFICATION]
- Location: lib/widgets/local_song_file_actions.dart:18 (`isCueSong`) vs :81 (`deleteLocalSong`)
- Scenario: a row with filePath `*.cue` or format `cue+*` but no `#trackNN` suffix would show CUE actions, and Remove from device would call `deleteFile` on the backing sheet/audio.
- Root cause: `isCueSong` is wider than `isCueVirtualPath`, but only the latter protects delete.
- Impact: would break the "deleting a virtual row preserves the backing CUE/audio" rule; deletes a file other tracks depend on.
- Fix: make delete use the same predicate as `isCueSong`, or narrow `isCueSong` to `isCueVirtualPath`; ~2 lines + test.
- Evidence: Rust scanner (`rust_backend/crates/local/src/backend/library.rs:422-427`) always emits `cue+*` rows with a `#trackNN` path, so no producing path was found; verify edited/imported rows and older DB rows.

### UX-001 [P3] [confidence: high] [VALIDATED]
- Location: `lib/l10n/arb/app_en.arb:3108` (`cueSplitConfirmMessage`), all locales
- Scenario: confirm dialog says "Files will be saved to the same directory", then a SAF folder picker opens.
- Root cause: copy not updated when the split moved to a picked destination.
- Impact: misleading prompt; files land outside the expected folder.
- Fix: reword to "You'll choose a destination folder next" in all arb files.
- Evidence: lib/widgets/local_song_file_actions.dart:146 always calls `PlatformBridge.pickSafTree()` after confirm.

### UX-002 [P3] [confidence: medium] [VALIDATED]
- Location: lib/widgets/local_song_file_actions.dart:186-207 (`splitLocalCue`)
- Scenario: split succeeds into a folder outside the scanned library → success snackbar, but no new songs appear.
- Root cause: no library rescan/add after export. Not a regression: the old SAF-source flow also wrote outside the library without rescanning.
- Impact: user must add the folder and rescan manually.
- Fix: after export, trigger an incremental scan when the tree is a library folder, else say where files went; small.
- Evidence: no scan call in the function; old flow (`26f8e71^`) had none either.

### UI-001 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/local_song_menu.dart:127-128`
- Scenario: virtual CUE row → menu shows Edit Metadata (always rejected at :246 with a snackbar) and Copy file path (copies `album.cue#track03`).
- Root cause: both options sit outside the `if (!cue)` block.
- Impact: dead option; clipboard gets a non-file path.
- Fix: hide Edit for `isCueVirtualPath`; copy `stripCueTrackSuffix(path)` or hide copy; ~3 lines + test update.
- Evidence: gating at :129 covers only gain/removeGain/analysis.

### BUG-003 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/local_song_menu.dart:183-190`
- Scenario: Rescan ReplayGain → Cancel → returns true; `LocalAlbumScreen._showTrackMenu` (`local_album_screen.dart:188`) refetches and rebuilds for nothing.
- Root cause: `runBatchReplayGain` returns void, branch returns true unconditionally.
- Impact: wasted refresh only; callers cannot tell cancel from change.
- Fix: return a bool from `runBatchReplayGain`; small.
- Evidence: branch body at :184-190.


### TEST-001 [P3] [confidence: high] [VALIDATED]
- Location: test/local_song_menu_actions_test.dart:124-152 (popover placement loop)
- Scenario: removing the `MornyeContextMenu` height constraint would still pass: 390x844 viewport with anchors at y=100/650 leaves room for the whole menu.
- Root cause: no short-viewport or mid-screen anchor case.
- Impact: popover scroll/clamp behavior (LTR/RTL, above/below) is unprotected.
- Fix: add a 390x420 case with a mid anchor; assert panel height <= free space and last item reachable only by scrolling.
- Evidence: viewport fixed at :75; only two anchor positions.

### TEST-002 [P3] [confidence: high] [VALIDATED]
- Location: test/local_song_menu_actions_test.dart (whole file)
- Scenario: Share, ReplayGain apply/remove, Edit Metadata, Go to album/artist and the CUE split confirm path have no tap tests.
- Root cause: tests cover only Play next, Add to queue, Copy path, Delete and split Cancel.
- Impact: regressions there (incl. BUG-001/BUG-002/BUG-003) pass CI.
- Fix: add tests alongside the fixes for those findings (mocked channel + share stub).
- Evidence: tapped labels at :161, :189, :198, :256, :268.

### TEST-003 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: test/local_song_menu_actions_test.dart:199, :257, :269
- Scenario: a single zero-delay `runAsync` then `pumpAndSettle` waits for async lookups before tapping dialog buttons; a longer await chain could make the tap miss.
- Root cause: timing-based waits instead of a condition.
- Impact: possible flakiness (fails loudly, not silently).
- Fix: pump until `find.text(...)` matches, with a bounded loop.
- Evidence: test-auditor reading; not reproduced.

### CONC-001 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: lib/services/music_player_service.dart:1832 (`seek`), :1928 (`skipToPrevious` restart), :1760 (`_playInternal`)
- Scenario: app restarts with a restored paused session (`_pendingRestorePosition = X`, `_sourceReady = false`); user seeks to Y (lyrics tap, notification seek) → `seek` hits a deck with no source, UI shows Y; on Play `_playInternal` starts at X.
- Root cause: `seek` and the restart branch ignore the pending-restore/loading state and are not serialized with `_sourceChangeTail`.
- Impact: seek after restore or during a load is lost; scrubber jumps back.
- Fix: when `!_sourceReady`, store the position in `_pendingRestorePosition` and only broadcast; ~6 lines + test.
- Evidence: `_pendingRestorePosition` read only at :1760; seek callers `player_lyrics.dart:901`, notification `MediaAction.seek` (:833). Unverified: whether the deck accepts a seek before a source is set.

### CONC-002 [P2] [confidence: high] [VALIDATED]
- Location: lib/services/music_player_service.dart:2031 (`onSourceDeleted`), :1892 (`_stopSession`)
- Scenario: user stops playback (`_index = -1`, session cleared, queue kept) then deletes a file that was in that queue → else-branch clamps `_index` to 0, broadcasts and persists the session.
- Root cause: clamp does not preserve `-1`; `_stopSession` keeps `_media`/`_queueItems`.
- Impact: an explicitly stopped session comes back on next launch; Play from stopped starts item 0.
- Fix: in the else branch skip index update, broadcast and persist when `_index < 0`; ~3 lines + test.
- Evidence: `_persistSession` (:1135) only clears when `_index < 0`; `wasCurrent` is false for `_index = -1`.

### CONC-003 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: lib/services/music_player_service.dart:667, :611, :770 (`unawaited(play())`, `unawaited(_handlePlayerComplete())`, `unawaited(pause())`)
- Scenario: `UsbOutputUnavailable` or a channel `PlatformException` from `stop`/`resume` inside these futures.
- Root cause: no `catchError` on fire-and-forget calls.
- Impact: uncaught async error; state may stay stale after a completion failure.
- Fix: small helper that logs and broadcasts paused/stopped on error; <10 lines.
- Evidence: reviewer trace; global zone handler not checked.

### CONC-004 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: lib/services/music_player_service.dart:1720-1727 (`play`)
- Scenario: `play()` while an older operation is active joins it even after `pause()`/`stop()` bumped `_playRequestGeneration`; the old op aborts and the newer Play is dropped.
- Root cause: join does not compare generations.
- Impact: final state paused although the last request was Play (headset click, automation, interruption end).
- Fix: join only when the active op's generation equals `_playRequestGeneration`; ~5 lines.
- Evidence: reviewer trace.

### KT-001 [P3] [confidence: high] [VALIDATED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/NativeReplayGainPolicy.kt (+ `android/app/src/test/.../NativeReplayGainPolicyTest.kt`)
- Scenario: download-era album ReplayGain policy ("used by DownloadService"); DownloadService no longer exists.
- Root cause: leftover after download removal.
- Impact: ~140 lines of dead code and a test guarding nothing shipped.
- Fix: delete both files.
- Evidence: only the file and its test reference the symbol (`grep -rln` over android/app/src, lib, rust_backend/crates).

### KT-002 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/HiResPlayback.kt:63, :98, :163; UsbDirectPlayback.kt:131, :178; NativeAudio.kt:7
- Scenario: `libspotiflac_audio` fails to load → `UnsatisfiedLinkError`/`ExceptionInInitializerError` (an `Error`, not `Exception`) escapes the worker-thread catch and crashes the process instead of falling back.
- Root cause: catch blocks catch `Exception` only.
- Impact: crash instead of fallback to normal playback, only if the native library is missing.
- Fix: catch `LinkageError` around `NativeAudio` calls and map to `unsupported`; ~3 lines.
- Evidence: CMake library and Rust share `abiFilters` (`build.gradle.kts:113-116`), so the trigger is unlikely in normal builds.

### DATA-002 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/screens/home_tab_recent.dart:210`, `lib/providers/music_player_provider.dart:162` (`shuffleLibrary`), lib/services/library_database.dart:583 (`getAll`)
- Scenario: tapping a recent album calls unbounded `getAll()`, decodes every library row, then filters by album in Dart; shuffle does the same for all rows.
- Root cause: `getAll()` has no bound and its ORDER BY matches no index (temp B-tree sort of the whole view).
- Impact: jank and memory spikes on large libraries for a single album tap.
- Fix: album tap → `getQueueLocalAlbumTracksByKey` (indexed); shuffle → select only id/file_path; ~20 lines.
- Evidence: the only two non-test `getAll()` callers.

### DATA-003 [P2] [confidence: medium] [VALIDATED]
- Location: lib/services/library_database.dart:643 (`getQueueLocalAlbumTracks`); callers `lib/utils/clickable_metadata.dart:44`, `lib/screens/queue_tab_navigation.dart:72,77`
- Scenario: album navigation queries `LOWER(album_name) = ? AND LOWER(COALESCE(...)) = ?`.
- Root cause: functions on columns defeat `idx_library_album`/`_norm` indexes (full scan); SQLite `LOWER` is ASCII-only while args use Dart `toLowerCase`.
- Impact: album open latency grows with library size; non-ASCII albums ("Été") can open empty or incomplete.
- Fix: use `album_key = ?` (`getQueueLocalAlbumTracksByKey`) or the `*_norm` columns; ~10 lines + test with a non-ASCII album.
- Evidence: query body at :650-652; keyed variant directly below.

### DATA-004 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/services/library_queue_store.dart:278` (singles `HAVING COUNT(*) = 1`), :460 (albums `> minimumTracks`)
- Scenario: a 10-track album with one file on disk shows as a Single in the Library singles filter/count; a single with a bonus file shows as an Album.
- Root cause: classification by stored file count.
- Impact: contradicts the AGENTS.md rule "classify Singles from explicit total-track tags (1), never from the number of files stored"; Library filter (`queue_tab.dart:116,1106`) disagrees with Home/Artist.
- Fix: per `album_key`, single = `MAX(total_tracks) = 1`, rest are Albums; ~30 lines SQL. Needs product confirmation that the rule covers the Library filter.
- Evidence: SQL lines above.

### DATA-101 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/csv_import_service.dart:28`, `lib/services/m3u_playlist_service.dart:42` (import half)
- Scenario: `pickAndParseCsv`, `parsePlaylistInBackground`, `parseM3u` have no non-test callers; the CSV parser is Spotify-oriented (`spotify:track:`, ISRC).
- Root cause: download-era import code left behind; only M3U export is used.
- Impact: ~150 lines of dead code (+ tests, native `parse_playlist` op) with latent parsing bugs.
- Fix: delete the import half and its tests; keep export.
- Evidence: `grep -rn` over lib/ finds callers only inside the two files.

### API-001 [P2] [confidence: high] [VALIDATED]
- Location: lib/services/backup_service.dart:413-422 (`restoreHistory`, non-native branch)
- Scenario: restore from a picked file without a path (`backup_restore_page.dart:94-96` → `BackupService.parse`) runs `clearAll()` then batched upserts; one malformed/old row (NOT NULL column) fails a batch after the clear.
- Root cause: clear and inserts in separate transactions, no validation; atomic `HistoryDatabase.replaceAll` exists but is unused here.
- Impact: existing history wiped, only a prefix restored; settings/profile already replaced.
- Fix: `await HistoryDatabase.instance.replaceAll(bundle.streamHistory())`; ~5 lines + test.
- Evidence: `history_database.dart:813` → `history_maintenance.dart:51` (single transaction).

### API-002 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: lib/services/backup_service.dart:206-294 (`writeBackupArchive`) vs `lib/services/listening_statistics.dart:253`
- Scenario: backup/restore or device migration drops `listening_statistics.db` → all play counts reset.
- Root cause: listening data is not part of the backup format.
- Impact: Artist Popular ranking and listening stats lost on restore without notice.
- Fix: optional `listening` category in v3 metadata (older readers ignore unknown keys), merge per (day, track_key); medium. Product decision: include or document exclusion.
- Evidence: no listening references in backup_service.dart; restore flow `backup_restore_page.dart:120-140`.

### API-003 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/screens/settings/backup_restore_page.dart:120-140`
- Scenario: profile, settings, history, collections restored sequentially; a later failure leaves earlier categories replaced with a generic error.
- Root cause: no validation pass before the first destructive write.
- Impact: partial restore (each category atomic on Android).
- Fix: validate all categories first, or report which were applied.
- Evidence: sequential awaits in one try/catch.

### DATA-203 [P2] [confidence: high] [VALIDATED]
- Location: `lib/services/library_duplicates.dart:11-30` (`readIsrcDuplicateGroups`), `lib/utils/duplicate_cleanup_policy.dart:47` (`buildKeepBestAllDuplicatePlan`)
- Scenario: files sharing a placeholder or reused ISRC (whole album tagged with one ISRC, "000000000000") form one group; Keep best (all) keeps `entries.first` and deletes every other physical file. Ranking `bit_depth, sample_rate, bitrate` lets a 128 kbps/48 kHz MP3 beat a 320 kbps/44.1 kHz MP3.
- Root cause: identity = non-empty ISRC only; no ISRC format, title or duration check; lossy ranking ignores bitrate first.
- Impact: destructive bulk action can delete distinct tracks or the better copy.
- Fix: require `^[A-Z]{2}[A-Z0-9]{3}\d{7}$` and duration within ~2 s; rank lossy by bitrate; ~15 lines + tests.
- Evidence: SQL grouping/order at :17-29; policy relies on that order (:42-46).

### SEC-001 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/utils/file_access.dart:354-386` (`deleteFile`)
- Scenario: SAF grant revoked/provider unavailable → `safDelete` false → `!safExists(path)` is true because `DocumentFile.exists()` returns false on permission errors → reported as deleted, deletion event published, callers drop the library row; file remains on storage. Local branch: `File.exists()` false on parent EACCES.
- Root cause: binary existence check after a failed delete; tri-state `fileExistenceByPath` exists but is unused here.
- Impact: failed delete reported as success; row hidden for a file that still exists.
- Fix: after a failed delete confirm absence with the tri-state helper (`== false` only); ~15 lines + test.
- Evidence: callers removing rows on `true`: `local_song_file_actions.dart:86`, `local_track_batch_actions.dart:55`, `duplicate_cleanup_policy.dart:22`, `local_album_screen.dart:146`; native `safExists` at `MainActivity.kt:972`.

### SEC-002 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/utils/local_library_scan_prefs.dart:7-16` (`readLocalLibraryLastScannedAt`)
- Scenario: an older build stored epoch millis (int) under `local_library_last_scanned_at` → `prefs.getString` casts to `String?` and throws `TypeError` before the `getInt` fallback.
- Root cause: typed getter before the legacy-type fallback.
- Impact: last-scan read throws for users upgrading from the int format (settings/scan startup).
- Fix: `final raw = prefs.get(key)` and switch on String/int; ~5 lines + test.
- Evidence: file body; the fallback comment states the int format existed.

### DATA-201 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/services/library_search.dart:10` (`[\p{L}\p{N}]+`), `lib/services/sqlite_helpers.dart:102` (`normalizeLookupText`)
- Scenario: Arabic with diacritics, Devanagari, Thai queries split into fragments at combining marks (`\p{M}`) and match unrelated rows; NFD-stored tags (`e`+U+0301) never match NFC queries.
- Root cause: tokenizer excludes marks; no Unicode normalization on query or stored `search_text`.
- Impact: wrong or missing search results for non-Latin scripts (app ships ar/hi locales).
- Fix: include `\p{M}`; NFC-normalize query and stored text (re-normalize migration); ~10 lines + migration.
- Evidence: regex at :10; `search_text` built by `LibraryRowMapper.queue`.

### DATA-202 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/library_genres.dart:7-19`, :31-47 (`page`)
- Scenario: `LOWER(genre)` folds ASCII only → "Électro"/"électro" are two genres; each page re-runs the recursive CTE over the whole visible library.
- Root cause: genre key computed in SQL at query time.
- Impact: duplicate genre rows for non-ASCII tags; O(library) per page on large libraries.
- Fix: normalized genre key at scan time or a `library_genres` side table; ~40 lines.
- Evidence: CTE at :11-18; `local_genres_screen.dart` pages by 40.

### SEC-003 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/utils/file_access.dart:272` (`_cueTrackSuffix`)
- Scenario: a real file named `Song #track1` matches `#track\d+$` → cannot be deleted/opened; existence checks test the stripped path and report it missing.
- Root cause: suffix regex not anchored to a `.cue` base.
- Impact: rare; such files become undeletable or are cleaned up as missing.
- Fix: require `\.cue#track\d+$` (case-insensitive); ~3 lines + test.
- Evidence: helpers applied to every path in file_access.dart.

### SEC-004 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/utils/saf_display_path.dart:127-139` (`_safDocumentId`)
- Scenario: `Uri.pathSegments` already decodes; `Uri.decodeComponent` decodes again → names with a literal `%XX` display wrongly.
- Root cause: double decoding.
- Impact: display-only.
- Fix: return the segment directly; 1 line.
- Evidence: contradicts `resolveSafDocumentLocation` doc comment.

### DATA-204 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/utils/path_match_keys.dart:99-148` (`addNormalized`), :180 (`_androidDocumentMatchKey`)
- Scenario: (A) lowercased keys make `A.flac`/`a.flac` in one folder collide → deleting one drops the other's row until rescan and hides it from duplicates. (B) virtual SAF CUE paths lose `#trackNN` in keys → all tracks of a CUE share a key (latent: current callers guard virtual paths).
- Root cause: case folding on case-sensitive storage; fragment dropped for SAF keys.
- Impact: rare row loss; trap for future callers.
- Fix: keep `#trackNN` in SAF/URI keys; skip lowercase key for non-SAF paths; ~10 lines.
- Evidence: :100-101, :125-131.

## Resolved

_None yet._

## Rejected

_False positives and intentional behavior, with one-line reason._

- R-001 (`/code-review` #8, share origin from screen context): Android-only app; `sharePositionOrigin` only affects iPad/macOS.
- R-002 (`/code-review` #9, split logic in a widget file): the old screen implementation was deleted, so there is no duplicate; no demonstrated impact.
- R-004 (test-auditor TEST-004, unawaited popover action): no pending future in that test; an open overlay at test end leaks nothing.
- R-005 (test-auditor TEST-005, plain `.cue` delete test): duplicate of DATA-001; its regression test belongs to that fix.
- R-003 (`/code-review` #10, graphify commit title `81577e5` missing "code"): historical pushed commit; fixing needs history rewrite. Future commits follow the AGENTS.md wording.
