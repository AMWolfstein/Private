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
- Impact: ~150 lines of dead code (+ tests) with latent parsing bugs; also Rust `parse_playlist` (`native_playlists.rs:17`, `data_jobs.rs:63`) and `hash_file` (`data_jobs.rs:62`) have only test callers.
- Fix: delete the import half, `csv_import_service.dart`, the Rust ops and their tests; keep `build_m3u` and export.
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

### DATA-301 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/local_song_menu.dart:256-282` (`editLocalSongMetadata`), `lib/controllers/metadata_editor_controller.dart:54`
- Scenario: `PlatformBridge.readFileMetadata` returns `{error: ...}` (no throw) on a transient SAF/IO failure → form prefilled from the DB, `comment`/`album_type`/`upc`/`lyrics` become `''` → user edits only the title → save sends empty values, which clear those tags.
- Root cause: prefill ignores `tags['error']`; fields the DB does not hold are submitted as clears.
- Impact: silent loss of embedded lyrics, comment, release type and UPC.
- Fix: abort with a snackbar when `tags['error'] != null`, or send only dirty fields; ~5 lines + test.
- Evidence: only thrown errors are caught (:258-261); `val()` falls back to DB or `''`.

### DATA-302 [P2] [confidence: high] [VALIDATED]
- Location: `lib/services/ffmpeg_metadata.dart:180-195` (`embedMetadataToMp3`)
- Scenario: tag-only edit on an MP3 whose stream copy reports "Invalid audio stream"/"incorrect codec parameters" (native MP3 editor already failed) → audio silently re-encoded with `libmp3lame -b:a 192k` and the original replaced.
- Root cause: conversion-era retry kept in the tag-write path.
- Impact: lossy, quality-reducing rewrite of the user's file (320k/VBR downgraded) without consent.
- Fix: fail with `MetadataSaveFailure.ffmpeg` instead of re-encoding; ~10 lines removed + test.
- Evidence: code above; reached via `save()` → `_embed` when tags.rs returns `method: "ffmpeg"`.

### DATA-306 [P2] [confidence: medium] [VALIDATED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafIo.kt:347`, :414 (`writeUriFromPath`); Dart callers `MetadataPersistenceService.writeBack`, `ReplayGainService._updateFile`
- Scenario: SAF write-back opens the original with mode `"wt"` (truncates immediately) then streams the temp copy; IO error, full storage or process death mid-copy leaves the only copy truncated; temp is deleted in `finally`.
- Root cause: non-atomic write-back and unconditional temp deletion.
- Impact: rare but total loss of a music file during SAF tag edit or ReplayGain.
- Fix: check free space/size first; keep the temp on failure and surface a retry; ~15 lines Kotlin.
- Evidence: `openOutputStream(uri, "wt")` at :347 and :414.

### DATA-303 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/services/ffmpeg_metadata.dart:375-379` (`embedMetadataToM4a`)
- Scenario: M4A edit on the FFmpeg fallback: explicit/`album_type`/`upc`/compilation are written only by `writeM4AReleaseIdentityTags`, whose bool result is ignored; `writeM4AFreeformTags` swallows errors → "saved" while the file is unchanged; UI reverts after re-read. FFmpeg mov muxer also drops unknown freeform atoms (ISRC, ReplayGain) without `-movflags use_metadata_tags`.
- Root cause: post-FFmpeg native write failures not propagated; freeform atoms not preserved.
- Impact: false success; untouched freeform tags lost on the fallback path.
- Fix: return failure when the identity write returns false; add `-movflags use_metadata_tags`; ~4 lines.
- Evidence: unused return value at :378.

### BUG-101 [P2] [confidence: high] [VALIDATED]
- Location: `lib/utils/lyrics_parser.dart:213-220` (`parse`), :758-765 (`_parseTtml`)
- Scenario: TTML with `<p>` but no usable `begin`, or no `<p>` → `_parseTtml` returns an untimed result (or null); `parse()` requires `lines.isNotEmpty`, falls through to `_parseLrcOrPlain(text)` on raw XML → plain text view shows XML markup.
- Root cause: untimed TTML result discarded.
- Impact: unsynced TTML lyrics (embedded or sidecar) render as raw XML.
- Fix: return `_withCredits(text, ttml)` when `ttml != null` and `plainText` is non-empty; ~3 lines + test.
- Evidence: guard at :215; untimed return at :758.

### DATA-304 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/services/replaygain_service.dart:158-170`, `lib/services/ffmpeg_replaygain.dart:188`
- Scenario: native ReplayGain writer fails → FFmpeg `-map 0 -c copy` fallback promotes over the original, then verification runs; for M4A the muxer dropped the atoms → reports failure, but the local file is already rewritten minus freeform tags.
- Root cause: verify after publish.
- Impact: failed apply leaves a modified file with lost custom tags.
- Fix: skip the FFmpeg fallback for .m4a/.mp4/.m4b (like Opus) or verify the temp before promoting; ~3 lines.
- Evidence: reviewer trace.

### DATA-305 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/services/ffmpeg_cue.dart:72-77` (`splitCueToTracks`)
- Scenario: one track fails → partial output not deleted, skipped with `continue`; shorter list returned with no signal; caller reports "n tracks".
- Root cause: no cleanup or partial-failure signal.
- Impact: silently incomplete split; truncated file left in staging.
- Fix: `FFmpegOutput.cleanup(outputPath)` on failure and return the failed count; ~4 lines. Pair with BUG-001/002.
- Evidence: caller `local_song_file_actions.dart:171` iterates `paths` only.

### DATA-307 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/widgets/local_song_menu.dart:297-312`
- Scenario: each metadata edit writes a new `library_covers/edited_<ts>.jpg` and never deletes the previous one.
- Impact: one orphaned image per edit (may be swept by cover snapshot pruning; not verified).
- Fix: delete the old cover if it is under `library_covers` and differs.

### BUG-102 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/utils/lyrics_parser.dart:280-288` (`_withCredits`)
- Scenario: LRC with a trailing "Written by:" credit and multi-timestamp chorus lines → plainText rebuilt from expanded timed lines → chorus duplicated.
- Fix: remove the trailer from the existing plainText instead of rebuilding; ~3 lines.

### BUG-103 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/utils/lyrics_parser.dart:415-436`
- Scenario: enhanced LRC `[00:10][01:30]<00:10>a<00:11>b` → repeated line shares word times of the first occurrence; word highlight wrong on repeats.
- Fix: shift word times per extra timestamp; ~10 lines.

### BUG-104 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/services/id3v23_lyrics.dart:137-161` (`_removeFrames`)
- Scenario: existing ID3v2.3 tag has a zero-size/invalid/overrunning frame → `break` drops every later frame (e.g. APIC) when lyrics are written.
- Impact: cover/tag loss with non-conforming taggers (low exposure: FFmpeg rewrites the tag just before).
- Fix: preserve the remaining payload verbatim or return null to leave the file unchanged; ~5 lines.

### BUG-105 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/utils/lyrics_metadata_helper.dart:56`, :71-79
- Scenario: lone `\r` separators are not split; header-only LRC counted as usable. Pattern also strips `[Chorus: X]` headers.
- Fix: split on `\r\n|\r|\n`; ~3 lines. Note: these helpers currently have no production callers (see DEAD-002), so fix only if kept.

### DATA-401 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/widgets/audio_analysis_widget.dart:913`, :941-963; `lib/services/audio_analysis_cache.dart`
- Scenario: cache key = path hash, validated by `fileSize` only (SAF size 0 skips check) → same-size replacement serves stale analysis.
- Fix: store and compare modified time; ~8 lines.

### DATA-402 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/library_cover_snapshot.dart:34-45`, `rust_backend/crates/mobile/src/native_cache/unix.rs:353-359`, `lib/services/library_schema.dart:15`
- Scenario: schema version 17 is hard-coded in three places; bumping `LibrarySchema.version` breaks cover pruning (orphan covers accumulate).
- Fix: use `LibrarySchema.version` and pass it to Rust, or a test asserting all three agree; ~5 lines.

### DEAD-001 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/ffmpeg_decryption.dart` (169), `FFmpegService.decryptWithDescriptor` (`ffmpeg_service.dart:46-57`), `DownloadDecryptionDescriptor` (`ffmpeg_models.dart`), `FFmpegExecution.command`, `FFmpegOutput.plan`, `FFmpegMetadata.embedMetadata`/`FFmpegService.embedMetadata`, `FFmpegMetadata.embedChunkTagsNative`, `returnTempPath`/`onTempReady` params of ReplayGain writers
- Scenario: download-era decryption and conversion-era helpers with no production callers.
- Impact: ~250 lines + `test/ffmpeg_decryption_output_test.dart` (215) and part of `test/maintainability_contracts_test.dart`.
- Fix: delete; trim tests.
- Evidence: `grep -rln` over lib/ test/ finds only definitions, self-references and tests.

### DEAD-002 [P3] [confidence: high] [VALIDATED]
- Location: `lib/utils/ffmpeg_reenrich.dart` (145), `lib/utils/re_enrich_result.dart` (51), `lib/utils/re_enrich_release_policy.dart` (8), `lib/utils/lyrics_metadata_helper.dart` (209: `cleanLyricsForDisplay`, `hasUsableLyricsContent`, `hasEmbeddedLyricsMetadata`, `isInstrumentalLyricsMarker`, `mergePlatformMetadataForTagEmbed`, sidecar writers), `PlatformBridge.writeSafSidecarLrc` (`platform_bridge.dart:830`)
- Scenario: online re-enrich/lyrics flow removed; nothing calls `applyFfmpegReEnrichResult`; the helpers are reachable only from it or tests.
- Impact: ~410 lines + tests (`re_enrich_result_test`, `re_enrich_release_policy_test`, helper tests), likely orphan `trackReEnrich*` l10n keys and native `write_external_lrc`.
- Fix: delete with tests, plus the `writeSafSidecarLrc` Kotlin handler (`MainActivity.kt:1447`); keep `writeTempToSaf` (live callers in replaygain/metadata persistence); check l10n keys in the dead-code sweep.
- Evidence: `grep -rln` per symbol over lib/.

### DEAD-003 [P3] [confidence: high] [VALIDATED]
- Location: `lib/utils/cover_art_utils.dart` (`highResCoverUrl`), `lib/widgets/cached_cover_image.dart:136,149` (`urlTransform`), callers `library_tracks_folder_screen.dart:530,566`
- Scenario: Spotify/Deezer CDN URL rewrite passed as `urlTransform`, which `LocalCoverImage` never reads.
- Impact: dead remote-artwork code (~30 lines + test).
- Fix: delete the file/test, the parameter and its two uses.

### DEAD-004 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/downloaded_embedded_cover_resolver.dart:210` (`scheduleRefreshForPath`), :232 (`invalidate`), `_pendingRefresh` branches
- Scenario: no non-test callers; staleness is handled by the mod-time poll. Class name/comments still say "downloaded"/"online fallback".
- Impact: ~50 lines dead API; misleading naming.
- Fix: remove dead methods; fix comments; rename if cheap.

### DATA-501 [P1] [confidence: medium] [VALIDATED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:741-757 (`querySafChildrenOrThrow`), consumed at :930, :1355; Dart `library_database.dart:373`, `library_cleanup.dart:18-27`
- Scenario: a cloud/network DocumentsProvider returns an empty children cursor with `DocumentsContract.EXTRA_ERROR` → treated as an empty folder, `traversalErrors` stays 0 → full scan: `error_count` 0 → `preserveMissing = false` → `deleteReplacedLibraryScanRows` deletes the subtree (or whole source if the root listing is empty); incremental: missing URIs go to `removedUris` → `deleteByPaths`.
- Root cause: only `EXTRA_LOADING` is checked; a 0-row result with no errors is trusted as authoritative.
- Impact: library rows for a folder or the whole source disappear after a transient provider failure (files untouched; restored by a later successful scan).
- Fix: throw `IOException` when `cursor.extras.getString(EXTRA_ERROR) != null` (~3 lines); optionally refuse a full replace yielding 0 rows when the source had rows.
- Evidence: check at :756 only reads `EXTRA_LOADING`; trigger depends on provider behavior (documented DocumentsProvider error contract).

### KT-201 [P2] [confidence: high] [VALIDATED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1465-1539 (changed-CUE loop in `scanSafTreeIncremental`), :1427, :1660
- Scenario: a CUE whose mtime changed fails to re-scan (temp copy null, audio missing, parse throws) → catch only does `errors++`; old `cue#trackN` paths never added to `currentUris` → returned as removed → Dart deletes the CUE's tracks. `errors` not returned.
- Root cause: failed re-index treated like deletion.
- Impact: transient read error deletes all tracks of a CUE album from the library.
- Fix: on failure add the existing virtual paths to `currentUris`; return the error count; ~5 lines.
- Evidence: catch block at :1534-1536; `currentUris` extended only at :1401 and :1530.

### KT-202 [P2] [confidence: high] [VALIDATED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1604-1613, :1427-1430 (incremental scan)
- Scenario: a `.cue` is added beside an already-indexed, unchanged audio file → CUE tracks indexed, standalone row kept → duplicates until a full rescan.
- Root cause: `cueReferencedAudioUris` only skips changed audio; never removes existing standalone rows.
- Fix: add `existingFiles.keys ∩ cueReferencedAudioUris` to `finalRemovedUris`; ~3 lines.
- Evidence: full scan avoids it via full swap (:1162).

### KT-203 [P2] [confidence: medium] [VALIDATED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1003-1012, :1047-1160 (`scanSafTree` resume)
- Scenario: full scan interrupted and resumed; checkpoint rebuilt from surviving NDJSON rows; files deleted/renamed in between stay in the output and are imported.
- Root cause: resumed output not pruned against the current listing.
- Impact: ghost tracks for deleted files.
- Fix: filter stale lines after traversal or discard the resume when the checkpoint has URIs not in the listing; ~15 lines.
- Evidence: reconcile step never consults the current listing.

### KT-102 [P2] [confidence: high] [VALIDATED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:191-196` (`safTreeLauncher` callback), :219
- Scenario: picker returns OK but `data.flags` has no grant bits (`takeFlags == 0`) or `takePersistableUriPermission` throws (e.g. grant cap reached, see KT-105) → only logged; payload delivered as success.
- Root cause: persist failure not propagated; no READ|WRITE fallback.
- Impact: Dart stores a tree whose grant is lost after restart; the library silently loses access.
- Fix: fall back to READ|WRITE flags when 0; on failure return an error; ~6 lines.
- Evidence: lines 191-196; unconditional `deliver(payload)` at :219.

### UX-003 [P2] [confidence: high] [VALIDATED]
- Location: `lib/screens/main_shell.dart:151-200` (`_repairSafAccessIfNeeded` dialog), `lib/providers/settings_provider.dart:173`, :279 (`setDownloadDirectory`), `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:1042-1061` (`isSafTreeAccessible`)
- Scenario: a user upgrading or importing settings with `storageMode == 'saf'` and a legacy `downloadTreeUri` gets a non-dismissible "Download folder access lost" dialog on start/resume whenever the tree is not writable or the provider is slow (`isSafTreeAccessible` returns false on any exception or missing write grant); its action resets the legacy fields.
- Root cause: download/output-folder repair flow and settings survived the offline migration; the probe is binary.
- Impact: obsolete download-era modal in an offline player (AGENTS.md: output-folder feature removed); can appear repeatedly.
- Fix: remove the repair dialog and the legacy `downloadTreeUri`/`downloadDirectory`/`storageMode` handling (ignore them on import); ~60 lines. Merges reviewer KT-101.
- Evidence: dialog strings `downloadFolderAccessLostTitle`; trigger condition at `main_shell.dart:157-160`.

### KT-103 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:756-778` (`onDestroy`), :857-866, :74
- Scenario: engine outlives the Activity; after Activity re-creation during a background scan, a new progress StreamHandler is installed without a Dart re-subscribe → progress stalls; `scope` never cancelled and backend channel handler not cleared → short Activity leak.
- Fix: cancel `scope` in `onDestroy`; confirm `ProgressStreamPoller` re-subscribes.

### KT-104 [P3] [confidence: high] [VALIDATED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:1459`, :1478
- Scenario: error JSON hand-built with only quote replacement → backslash/newline in a message yields invalid JSON → Dart `jsonDecode` throws.
- Fix: use `errorJson(e.message ?: "unknown")`; 2 lines.

### KT-105 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:193`
- Scenario: `releasePersistableUriPermission` is never called; replaced/removed folders keep grants until the platform cap (128/512) → later picks fail (silently, KT-102).
- Fix: release grants when a library source is removed; ~15 lines.

### KT-204 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1396-1398, :1410
- Scenario: providers without `COLUMN_LAST_MODIFIED` give 0 → edits never detected incrementally; replacing audio under an unchanged CUE keeps stale CUE data.
- Fix: treat 0 as changed; ~2 lines.

### KT-205 [P3] [confidence: high] [VALIDATED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1094-1096, :1558-1575
- Scenario: resumed scan skips indexed CUEs without `scanned++` (progress under-reports); unchanged-CUE copy failure only logged → audio indexed standalone, duplicating CUE rows.
- Fix: count/progress before `continue`; treat unresolved unchanged CUE as an error.

### SEC-101 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `android/app/src/main/AndroidManifest.xml:42-45`, `android/app/src/main/kotlin/com/zarz/spotiflac/PlayerWidgetProvider.kt:274-278` (`PlayerWidgetBridge.handleIntent`)
- Scenario: any app can start the exported launcher Activity with `player_widget_command=<any>`; forwarded to Dart unvalidated (receiver path allow-lists toggle/next/previous).
- Impact: low today (MediaSession allows the same); risk for future handlers.
- Fix: same allow-list in `handleIntent`; 3 lines.

### DEAD-201 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/platform_bridge.dart:268` (`prepareRuntimeState`), :277 (`setDownloadDirectory`), :305 (`buildFilename`), :316 (`sanitizeFilename`); `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:917`, :925; `CoreBackend.kt:13-14`
- Scenario: no `PlatformBridge.` callers; native branches for buildFilename/sanitizeFilename unreachable (not in `nativeBackendMethods`), others have no handler.
- Fix: delete wrappers, branches and interface members (~40 lines). (`SettingsNotifier.setDownloadDirectory` is a different symbol — see UX-003.)

### DEAD-202 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/platform_bridge.dart:415, 429, 494, 510, 528, 563, 688, 776, 792, 808` (`resolveSafFile`, `inspectSafFiles`, three `create*SafFile*` variants, `shareMultipleContentUris`, `checkHiResAuthenticity`, `ensureAC4Config`, `writeAC4Metadata`, `rewriteSplitArtistTags`) and their MainActivity handlers
- Scenario: download/conversion-era wrappers with zero callers; native handlers unreachable.
- Fix: remove wrappers, handlers and CoreBackend members in one batch; keep `writeM4AFreeformTags` and `safCreateFromPath`.

### DEAD-203 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/platform_bridge.dart:574, 591, 607, 658` (`getLyricsLRC`, `getLyricsLRCWithSource`, `embedLyricsToFile`, `fetchAndSaveLyrics`); `android/app/src/rust/kotlin/com/zarz/spotiflac/SelectedCoreBackend.kt:34-54`, :390-406
- Scenario: Embed lyrics and fetch-and-save were removed (AGENTS.md) but remain wired end to end; no `lib/` callers.
- Fix: delete wrappers, Kotlin branches and plumbing; update tests.

### DEAD-206 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/platform_bridge.dart:223, 333-339`; `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:965-970`; `android/app/src/main/kotlin/com/zarz/spotiflac/SetupFolderPickerStore.kt`
- Scenario: setup folder step removed; native still persists `for_setup` picks and emits `setupFolderSelectionChanged`; nothing reads it.
- Fix: remove Dart members, handlers, `for_setup` branch and the store (~60 lines).

### DEAD-207 [P3] [confidence: high] [VALIDATED]
- Location: `lib/services/platform_bridge.dart:1167-1230` (iOS bookmark/directory methods), `lib/widgets/ios_library_folder_sheet.dart`, `lib/providers/local_library_provider.dart:636-644, 917, 1586-1608`, `lib/screens/settings/library_settings_page.dart:150`
- Scenario: Android-only project (no `ios/`); methods have no handler.
- Fix: remove iOS methods, sheet and branches (~150 lines); include `migrateIosContainerPaths`, `lib/utils/ios_container_paths.dart` in the dead-code sweep.

### DEAD-208 [P3] [confidence: high] [VALIDATED]
- Location: `android/app/proguard-rules.pro:48-53`
- Scenario: keep rules for nonexistent `DownloadService` and `DownloadQueueWidgetProvider`.
- Fix: delete both blocks; update the stale comment in `NativeReplayGainPolicy.kt:4` (see KT-001).

### RUST-101 [P2] [confidence: high] [VALIDATED]
- Location: `rust_backend/crates/core/src/tags/id3.rs:404-407` (`decode`), :489 (`v1`), :296 (`picture_frame`); `rust_backend/crates/core/src/text.rs:3` (`utf8`)
- Scenario: ID3v1/v2.2/v2.3 text in ISO-8859-1 (encoding 0, e.g. "Beyoncé" with 0xE9) → decoded as lossy UTF-8 → "Beyonc\u{FFFD}"; UTF-16 surrogate pairs (emoji) become two U+FFFD.
- Root cause: encoding 0 routed through UTF-8 (Go-parity decoder); no `decode_utf16`.
- Impact: corrupted titles/artists/albums for older/Windows-tagged MP3s; saving writes the replacement characters back permanently.
- Fix: Latin-1 for encoding 0 when not valid UTF-8; `char::decode_utf16`; ~15 lines; update Go-parity tests.
- Evidence: `decode` and `utf8` bodies; reached from `read_tags` "mp3" branch (tags.rs:208).

### RUST-102 [P2] [confidence: medium] [VALIDATED]
- Location: `rust_backend/crates/core/src/tags/write/id3.rs:278-300` (`read_frames`), :71-80 (`edit_header`)
- Scenario: (1) a zero-length or bad-size frame → `break`, Ok with frames so far → rewritten tag drops every later frame (APIC, TXXX, POPM); reader errors on the same input. (2) compressed/encrypted v2.3/v2.4 frames and unknown v2.2 IDs dropped. (3) every save replaces all COMM and USLT frames (editor always sends comment/lyrics), including iTunSMPB/iTunNORM and other-language lyrics. (4) zero-length tag header returns Err, pushing Dart to the FFmpeg fallback (DATA-302).
- Root cause: lossy rewrite that fails silently on frames it cannot re-emit.
- Impact: loss of untouched artwork/metadata and gapless info in MP3s with slightly malformed tags.
- Fix: copy remaining raw bytes or return Err instead of truncating; drop only COMM with empty descriptor and same language; pass through encrypted frames raw; ~30 lines + tests. Related: BUG-104 (Dart USLT writer has the same `break` pattern).
- Evidence: `break` at :298-300.

### RUST-201 [P2] [confidence: high] [VALIDATED]
- Location: `rust_backend/crates/core/src/media/hires/mod.rs:567-568` (`Source::analyze_window`, FLAC)
- Scenario: FLAC whose STREAMINFO declares more channels than frames carry → `block.channel(index)` slices out of range in claxon → panic inside an FFI call (Audio Quality Analysis).
- Root cause: claxon does not check frame vs STREAMINFO channels; guard exists in `replacement.rs:93-95` but not here.
- Impact: panic on untrusted file data (surfaced as a generic error if uniffi catches it; unverified).
- Fix: return Err when `block.channels()` differs; ~3 lines + test.

### RUST-202 [P2] [confidence: high] [VALIDATED]
- Location: `rust_backend/crates/core/src/cue.rs:117-122` (`parse`, FILE), `CueTrack` :25-35; consumers `rust_backend/crates/local/src/backend/library.rs:232,284`, `scan.rs:446`
- Scenario: multi-FILE cue (one file per track: `FILE "01.flac"`/TRACK 01/INDEX 01 00:00:00, `FILE "02.flac"`...) → `sheet.file_name` overwritten per FILE; all tracks attributed to the last file with their own start times.
- Root cause: no per-track file field.
- Impact: wrong/zero durations and playback offsets; Split into Tracks cuts the wrong audio; no error shown.
- Fix: record file per track and resolve per track, or reject sheets with a second distinct FILE (~5 lines) + test.
- Evidence: assignment at :119; no multi-FILE test.

### RUST-203 [P2] [confidence: high] [VALIDATED]
- Location: `rust_backend/crates/core/src/cue.rs:291-300` (`timestamp`), `rust_backend/crates/local/src/backend/library.rs:431-433` (`cue_library_rows`)
- Scenario: malformed INDEX ("xx:yy:zz") becomes 0.0; ff >= 75, negative values and out-of-order starts accepted → negative durations emitted to the library.
- Root cause: no validation; `unwrap_or(0)`.
- Impact: overlapping/zero-start tracks and negative durations without a parse error.
- Fix: `timestamp` returns Option, rejects ff >= 75 / ss >= 60 / negatives; clamp durations with `.max(0)`; ~10 lines + tests.

### RUST-204 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `rust_backend/crates/core/src/cover/library.rs:53-60`, :71 (`library_thumbnail`)
- Scenario: cache mutex held across `resize` of untrusted embedded art; a decoder panic poisons it → every later call fails "thumbnail cache unavailable" until restart.
- Impact: all library covers disappear after one bad image.
- Fix: recover with `into_inner()` on `Poisoned`, or resize outside the lock; ~3 lines.

### RUST-001 [P3] [confidence: high] [VALIDATED]
- Location: `rust_backend/crates/mobile/src/usb_audio/transport.rs:235, 268, 274, 278, 286, 294` (`completed`, `Slot::submit`, `success`, `actual`)
- Scenario: `submit` passes `self as *mut Slot` as libusb `user_data`, then writes `self.pending` through `&mut self`; later reborrows invalidate the raw pointer's provenance, so the callback's write is UB under Stacked/Tree Borrows. `iso_packet_desc.as_ptr()` on `[T; 0]` has zero-byte provenance.
- Root cause: shared completion flag stored inside a `&mut`-used struct.
- Impact: latent UB only; Opus review: no realistic miscompile today (pointer escapes to libusb, flag reloaded each loop).
- Fix: heap `AtomicBool` passed as `user_data` with `pending()` accessor; `addr_of_mut!(...).cast()` for iso descriptors; ~15 lines.
- Evidence: Opus escalation verdict (Sonnet → Opus).

### RUST-002 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `rust_backend/crates/mobile/src/usb_audio/transport.rs:626-631` (`run`), :433-436 (`configure`), `descriptors.rs:247-264`
- Scenario: integer-nominal rates (48 kHz @125 µs = 6 frames) with feedback slightly above nominal occasionally need 7 frames; if `wMaxPacketSize` is exactly 6×frame, `run` fails "USB feedback exceeded endpoint capacity".
- Impact: USB bit-perfect playback aborts mid-track on DACs without packet headroom.
- Fix: clamp to endpoint capacity and carry the remainder; ~5 lines.

### RUST-103 [P3] [confidence: high] [VALIDATED]
- Location: `rust_backend/crates/core/src/tags/id3.rs:302` (`picture_frame`), `rust_backend/crates/core/src/tags/write/id3.rs:182-186` (`cover`)
- Scenario: UTF-16 APIC description terminator found with unaligned `windows(2)` → image offset wrong by one → corrupt cover (re-embedded for RIFF/AIFF).
- Fix: aligned search like `separator()`; ~5 lines.

### RUST-104 [P3] [confidence: high] [VALIDATED]
- Location: `rust_backend/crates/core/src/tags/comments.rs:18-22`, `containers.rs:291`, `write/ogg.rs:109-117`, `write.rs:737`
- Scenario: writer accepts Ogg covers up to 16 MB (≈21 MB base64) but reader caps 10 MB → covers above ~7.4 MB written then read back as missing; reader processes only the first 100 Ogg comments (ReplayGain/R128/picture beyond that ignored).
- Fix: align limits; bound by bytes, not count.

### RUST-105 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `rust_backend/crates/core/src/tags/write/riff.rs:46, 94-96, 152`, `write/ape.rs:19-40`, `write/mp4.rs:138`, `tags/mp4.rs:45`
- Scenario: WAV/AIFF ID3 chunk rebuilt only from parsed fields (TXXX/unknown/extra APIC lost; odd final chunk without pad fails save); APE edit deletes trailing ID3v1; MP4 `number as u16` wraps; `covr` type 13 for non-JPEG; legacy rtng 4 not read as explicit.
- Fix: individually small; batch with RUST-102.

### RUST-106 [P3] [confidence: medium] [VALIDATED]
- Location: `rust_backend/crates/core/src/tags/write.rs:403-407`, :737-776 (`picture`)
- Scenario: replacement cover >16 MB that cannot be shrunk → `picture()` Ok(None) after old pictures were removed → save succeeds, artwork gone; oversize decode uses image crate default 512 MB limit.
- Fix: return Err or keep old pictures; set `image::Limits`.

### RUST-205 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `rust_backend/crates/core/src/media/hires/mod.rs:525-532`, `WavSource::open` (:690)
- Scenario: crafted WAV with up to 65535 channels allocates per-channel STFT buffers up front (~100 MB–2 GB) → OOM risk.
- Fix: reject WAV channels > 32; 1 line.

## Resolved

_None yet._

## Rejected

_False positives and intentional behavior, with one-line reason._

- R-001 (`/code-review` #8, share origin from screen context): Android-only app; `sharePositionOrigin` only affects iPad/macOS.
- R-002 (`/code-review` #9, split logic in a widget file): the old screen implementation was deleted, so there is no duplicate; no demonstrated impact.
- R-004 (test-auditor TEST-004, unawaited popover action): no pending future in that test; an open overlay at test end leaks nothing.
- R-005 (test-auditor TEST-005, plain `.cue` delete test): duplicate of DATA-001; its regression test belongs to that fix.
- R-006 (metadata DEAD-005, `cover_cache_manager.dart`): live upgrade-cleanup affordance used by `cache_management_page.dart`; UX note only.
- R-007 (kotlin KT-101, legacy SAF repair dialog probe): merged into UX-003.
- R-008 (kotlin DEAD-204/DEAD-205): duplicates of DEAD-002 and DATA-101; native parts added there.
- R-003 (`/code-review` #10, graphify commit title `81577e5` missing "code"): historical pushed commit; fixing needs history rewrite. Future commits follow the AGENTS.md wording.
