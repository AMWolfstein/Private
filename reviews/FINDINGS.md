## Open

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

### BUG-105 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/utils/lyrics_metadata_helper.dart:56`, :71-79
- Scenario: lone `\r` separators are not split; header-only LRC counted as usable. Pattern also strips `[Chorus: X]` headers.
- Fix: split on `\r\n|\r|\n`; ~3 lines. Note: these helpers currently have no production callers (see DEAD-002), so fix only if kept.

### RUST-205 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `rust_backend/crates/core/src/media/hires/mod.rs:525-532`, `WavSource::open` (:690)
- Scenario: crafted WAV with up to 65535 channels allocates per-channel STFT buffers up front (~100 MB–2 GB) → OOM risk.
- Fix: reject WAV channels > 32; 1 line.

### BUG-203 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/providers/local_library_provider.dart:1666-1678` (`removePhysicalFiles`/`removeItems`), `lib/services/deleted_library_files.dart:7-16`, `lib/providers/library_collections_provider.dart`
- Scenario: deleting a song (menu, album, duplicates, batch) clears only the library index; Loved/playlist entries keyed `local:<id>`/`isrc:` remain and render verbatim (`library_tracks_folder_screen.dart:236-259`).
- Impact: ghost rows in Loved/playlists that fail on play; inflated counts.
- Fix: remove matching collection keys on delete, or hide missing local entries at render; ~25 lines. Unverified: exact play failure symptom.

### BUG-204 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/providers/local_library_provider.dart:324-335` (`reloadFromStorage`)
- Scenario: a DB write (tag edit, duplicates, batch edit) followed by `reloadFromStorage()` while a load is in flight → awaits the stale load and returns; `loadedIndexVersion` not bumped.
- Impact: UI shows pre-edit tags/artwork until the next reload; dependent providers stay stale.
- Fix: `_reloadRequested` flag → extra pass after the in-flight load; ~8 lines.

### BUG-205 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/providers/local_library_provider.dart:1616-1631` (`clearLibrary`)
- Scenario: provider disposed during the awaited refresh → `state =` without `ref.mounted` → StateError; no guard against a running scan.
- Fix: `if (!ref.mounted) return;`; optionally refuse during `_scanInProgress`.

### BUG-303 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/utils/clickable_metadata.dart:14` (`navigateToArtistCredits`), caller `lib/widgets/local_song_menu.dart:162`
- Scenario: splits artist names on commas only → "A feat. B" opens as one artist; "Tyler, The Creator" becomes "Tyler".
- Fix: use `splitArtistNames` and prefer an exact library match.

### BUG-304 [P3] [confidence: high] [VALIDATED]
- Location: `lib/utils/clickable_metadata.dart:44-48` (`navigateToAlbum`)
- Scenario: DB error swallowed by `catch (_) {}` → "album information unavailable", nothing logged.
- Fix: log via `AppLogger`; ~3 lines.

### UI-202 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/screens/queue_tab.dart:97` (`_selectedIds`), `queue_tab_item_widgets.dart:10`, `queue_tab_filter_widgets.dart:673` (`_selectedItemsFromAll`)
- Scenario: select tracks in Songs, then type in search / a rescan bumps `loadedIndexVersion` → `_selectedIds` keeps ids no longer visible; header and "Delete N tracks" show the stale count while actions apply only to loaded items; select-all never reaches "all selected".
- Root cause: QueueTab keeps its own selection and never prunes (only folder/album screens call `pruneSelection`).
- Impact: wrong counts in labels and confirmations; actions touch fewer tracks than shown.
- Fix: intersect with visible ids when computing `selectionItems` (or exit selection on query change); derive the count from resolved items; ~10 lines + test.
- Evidence: `_selectedIds` mutated only in `queue_tab_selection.dart`; verify the search field is reachable in selection mode on device.

### UX-102 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/local_artist_screen.dart:583-607` (Popular page dots)
- Scenario: dot hit box ≈16×32 px, below the 48px rule.
- Fix: `ConstrainedBox(minWidth: 48, minHeight: 48)` around the detector, keep the 8px dot; ~3 lines.

### UX-106 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/widgets/album_detail_header.dart:788-820` (`_MornyeHeaderButton`, compact)
- Scenario: 360dp width at 1.5–2× font scale → Play/Shuffle labels ellipsize (`maxLines: 1`). Arithmetic only.
- Fix: icon-only with semantics label above ~1.3× text scale; ~10 lines.

### UX-107 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/listening_statistics_screen.dart:150-154,237-263`
- Scenario: error refresh `IconButton` has no tooltip; activity rows are announced as fragments; fixed 68px date column wraps at large scale.
- Fix: tooltip, `Semantics(label:, excludeSemantics: true)` per row, min-width instead of fixed width; ~8 lines.

### UI-203 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/library_tracks_folder_screen.dart:177` (`_removeSelected`)
- Scenario: back out while the playlist/Loved removal awaits → `exitSelectionMode()` (setState) runs before `if (!mounted) return`.
- Fix: move the mounted check above it; 1 line.

### UI-204 [P3] [confidence: high] [VALIDATED]
- Location: `queue_tab_navigation.dart:128`, `library_tracks_folder_screen.dart:771`, `playlist_picker_sheet.dart:355`
- Scenario: dialog-owned `TextEditingController`s are never disposed.
- Fix: `try/finally { controller.dispose(); }` in each.

### UI-205 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/widgets/playlist_picker_sheet.dart:221-249` (Create playlist `onTap`)
- Scenario: create flow bypasses `_isSubmitting` and has no try/catch → a throw is unhandled; double-tap or Done during the awaits can create twice / run concurrently.
- Fix: set `_isSubmitting` around the flow and catch with `friendlyError`.

### UI-206 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/duplicate_review_sheet.dart:226-232`
- Scenario: `findIsrcDuplicateGroups()` throws → `snapshot.data ?? const []` shows "no duplicates".
- Fix: handle `snapshot.hasError` with `friendlyError` + retry; ~8 lines.

### PERF-201 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/queue_tab.dart:1135` (`selectionItems`)
- Scenario: every QueueTab build recomputes the active filter's page data even outside selection mode.
- Fix: compute inside the selection branch or reuse the built `filterData`.

### PERF-202 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/library_tracks_folder_screen.dart:213`
- Scenario: `ref.watch(libraryCollectionsProvider)` (no `==`) rebuilds the whole screen on any collection change; only the cover inputs are needed.
- Fix: `select` the cover inputs.

### PERF-301 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/theme/cover_palette.dart:366-398` (`didUpdateWidget`/`_maybeResolve`), :60-76 (`cacheKeyFor`)
- Scenario: every parent rebuild of a `CoverPaletteBuilder` awaits `File(source).stat()` before the cache lookup, even for an unchanged source.
- Fix: if a host rebuilds >1/s (measure in DevTools on album/now-playing), rate-limit the stat per source or invalidate from the edit path; ~10 lines.
- Cross-refs: callers by grep only. Guards checked: `_pending` dedups in-flight only.

### UI-401 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/screens/settings/log_screen.dart:515-535` (entries mapped into one `SettingsGroup` in a `SliverToBoxAdapter`), :49-76 (`_onLogUpdate`)
- Scenario: detailed logging on → native poll every 800 ms (`logger.dart:125`) or app logs notify → `setState` rebuilds up to 500 (`maxEntries`) non-lazy tiles plus the page, then auto-scrolls.
- Fix: `SliverList.builder` with group decoration, or throttle updates; ~30 lines. Measure frame times first.
- Guards checked: `mounted` only; no throttling.

### UX-202 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/settings/cache_management_page.dart:631-636` (`totalKnownDiskCacheBytes`)
- Scenario: audio-analysis cache is listed and cleared but left out of "Estimated total".
- Fix: add `audioAnalysisStats.totalSizeBytes`; 1 line.

### UX-203 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/settings/settings_tab.dart:114-124,146`, `lib/screens/settings/settings_search_catalog.dart`
- Scenario: search keywords `layout`/`grid`/`amoled`/`provider` point at removed options; catalog misses glass clarity, custom font, lyrics text size and USB sub-options.
- Fix: drop stale keywords, add catalog entries; ~25 lines.

### SEC-302 [P3] [confidence: high] [VALIDATED]
- Location: `android/app/build.gradle.kts:134-141` (`release` signingConfig)
- Scenario: no `key.properties` → release silently signs with the debug key; the "CI re-signs" comment has no workflow in the repo.
- Fix: warn or fail release tasks without a keystore unless an opt-in property is set; ~5 lines. (Also reported by dependency-auditor as DEP-003; merged.)

### UX-207 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `AndroidManifest.xml:46` (`screenOrientation="portrait"`), `lib/services/app_orientation.dart:12-19`
- Scenario: targetSdk 37 → Android 16+ ignores orientation locks on large screens (sw ≥ 600dp), so every page, not only the full player, can render in landscape there.
- Fix: check non-player pages on a tablet/foldable emulator in landscape; fix layouts that assume portrait. No manifest change needed.

### DEP-001 [P3] [confidence: high] [VALIDATED]
- Location: `pubspec.yaml:17` (`timezone`), :40 (`cupertino_icons`), :69 (`synchronized`)
- Scenario: zero `package:` imports in lib/test/integration_test; `cupertino_icons` bundles an unused font.
- Fix: remove the three lines, `flutter pub get`.

### DEP-002 [P3] [confidence: high] [VALIDATED]
- Location: `rust_backend/NOTICE:17` (`crates/network/src/url.rs`), `pubspec.yaml:31` ("# HTTP & Network" over `crypto`)
- Scenario: NOTICE attributes Go-licensed code to a crate that no longer exists; pubspec comment names a removed section.
- Fix: repoint or drop the NOTICE sentence; retitle the comment. Docs only.

### TEST-203 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `test/library_collections_hydration_test.dart:335-348,455-464` (`expect(ticks, greaterThan(1))`), `test/support/library_collections_benchmark.dart:71`, integration_test native heartbeats
- Scenario: responsiveness asserted by counting real 1 ms `Timer.periodic` ticks; a fast parse (smaller fixture at :333) can yield 0–1 ticks.
- Fix: order-based check (timer/microtask scheduled mid-work ran before completion) instead of a count.

### TEST-205 [P3] [confidence: high] [VALIDATED]
- Location: repo-wide (~55 `expect(x.length, N)`, ~8 `expect(x.isEmpty, isTrue)`, e.g. `library_collections_database_read_test.dart:151`, `local_artist_popular_test.dart:71-72`)
- Scenario: weak matchers give poor failure messages; no false passes found.
- Fix: use `hasLength`/`isEmpty`/`everyElement` only in files already being touched.

### TEST-101 [P3] [confidence: high] [VALIDATED]
- Location: test trim map for the dead-code sweep (one entry instead of per-DEAD edits)
- Scenario: these tests keep dead code alive and must be deleted or trimmed together with the matching entry:
  - DEAD-001: delete `ffmpeg_decryption_output_test.dart`.
  - DEAD-002: delete `lyrics_metadata_helper_test.dart`, `re_enrich_release_policy_test.dart` and `re_enrich_result_test.dart`.
  - DEAD-003: delete `cover_art_utils_test.dart`.
  - DEAD-004 and DEAD-632: trim `downloaded_embedded_cover_resolver_test.dart` and `cached_cover_decode_test.dart`.
  - DEAD-202: trim `platform_bridge_metadata_test.dart:157-167`.
  - DEAD-203 and DEAD-304: trim `integration_test/lyrics_file_access_test.dart`, plus the `getLyricsLRCWithSource` stubs in `mornye_library_actions_test.dart:50` and `library_search_results_test.dart:54`.
  - DEAD-207: delete `ios_library_folder_sheet_test.dart`, `ios_container_paths_test.dart` and `file_access_ios_test.dart`, and trim the bookmark cases in `platform_bridge_metadata_test.dart:181-193` and `installation_restore_test.dart:98-120`.
  - DEAD-401, DEAD-402 and DEAD-403: trim these. Keep the "old JSON still loads" and "key absent" assertions.
    - `models_and_utils_test.dart:545-615`
    - `settings_persistence_test.dart:75,124,132`
    - `native_backup_contract_test.dart:95-132` and `fixtures/native_backup_contract.json`
    - `integration_test/native_data_jobs_test.dart` and `integration_test/native_history_snapshot_test.dart`
    - The `downloadDirectory*` and `downloadDirectoryBookmark` model fields are not yet covered by a DEAD entry. Add them to that sweep.
  - DEAD-501: delete `provider_resource_ids_test.dart`.
  - DEAD-502: delete `ttl_cache_test.dart`, and trim or delete `cover_cache_maintenance_test.dart`.
  - DEAD-503: trim `models_and_utils_test.dart:25-49,272-283,892-893` and `artist_utils_test.dart:24-33`.
  - DEAD-504: delete `album_description_test.dart`.
  - UX-104: delete `track_history_snapshot_test.dart`, `track_collection_action_policy_test.dart` and `track_list_tile_selection_test.dart`. Trim `library_tracks_folder_data_test.dart` (`historyRequest`) and `maintainability_contracts_test.dart:91-94`.
  - DEAD-601: delete `expressive_seek_track_test.dart`. Trim `now_playing_lyrics_transition_test.dart:27,274-275`, and rework `player_widget_ownership_test.dart:80` (it builds `MaterialPlayerLayout`).
    - A reviewer flagged `playback_seek_slider.dart:124` as a live use. It is not: the Mornye branch at `:83` always returns before it.
  - DEAD-602: delete `smoothed_progress_test.dart`.
  - DEAD-603: trim `app_snack_bar_test.dart` and `shell_navigation_service_test.dart:162`.
  - DEAD-631: trim `detail_route_loading_test.dart` and `mornye_loading_and_chrome_test.dart`.
  - DEAD-633: delete `material_expressive_test.dart`, and trim `loading_motion_preferences_test.dart`, `adaptive_overlay_test.dart` and `support/material_test_theme.dart`.
- Fix: apply the list together with each DEAD batch. The lists come from grep, so read each case before deleting it. Keep the tests that assert removed features stay removed (e.g. `tutorial_copy_test.dart:20-25`, `collections_upgrade_test.dart`).

### PERF-401 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/services/library_schema.dart:231-244` (`_createNormalizedIndexes`), `lib/services/library_queue_store.dart:242,503-506` (`artistPage`, `_appendQueueLocalFilters`)
- Scenario: these queries filter, group or order by `l.album_artist_norm`, and every one of them is a full scan on a library of 10k–50k tracks:
  - artist-screen tracks, Popular and discography
  - the Home Artists shelf
  - `artistPage` (`GROUP BY album_artist_norm ORDER BY artist_key LIMIT/OFFSET`)
  - Artists with fewer than 40 tracks cannot stop at the LIMIT, so each page scans the whole table.
- Root cause: no index covers `album_artist_norm`. A source check confirms that only `match_key`, `album_key`, `*_name_norm` for track/artist/album, `scanned_at` and the queue orders are indexed.
- Fix: add `album_artist_norm`, or a composite `(album_artist_norm, album_key)`, to `_createNormalizedIndexes` with `IF NOT EXISTS` in an upgrade; ~5 lines.
- Measure: `EXPLAIN QUERY PLAN` and a Stopwatch around `getQueueTrackPageResult(albumArtist:)` on a 20k fixture, before and after.

### PERF-402 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/services/library_genres.dart:8-48` (`libraryGenreTagsSql`, `LibraryGenres.page`); caller `lib/screens/local_genres_screen.dart:76,142`
- Scenario: a recursive CTE splits `genre` on `;` across every visible row, then runs DISTINCT/GROUP BY again for each 40-row page of the Genres list and of each genre's tracks. `genre` has no index.
- Impact: estimated 50–200 ms of SQLite time per page at 20k tracks. Pages load slowly; the UI isolate does not stall.
- Fix: cache the exploded tags per `loadedIndexVersion` (a table or an in-memory list); ~40 lines.
- Measure: a Stopwatch around `LibraryGenres(db).page()`, list and detail, on 20k tracks with multi-valued genres.

### PERF-404 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/services/library_database.dart:793-815` (`getLookupIndex`), `lib/providers/local_library_provider.dart:65-76,266-300,538-562`
- Scenario: about 15 refresh paths (after a scan, edit, delete, clear or source change) load up to 2×N `match_key`/`isrc` strings into two Dart `Set`s.
  - The only consumer, `existsInLibrary`, is called only from `track_list_tile.dart:52`.
  - `TrackListTile` is dead code (UX-104).
- Impact: an estimated 40k–100k strings are decoded and held in memory on every refresh, purely for dead code.
- Fix: drop `getLookupIndex` and the sets from `LocalLibraryState` together with the UX-104 removal; ~30 lines removed.

### PERF-405 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/screens/home_tab_feed.dart:7-12`, `lib/services/library_queue_store.dart:430-470` (`_queueAlbumUnionSql`), `lib/providers/library_browse_provider.dart:150-170`
- Scenario: every `loadedIndexVersion` bump re-runs about four full-library aggregates for the Home shelves. The browse notifier also re-reads every loaded page.
- Fix: only if the measurement is bad, cache shelf results per version or use an album summary table.
- Measure: a Stopwatch around the shelf queries at Home mount, at 20k and 50k tracks.

### PERF-601 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/providers/local_artist_provider.dart:136-139,147-201` (`localArtistPopularProvider`, play-count loader)
- Scenario: to pick the top 20, the provider pages the artist's whole catalogue 40 rows at a time. Each page runs a DB query, `fromJson` on the UI isolate, `listeningRecorder.flush()` and `playsForTracks`. A `loadedIndexVersion` bump starts the whole thing again.
- Fix: as a minimum, flush once before the loop (~5 lines). Better: a SQL top-20 joined with play counts.
- Measure: a Stopwatch around the provider for an artist with ~2000 tracks.

### PERF-602 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/queue_tab_filter_widgets.dart:53-62,283-300` (`localNavigationItems`, `localNavigationIndexByUnifiedId`)
- Scenario: every QueueTab build makes an O(N) list and a Map over all loaded rows. `_buildUnifiedLibraryItem`/`_buildUnifiedGridItem` accept them but never read them. This adds to PERF-201 (`selectionItems`), and they would be fixed together.
- Fix: delete the parameters and the loop (~20 lines removed).

### PERF-603 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/screens/home_tab_feed.dart:14-15` (`_buildLocalFeed`)
- Scenario: the root `HomeTab.build` watches the whole `libraryCollectionsProvider` (which has no `==`) and sorts playlists. A Loved toggle or playlist edit rebuilds all of Home, including while it is kept alive off-screen.
- Fix: a `Consumer` or `select` on playlists, with the sort memoised; ~10 lines. Measure with the DevTools rebuild counter while toggling Loved.

### PERF-604 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/main.dart:41,79-87` (`main`)
- Scenario: the `setAppOrientation()` channel call is awaited before, and in sequence with, the prefs and install-marker steps that it does not depend on.
- Fix: start it in parallel and await it before `runApp`; ~3 lines. Estimated saving 5–20 ms; check with `--trace-startup`.

### PERF-501 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `rust_backend/crates/local/src/backend/cover.rs:109-183` (`cache_cover`), `rust_backend/crates/local/src/files.rs:586-600` (`StagedFile::publish`)
- Scenario: the cover cache is keyed per file (`uri|lastModified` or `path|size|mtime`), so every track with embedded art writes its own thumbnail. Each write runs `sync_all` plus a directory fsync (source-confirmed).
  - Example: 10k tracks across ~800 albums gives ~10k files and ~20k fsyncs for a cache that can be regenerated.
  - The in-memory dedup (32 entries) only skips the repeated decode.
- Fix: ~20 lines, either of:
  - name the file by a hash of the thumbnail bytes and skip it if it exists; this must stay compatible with the cover sweep and with DATA-502/CONC-102;
  - publish the cache without fsync.
- Measure: scan time of a 2k-track corpus, `strace -c -e fsync,fdatasync`, and `du` of the cover dir against the distinct album count.

### PERF-502 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafIo.kt:253-270` (`acceptRead`), `SafMetadataReadPolicy.kt:22-28`
- Scenario: unreadable or missing tags (`metadataFromFilename: true`) make `acceptRead` throw `IOException`. The fallback then:
  - copies the whole file to temp;
  - reads it again;
  - retries the direct read.
  The file is never stored, so this repeats on every incremental scan. The path is source-confirmed; how often it happens in real libraries is unknown.
- Fix: return a typed "file readable, tags unreadable" result and skip the copy and retry for it, keeping the fallback for open/seek failures; ~10 lines.
- Measure: count `copyUriToTemp` calls while scanning 200 untagged MP3s.

### PERF-503 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `rust_backend/crates/local/src/backend/library.rs:89-112`, `rust_backend/crates/core/src/tags/containers.rs:257-310`
- Scenario: Ogg/Opus covers are reassembled twice on a cache miss: the comment packet with its base64 art goes through `extract_cover` and again through `read_library_metadata`. FLAC already uses a merged pass.
- Fix: reuse the assembled packet; ~30 lines. Measure on an Opus-heavy corpus first.

### PERF-504 [P3] [confidence: high] [VALIDATED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1555-1575,1508-1509,1098-1099`
- Scenario:
  - Every incremental scan copies each unchanged `.cue` to temp, one at a time, just to re-resolve its audio sibling.
  - Changed CUEs query `audioDoc.name`/`lastModified()` again, though the listing already holds them.
- Fix: persist the cue→audio URI mapping, or resolve it from the cached listing; ~20 lines.

<!-- Mornye parity pass (2026-10-20): upstream v5.1.1/latest Mornye path of the online
artist/album/playlist screens compared with the local screens. Upstream refs are
`spotiflacapp/SpotiFLAC-Mobile`; see `UPSTREAM.md`. -->

<!-- Home parity pass (2026-10-20): upstream v5.1.1/latest Mornye Home (explore feed) compared
with the local Apple Music Home. Overlaps: PERF-405, PERF-603. -->

<!-- Now Playing parity pass (2026-10-20): ours vs upstream v5.1.1/latest Mornye player.
Ours equals v5.1.1 apart from intentional deltas (Immersive view, no motion artwork,
external player or download lookups). Upstream-latest items are in `UPSTREAM.md`. -->

### UI-402 [P2] [confidence: high] [VALIDATED]
- Location: `lib/screens/local_album_screen.dart` (`_deleteSelected`)
- Scenario: in an album, select some (not all) tracks and confirm delete → files are deleted but the rows stay on screen; footer count/duration/quality are stale; tapping a stale row fails to open a missing file.
- Root cause: `_deleteSelected` only exits selection and pops when every track was deleted; it never drops deleted ids from `_loadedTracks`/`widget.tracks` or calls `_rebuildTrackCaches`. Callers pass static track lists, and the build watches no library provider.
- Fix: after a non-zero delete, remove the deleted ids in `setState` and rebuild the caches (the per-track menu path already refreshes); ~8 lines + widget test.
- Guards checked: `pruneSelection` trims only selected ids; the pop guard covers the all-deleted case only. (Reported as P1 by flutter-dart-auditor; demoted: no data loss, the view is stale.)

### UI-403 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/screens/track_metadata_edit_sheet.dart` (`_save`), shown from `lib/widgets/local_song_menu.dart` (`editLocalSongMetadata`)
- Scenario: tap Save, then dismiss the sheet (barrier tap or Back) while the save writes → tags are written, but `mounted` is false so the sheet never pops `true`; the caller sees null and skips the re-read/upsert, so the library row and player keep the old tags until a rescan, and a failure is never reported.
- Fix: `PopScope(canPop: !_saving)` and `isDismissible`/`enableDrag` false while saving (or return the result through a caller-owned callback); ~5 lines.
- Guards checked: none block dismissal during the save.

### UI-404 [P2] [confidence: high] [VALIDATED]
- Location: `lib/screens/home_tab.dart` (`_onSearchChanged`)
- Scenario: query is `''`; type "a" (300 ms debounce starts) and backspace within 300 ms → `text == _query` returns before `_searchDebounce?.cancel()`, the pending timer fires and sets `_query = 'a'` under an empty field; Home shelves stay hidden behind stale results.
- Fix: cancel the debounce before the equality check; 1 line + test.

### UI-405 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/local_artist_screen.dart` (Popular row divider `Positioned(left: 80, right: 20)` and row padding `fromLTRB(20, 8, 10, 8)`), `lib/screens/track_metadata_edit_sheet.dart` (`_selectionField` `EdgeInsets.only(left: 4, ...)`)
- Scenario: RTL locale → the divider inset and label inset sit on the wrong side.
- Fix: `PositionedDirectional`/`EdgeInsetsDirectional`; ~3 lines.

### UI-406 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/audio_analysis_widget.dart` (`_loadSpectrogramFromCache`; consumers `_tryLoadFromCache`, `_analyze`, `_changeSpectrogramChannel`)
- Scenario: a truncated cached spectrogram PNG (app killed during the non-atomic write) → `ui.decodeImageFromList(bytes, completer.complete)` reports the decode error as an unhandled async error and never completes the completer; the surrounding try/catch never fires.
- Impact: channel switch spins forever (chips and Save disabled) on every reopen; the cache key is never released or trimmed; Analyze with a valid JSON cache never clears `_analyzing`.
- Fix: decode with `ui.instantiateImageCodec` + `getNextFrame()` inside the try/catch, dispose the codec, delete the bad file and regenerate; ~8 lines.

### UI-407 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/screens/queue_tab.dart` (`QueueTab.build`: `libraryCollectionsProvider.select` tuple, then `ref.read`)
- Scenario: Library → Playlists; open a playlist and rename it, change its cover or edit its tracks without changing the playlist count; go back → the grid keeps the old name, cover, track count and sort order. Singles' playlist-membership filter is stale the same way.
- Root cause: the build watches only counts and flags, but renders `playlists[i]` fields from `ref.read`; `LibraryCollectionsState` has no `==`.
- Fix: also watch `select((s) => s.playlists)` for the playlists section (or move the grid into a `Consumer`); ~5 lines + test.

### UI-408 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/screens/queue_tab.dart` (`activePageValue`/`countsValue` handling), `lib/screens/queue_tab_filter_widgets.dart`
- Scenario: the library page or counts provider throws → error is never surfaced; the page shows the empty "go Home" state and can hide the search field.
- Fix: render `ErrorCard` with retry (`ref.invalidate`) on `hasError`; ~10 lines.

### UI-409 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/mornye_library_screen.dart` (search `IconButton` toggle)
- Scenario: type a query, then tap the search icon to hide the field → `_query` stays set; the overview keeps showing search results and Albums/Artists stay filtered with no visible field or clear control.
- Fix: clear `_search`/`_query` when hiding, or keep the field while a query is set; ~4 lines.

### UI-410 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/screens/mornye_library_screen.dart` (scroll listener, Retry, `onRefresh`), `lib/providers/library_browse_provider.dart` (`loadMore`)
- Scenario: `loadMore()` fails on Albums/Artists → every scroll tick near the end retries it; Retry invalidates the provider and drops every loaded page; pull-to-refresh rethrows from `onRefresh`.
- Fix: skip auto load-more while `loadMoreError` is set, make Retry call `loadMore()`, catch in `onRefresh`; ~8 lines. Needs a forced failure to confirm.

### UI-411 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/library_search_results.dart` (`_toggleSelection`, `_selectAllVisible`)
- Scenario: double-tap an unselected search result before its lookup resolves → both taps select it; a lookup error escapes the tap callback and fails select-all silently.
- Fix: in-flight set, re-check after the await, try/catch with a snackbar; ~10 lines.

### UI-412 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/library_selection_playback_actions.dart` (Play next / Add to queue)
- Scenario: `enqueueLibraryItems` throws → unhandled async error, the bar stays open, no snackbar.
- Fix: try/catch with `showCannotOpenFileSnackBar`, as the other playback paths do; ~6 lines.

### UI-413 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/screens/settings/backup_restore_page.dart` (`_restoreBackup`, `_isBusy`)
- Scenario: tap Import, pick a large backup; while it parses or the confirm dialog is open, tap Import again → `_isImporting` is set only after confirmation, so a second restore runs and both interleave settings, history (which clears first) and collection restores.
- Fix: a `_restoring` flag set at entry, cleared in `finally`, included in `_isBusy`; ~5 lines.

### UI-414 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/screens/settings/library_settings_page.dart` (`_pickLibraryFolder`, `_startScan`, `_removeSource`, `_requestStoragePermission`)
- Scenario: the SAF picker throws or `addSource` fails → nothing visible happens; scan and remove have no catch; `_requestStoragePermission` calls `setState` after an await without `mounted` (pre-API 29).
- Fix: try/catch with the page's existing `snackbarError(friendlyError)`; add the `mounted` check; ~15 lines.

### UI-415 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/mornye_performance_hud.dart` (`_move` vs `_clamped`)
- Scenario: drag the developer HUD past an edge → the stored position is unclamped, so it seems stuck until the overshoot is undone; after rotation it can sit far off-screen.
- Fix: store `_clamped(next)` in `_move`; 1 line.

### UI-416 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/screens/settings/library_settings_page.dart` (keyless `Consumer` per library source)
- Scenario: remove a middle source → row state is reused by position; switches may flash.
- Fix: `key: ValueKey(source.id)`; 1 line.

### UI-417 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/main_shell.dart` (`_KeepAliveTabPage`)
- Scenario: unused leftover from the previous tab host (`LazyTabView` replaced it).
- Fix: delete it; ~20 lines.

### UI-418 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/widgets/player_lyrics.dart` (`_TimedLyricSweepPainter.paint`)
- Scenario: word-timed RTL lyrics (Arabic/Hebrew) → the colour sweep runs left to right against the reading direction.
- Fix: mirror the reveal per RTL `TextBox` and order boxes by reading order; ~15 lines.

### UI-419 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/widgets/mornye_player_layout.dart` (compact cover rect, `_PlayerHeaderLayout.performLayout`)
- Scenario: RTL on the lyrics/queue page → the compact header uses physical left/right, so it is not a mirror of the expanded header and the ellipsis no longer aligns with the timeline end.
- Fix: resolve left/right from `Directionality`; ~10 lines.

### UI-420 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/screens/lyrics_share_screen.dart` (6:4 `Expanded` split)
- Scenario: landscape phone or large text → the line list shows about one row.
- Fix: side-by-side layout below a height threshold; ~15 lines.

### PERF-605 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/mornye_artist_header.dart` (`MornyeGroundAnchor` around the collapsing artwork), `lib/widgets/mornye_artwork_glass.dart` (`_RenderGroundAnchor.performLayout` → `_changed` → `_schedule`; `_MornyePageGroundState._build` key includes `size`)
- Scenario: scroll the artist page so the header collapses → the anchor's box shrinks each frame, every size change schedules a post-frame ground build, and the exact size is in the build key, so the page ground (cover decode, blur at the clarity sigma, `toImage`) is rebuilt roughly once per collapse frame; stale results are discarded by the generation check.
- Impact: GPU/CPU work on every scroll frame of the artist header; a likely contributor to the artist-page raster p90 the owner measured (21-43 ms). Album and playlist anchors scroll with the content at a fixed size and are not affected.
- Fix: build the ground once for the expanded size (e.g. anchor a fixed `maxExtent` box, or exclude height from the key and let the veil/controls sample it scaled); measure raster p90 before and after with the HUD.

### UX-208 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/library_tracks_folder_screen.dart` (`_removeSelected`)
- Scenario: remove 3 tracks from a playlist or Loved → the snackbar reads "3 selected" (`selectionSelected`).
- Fix: a removed-from-playlist/Loved l10n string; ~5 lines + arb.

### UX-209 [P2] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/screens/queue_tab_collection_items.dart` (`_buildCollectionGridItem`), `lib/screens/queue_tab_filter_widgets.dart` (playlists grid `childAspectRatio: 0.72`)
- Scenario: 360dp phone at 2x font → fixed square cover leaves about 55dp for title and count, which need about 71dp → RenderFlex overflow.
- Fix: `Expanded` cover or a text-scaled `mainAxisExtent`; ~5 lines + textScale 2 widget test.

### UX-210 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/screens/queue_tab_collection_items.dart` (playlist selection mode)
- Scenario: in playlist selection mode, tiles expose no selected/checked state and still announce "Open playlist".
- Fix: `Semantics(selected:)` and a select/deselect label in selection mode; ~8 lines.

### UX-211 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/widgets/selection_bottom_bar.dart`, `lib/screens/library_tracks_folder_screen.dart` (`appBarTitle`)
- Scenario: the "N selected" count changes silently for TalkBack.
- Fix: `Semantics(liveRegion: true)` around the count; 1-2 lines.

### UX-212 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/screens/queue_tab_filter_widgets.dart` (`_countHeaderRow`)
- Scenario: 1.5-2x font on 360dp → Filter/Create buttons shrink inside `FittedBox(scaleDown)` below 48dp and below 1x text.
- Fix: `Wrap` or a second row when narrow; ~10 lines.

### UX-213 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/local_song_row.dart` (ellipsis and Play tooltips, explicit badge)
- Scenario: playlist/Loved/genre/album rows announce only "More options"/"Play"; the explicit badge reads "Explicit E".
- Fix: title/artist in tooltips (`a11yPlayTrackByArtist`, new "More options for {title}"), `excludeSemantics: true` on the badge; ~8 lines.

### UX-214 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/local_song_row.dart` (numbered leading `SizedBox(width: 24)`)
- Scenario: 1.5-2x font on albums with 10+ tracks → track numbers wrap or overflow.
- Fix: `FittedBox(scaleDown)` + `maxLines: 1`, or a text-scaled width; 2-3 lines.

### UX-215 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/playlist_picker_sheet.dart` (`error:` branch)
- Scenario: the summaries provider throws → "No playlists yet" with no retry.
- Fix: `friendlyError` + Retry (`ref.invalidate`); ~8 lines.

### UX-216 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/library_search_results.dart` (load-more `IconButton`)
- Scenario: the load-more button's tooltip is the category name ("Songs").
- Fix: a Show more string; 1 line + arb.

### UX-217 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/screens/library_tracks_folder_screen.dart` (`_pickCoverImage`, `_removeCoverImage`, rename), `lib/screens/queue_tab_navigation.dart` (`_showCreatePlaylistDialog`)
- Scenario: setting a cover, renaming or creating a playlist throws → no feedback; the Songs-tab create dialog uses stock `AlertDialog` instead of `AppAlertDialog`.
- Fix: catch with `friendlyError` snackbars; use `showAppDialog`/`AppAlertDialog`; ~15 lines.

### UX-218 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/screens/local_guide_pages.dart` (`_TutorialPage` bottom gap) vs `lib/screens/setup_screen.dart` (`floatingActionButton`)
- Scenario: setup tip pages (especially the last with the Ready card) at a small viewport or large text → content ends 12-32dp above the bottom, so the Next button permanently covers it.
- Fix: the same `24 + _headerHeight`-style bottom padding the other steps use; ~3 lines.

### UX-219 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/setup_screen.dart` (no `PopScope`)
- Scenario: press system Back on setup step 4 → the app exits instead of going to step 3.
- Fix: `PopScope(canPop: _currentStep == 0, onPopInvokedWithResult: → _prevPage)`; ~8 lines.

### UX-220 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/settings_group.dart` (`SettingsChoiceChip`), `lib/screens/settings/metadata_separator_settings_page.dart` (separator rows)
- Scenario: TalkBack does not announce the selected Player view or separator.
- Fix: `Semantics(selected:, button: true, inMutuallyExclusiveGroup: true)`; ~6 lines.

### UX-222 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/widgets/music_haptics_settings.dart`, `lib/widgets/playback_normalization_settings.dart`
- Scenario: Sensitivity, Strength and Pre-amp sliders are announced with only a value.
- Fix: `Semantics(label:)` as the clarity slider does; ~3 lines.

### UX-223 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/settings/playback_settings_page.dart` (`-bit PCM`, `DSD (DoP)`, `DSD (Native)`, `kHz`, `Beta`), `about_page.dart` (version line), `log_screen.dart` (`Native` badge), `library_settings_page.dart` (`day/month/year` last-scanned)
- Scenario: non-English locale → mixed-language labels and a fixed date order.
- Fix: l10n keys and `DateFormat.yMd(locale)`; ~10 lines.

### UX-224 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/screens/settings/cache_management_page.dart` (`_buildClearTrailing`)
- Scenario: five "Clear" buttons with no per-row label for TalkBack.
- Fix: label or tooltip naming the cache; ~6 lines.

### UX-225 [P3] [confidence: high] [VALIDATED]
- Location: `lib/screens/setup_screen.dart` (`animateToPage`), `lib/screens/local_guide_pages.dart` (staggered/implicit animations), `lib/widgets/settings_group.dart` (`SettingsSearchTarget._reveal` `ensureVisible`)
- Scenario: reduced motion on → setup slides/bounces and the settings search scroll still animate.
- Fix: `Duration.zero`/`jumpToPage` when `disableAnimationsOf`; ~10 lines.

### UX-226 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/screens/settings/library_settings_page.dart` (hero card `Alignment.centerLeft`, `Positioned(right:/left:)` decor, `EdgeInsets.only(right: 8)`)
- Scenario: RTL → hero count and decor stay on physical sides.
- Fix: directional alignment, `PositionedDirectional`, `EdgeInsetsDirectional`; ~4 lines.

### UX-229 [P2] [confidence: medium] [VALIDATED]
- Location: `lib/screens/listening_rewind_screen.dart` (`_RewindStoryState` auto-advance)
- Scenario: TalkBack on → slides auto-advance every 6 s while the reader is still speaking (only `disableAnimationsOf` is checked).
- Fix: `_autoAdvance = !disableAnimations && !MediaQuery.accessibleNavigationOf(context)`; ~2 lines.

### UX-230 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/album_detail_header.dart` (`HeaderCircleButton` defaults `buttonSize ?? 44`)
- Scenario: the default back circle on album, playlist, artist and `AppSliverHeader` pages draws 44dp, while AGENTS.md says header controls are 48dp (`kMornyeHeaderControlSize`); the glass radius already assumes 48.
- Fix: default to `kMornyeHeaderControlSize`; 3 lines (update header size tests).

### UX-231 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/screens/track_metadata_edit_sheet.dart` (saving spinner, Advanced header, `AnimatedSize`/`AnimatedRotation`)
- Scenario: the saving spinner is unlabeled, the Advanced header has no button/expanded semantics, and its animations ignore reduced motion.
- Fix: `Semantics(button:, expanded:)`, a live-region "Saving" label, zero durations under reduced motion; ~12 lines.

### UX-232 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/screens/listening_rewind_screen.dart` (left-third tap = previous, `EdgeInsets.fromLTRB(16, 8, 4, 0)`), `lib/screens/listening_statistics_screen.dart` (`chevron_left`/`chevron_right`)
- Scenario: RTL → reversed story tap zones, asymmetric Close/progress insets, year arrows pointing the wrong way.
- Fix: directional insets, flip the zone test, direction-aware chevrons; ~8 lines.

### UX-233 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/widgets/metadata_text_field.dart`
- Scenario: the visible label is a separate `Text`; most fields have no hint, so TalkBack may read an unlabeled edit box.
- Fix: `Semantics(label:)` around the field; ~3 lines. Verify with a semantics test.

### UX-234 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/mornye_level_slider.dart` (`_update`, `_LevelPainter`, thumb centre)
- Scenario: RTL → the horizontal EQ gain slider does not mirror, unlike `MornyeSlider` and `AppSwitch`.
- Owner decision (2026-10-23): the gain slider mirrors in RTL like every other slider.
- Fix: use `1 - fraction` when horizontal and RTL, in `_update`, the painter and the thumb centre; ~8 lines. The vertical EQ faders are unchanged.

### UX-235 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/app_choice_chip.dart`, `lib/widgets/app_action_button.dart`, `lib/widgets/app_switch.dart`
- Scenario: default text scale → chip and action button are about 44dp tall and the standalone switch hit box 71x44; 45 chip call sites repeat the shortfall.
- Fix: `minimumSize: Size(48, 48)` on both `CupertinoButton`s and a 48dp switch hit box; ~3 lines.

### UX-236 [P3] [confidence: low] [NEEDS VERIFICATION]
- Location: `lib/widgets/app_choice_chip.dart` (selected state), `lib/widgets/audio_quality_badges.dart` (`ExplicitBadge`)
- Scenario: light Mornye, red accent → selected chip text about 4.4:1 and the light explicit badge about 3.9:1 (hand-computed).
- Fix: measure first; if below AA use `onSurface` for the selected label and an opaque badge fill.

### UX-237 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/audio_analysis_info_card.dart` (`_formatChannelStats`, `_formatChannels`)
- Scenario: `Ch n`, `P`, `R`, `DR`, `Clip` and `N/A` are hard-coded English.
- Fix: arb keys; ~6 strings.

### UX-239 [P2] [confidence: high] [VALIDATED]
- Location: `lib/widgets/mornye_player_queue.dart` (queue rows), `lib/widgets/player_queue_dismissible.dart`
- Scenario: TalkBack or switch access in Up Next → removing a queued song is swipe-only; `Dismissible` exposes no semantic action and the row has no remove control.
- Fix: a `CustomSemanticsAction` "Remove" calling the same removal; ~8 lines.

### UX-240 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/playback_seek_slider.dart` (`Semantics(slider: true, excludeSemantics: true)`)
- Scenario: the seek bar is announced as an unnamed "slider, 37%".
- Fix: a seek label (new arb key) and `formatClock` values for value/increase/decrease, as the volume slider does; ~6 lines.

### UX-241 [P3] [confidence: high] [VALIDATED]
- Location: `lib/widgets/automix_settings.dart` (`slider` helper)
- Scenario: AutoMix duration, pitch and speed sliders are announced as unnamed range percentages ("50%" for pitch 0.0).
- Fix: `Semantics(label:)` and a `semanticFormatterCallback` with the real value and unit, as `LyricsSizeSetting` does; ~6 lines.

### UX-242 [P3] [confidence: medium] [NEEDS VERIFICATION]
- Location: `lib/screens/now_playing_screen.dart` (minimize `IconButton` as the title of a 36dp toolbar)
- Scenario: the minimize control is about 36dp tall. Swipe-down and Back still dismiss.
- Fix: a 48dp toolbar or taller hit area; 1-3 lines.

### UX-243 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/widgets/mini_player.dart` (`Dismissible`)
- Scenario: dismissing the mini player is swipe-only; TalkBack/switch users cannot dismiss it.
- Fix: a "Dismiss" `CustomSemanticsAction` running the same `setState` + `stop()`; ~6 lines. Fix together with UI-101.

### UX-244 [P3] [confidence: medium] [VALIDATED]
- Location: `lib/screens/lyrics_share_screen.dart` (`_SelectionCount`)
- Scenario: the "n/N" selected-lines count changes silently for TalkBack.
- Fix: `Semantics(liveRegion: true, container: true)`; 2 lines.

## Resolved

### CONC-001 [P2] [confidence: medium] [RESOLVED]
- Location: lib/services/music_player_service.dart (`seek`), `skipToPrevious` restart, `_playInternal`
- Scenario: app restarts with a restored paused session (`_pendingRestorePosition = X`, `_sourceReady = false`); user seeks to Y (lyrics tap, notification seek) → `seek` hits a deck with no source, UI shows Y; on Play `_playInternal` starts at X.
- Resolution: T7. `seek` now publishes the position immediately, stores it in `_pendingRestorePosition` while `!_sourceReady`, and runs the transport seek inside `_serializeSourceChange` guarded by the play generation; `_loadIndex` consumes `_pendingRestorePosition` when it builds the effective start position, so a seek that lands before the source finishes loading (including during `cancelPreparation`) still wins. `skipToPrevious`'s restart branch reuses `seek(Duration.zero)`. Regressions: "seek before restored source load replaces the saved position", "seek while preparation cancellation waits becomes the load position", "seek during source preparation waits for the new source", "previous restart before restored load is retained on play".

### CONC-002 [P2] [confidence: high] [RESOLVED]
- Location: lib/services/music_player_service.dart (`onSourceDeleted`), `_stopSession`
- Scenario: user stops playback (`_index = -1`, session cleared, queue kept) then deletes a file that was in that queue → else-branch clamps `_index` to 0, broadcasts and persists the session.
- Resolution: T7. The clamp/broadcast/persist branch is skipped when `_index < 0`, so an explicitly stopped session is not revived by a later deletion; the queue entry is still removed. Regression: "deleting a queued source cannot revive an explicitly stopped session".

### CONC-003 [P3] [confidence: low] [RESOLVED]
- Location: lib/services/music_player_service.dart (`unawaited(play())`, `unawaited(_handlePlayerComplete())`, `unawaited(pause())`)
- Scenario: `UsbOutputUnavailable` or a channel `PlatformException` from `stop`/`resume` inside these futures.
- Resolution: T7. Fire-and-forget transport callbacks now run through `_runPlaybackCallback`, which reports a failure through the existing playback-error path (keeping the selected track retryable) unless a newer play request superseded it; `_playIndex` owns failures raised after its own generation bump (last-track completion awaiting autoplay, preparation cancellation). Regressions: "sleep timer pause failure is caught and keeps a retryable track", "completion transport failure is caught and published as a playback error", "last-track completion reports stop failure after pending autoplay appends".

### CONC-004 [P3] [confidence: low] [RESOLVED]
- Location: lib/services/music_player_service.dart (`play`)
- Scenario: `play()` while an older operation is active joins it even after `pause()`/`stop()` bumped `_playRequestGeneration`; the old op aborts and the newer Play is dropped.
- Resolution: T7. The join compares the active operation's generation and only shares work with an operation started for the current generation; an accepted new Play bumps the generation before starting, so a Pause delayed on AutoMix cleanup cannot enqueue after it and win. Regression: "Play after Pause does not join an invalidated resume".

### KT-002 [P3] [confidence: low] [RESOLVED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/HiResPlayback.kt, UsbDirectPlayback.kt, UsbPcmSource.kt, NativeAudio.kt
- Scenario: `libspotiflac_audio` fails to load → `UnsatisfiedLinkError`/`ExceptionInInitializerError` (an `Error`, not `Exception`) escapes the worker-thread catch and crashes the process instead of falling back.
- Resolution: T7. Verified by trace: the static `System.loadLibrary` failure (and a missing JNI symbol) reached only `Exception` handlers. New `NativePlaybackFailure.kt` converts `LinkageError` alone into an `IllegalStateException` that preserves the cause, leaving ordinary exceptions and fatal VM errors untouched; the existing prepare/command/pump boundaries in `HiResPlayback`, `UsbDirectPlayback` and `UsbBitPerfectPlugin` now contain it, `UsbPcmSource` releases partially initialised JNI state, and WavPack DSD construction cleans up its decoder handle before propagating. No external-player fallback was added. Regressions: `NativePlaybackFailureTest` (4 host tests).

### SEC-101 [P3] [confidence: medium] [RESOLVED]
- Location: `PlayerWidgetProvider.kt` (`PlayerWidgetBridge.handleIntent`), AndroidManifest exported launcher Activity
- Scenario: any app can start the exported launcher Activity with `player_widget_command=<any>`; forwarded to Dart unvalidated (receiver path allow-lists toggle/next/previous).
- Resolution: T7. Verified by trace: `handleIntent` forwarded any command string. The extra is now removed and validated against one shared `PlayerWidgetCommandPolicy` used by both the activity bridge and the widget receiver; unknown commands are consumed without dispatching or replacing a pending transport. Regressions: `PlayerWidgetCommandPolicyTest` (2 host tests) and a `PlayerWidgetTest` instrumentation case (compiled, not executed).

### SEC-303 [P3] [confidence: low] [RESOLVED]
- Location: exported `AudioService` (`onGetRoot`), `music_player_service.dart` queue publications
- Scenario: `onGetRoot` accepts any caller → any installed app can browse the current queue (ids, titles, art URIs; ids may be file paths/URIs) and `playFromMediaId`.
- Resolution: T7. Verified by trace: the Dart queue publishes raw `source`/`resolvedSource` extras and a local artwork URI, and `onGetRoot` returned a root to every caller. `onGetRoot` now resolves the real `RemoteUserInfo`, cross-checks the callback package against `PackageManager.getPackagesForUid(uid)` (adding the binding identity AndroidX does not check) and permits only this app's UID or Android-trusted controllers, failing closed to `null`. The service stays exported so trusted Bluetooth/system integrations still work. The owner explicitly accepted the compatibility loss for untrusted car/controller apps. Regression: `BrowserClientPolicyTest` (4 host tests). Device/OEM integration not executed.

### BUG-201 [P2] [confidence: high] [RESOLVED]
- Location: `lib/providers/local_artist_provider.dart` (`localArtistPopularProvider` tie-break)
- Scenario: artist with <20 played songs; any scan/delete/edit bumps `loadedIndexVersion` → provider rebuilds → `random.nextDouble()` ties redrawn → unplayed Popular picks reshuffle while the page is open.
- Resolution: T7. Per-ID random priorities are kept in an autoDispose family cache that lives as long as the Popular page listens, so an index refresh reuses the original draws, deleted rows drop out and a newly indexed ID draws once. Ranking (play counts first, 20 cap), paging and the full-artist queue are unchanged; reopening the page draws afresh. Regression: `local_artist_popular_test.dart` (draw-counting refresh, delete, promote and dispose cases).

### BUG-202 [P2] [confidence: high] [RESOLVED]
- Location: `lib/providers/library_search_provider.dart`
- Scenario: Local Library disabled → search still returns local songs/albums/artists (`includeLocal: true` hard-coded; watched setting discarded).
- Resolution: T7. The watched setting is forwarded to `includeLocal`, and a disabled library returns no local hits without touching the index or database; user playlists remain searchable. Regression: `library_search_provider_test.dart` (songs/albums/artists empty with an index that throws on access, playlists still searched).

### BUG-302 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/services/batch_track_actions.dart` (`runBatchReplayGain`)
- Scenario: batch ReplayGain over a selection containing CUE virtual rows (single-track menu hides it) → virtual paths sent to the writer → inflated failure count; `catch (_) {}` hides reasons.
- Resolution: T7. Verified by trace. CUE virtual rows are filtered out before the confirmation totals and the loop (a CUE-only selection returns early with no dialog), and failures now log: a false write warns with the path, an exception logs with its stack. Regressions: `batch_track_actions_test.dart` (CUE-only, mixed local/SAF filtering, false-write logging, Back during a pending write).

### DEAD-604 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/player_artwork.dart` (`http` branch), `lib/providers/music_player_provider.dart` (`playableFromLocal`)
- Scenario: `http*` covers still render via `CachedCoverImage`, and `playableFromLocal` passes them through → legacy rows could fetch remote artwork (contradicts "no remote artwork loading").
- Resolution: T7. `CachedCoverImage` already rejected every non-file scheme, so no fetch was possible; the dead network branch is gone and a legacy `http` cover now renders the placeholder and is not published into playback state. Regression: `player_artwork_test.dart` (remote URL placeholder, `playableFromLocal` drops `http` and keeps a local path).

### UI-101 [P2] [confidence: high] [RESOLVED]
- Location: `lib/widgets/mini_player.dart` (`_MiniPlayerState._dismissedItemId`)
- Scenario: swipe-dismiss the mini player on track A → play A again → pause → `mediaItem.id == _dismissedItemId && !isPlaying` → bar disappears while A is current.
- Resolution: T7. The dismissal latch is cleared when the item is null, the id differs, or playback resumed after the bar was seen paused, so replaying the same track shows the bar again and pausing it later keeps it. It is also retained across the frames where an asynchronous stop still reports `playing`, which would otherwise rebuild the dismissed `Dismissible`. Regression: `mini_player_dismissal_test.dart` (six paused/playing × reset cases, including a delayed stop and a forced stale-playing rebuild).

### UI-201 [P2] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/batch_progress_dialog.dart` (`BatchProgressDialog.dismiss`); caller `lib/services/batch_track_actions.dart`
- Scenario: batch ReplayGain running → Android back pops the progress dialog (no `PopScope`; `barrierDismissible: false` does not block back) → loop continues with `cancelled == false` → `dismiss` pops the root navigator's top route, i.e. the Songs/album page.
- Resolution: T7 (also Codex FA-CONC-001). `show` now returns a dismissal callback that removes only its own captured route, Back is captured by `PopScope` and routed through the existing once-only cancel, an externally removed dialog cancels the batch, and a stale completion can no longer dismiss a newer dialog. Regressions: `batch_progress_dialog_test.dart` (Back, Settings covering the dialog, completion before the first frame, external removal, old callback versus new dialog).

### UX-201 [P2] [confidence: high] [RESOLVED]
- Location: `lib/screens/settings/cache_management_page.dart` (`_refreshOverview`, `build`)
- Scenario: `_buildOverview()` throws on first load → catch sets `_isLoading=false` and shows a snackbar, `_overview` stays null → `_isLoading || overview == null` keeps an endless spinner.
- Resolution: T7. A failed load is tracked and renders an `ErrorCard` with Retry instead of the spinner; Retry clears the error and shows progress again. Regression: `cache_management_error_test.dart` (failure on the cache path only, error card without spinner, Retry to a rendered overview).

### BUG-101 [P2] [confidence: high] [RESOLVED]
- Location: `lib/utils/lyrics_parser.dart:213-220` (`parse`), :758-765 (`_parseTtml`)
- Scenario: TTML with `<p>` but no usable `begin`, or no `<p>` → `_parseTtml` returns an untimed result (or null); `parse()` requires `lines.isNotEmpty`, falls through to `_parseLrcOrPlain(text)` on raw XML → plain text view shows XML markup.
- Root cause: untimed TTML result discarded.
- Impact: unsynced TTML lyrics (embedded or sidecar) render as raw XML.
- Fix: return `_withCredits(text, ttml)` when `ttml != null` and `plainText` is non-empty; ~3 lines + test.
- Evidence: guard at :215; untimed return at :758.
- Resolution: `e6276a6` (T6). Both parsers accept an untimed TTML result (lines empty, plain lyric text non-blank) instead of re-parsing the raw XML as LRC, which showed markup. Shared goldens `untimed TTML keeps plain lyrics` and `TTML invalid missing paragraph timing falls to plain` (expected updated from the raw XML) pin the behaviour in both suites.

### BUG-102 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/utils/lyrics_parser.dart:280-288` (`_withCredits`)
- Scenario: LRC with a trailing "Written by:" credit and multi-timestamp chorus lines → plainText rebuilt from expanded timed lines → chorus duplicated.
- Fix: remove the trailer from the existing plainText instead of rebuilding; ~3 lines.
- Resolution: `e6276a6` (T6). The trailer is dropped from the retained plain text (exact match of the popped credit's text first, credit-regex scan from the end only as fallback) instead of being rebuilt from lines, which duplicated chorus lines shared by timestamps. The Rust `with_credits` path had the same rebuild and was fixed for parity. Goldens `credit trailer keeps chorus once in plain text` and `multi-credit trailer keeps the retained credit in plain text`.

### BUG-103 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/utils/lyrics_parser.dart:415-436`
- Scenario: enhanced LRC `[00:10][01:30]<00:10>a<00:11>b` → repeated line shares word times of the first occurrence; word highlight wrong on repeats.
- Fix: shift word times per extra timestamp; ~10 lines.
- Resolution: `e6276a6` (T6). Verified by trace: repeated occurrences shared unshifted absolute word times on both parsers. Word timing is now anchored at the occurrence nearest the first word and each repeat replays the same relative timing (shifts clamp at zero). The existing golden `repeated line and empty end tags` was updated for the shifted repeat and a new golden pins the canonical case.

### RUST-401 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/mobile/src/native_lyrics.rs:111-139` (`execute`), :688-700, :790-826 (`parse_ttml`)
- Scenario: native (production) lyrics path has the same untimed-TTML discard as BUG-101 → raw XML shown as plain lyrics.
- Fix: accept TTML when lines or plain text are non-empty; ~3 lines; fix together with BUG-101 and update `test/fixtures/native_lyrics_parsers.json`.
- Evidence: `parseAsyncNative` is the live path (`lyrics_parser.dart:231`).
- Resolution: `e6276a6` (T6). Same fix as BUG-101 in `execute`; the shared fixture goldens cover both parsers (`shared_dart_parser_goldens`, `test/native_lyrics_parser_test.dart`).

### RUST-403 [P2] [confidence: medium] [RESOLVED]
- Location: `rust_backend/crates/mobile/src/native_lyrics.rs:~455-490` (`parse_lrc`)
- Scenario: one LRC line with K leading timestamps and W word tags clones the word list K times (K×W); a crafted ~700 KB line can exhaust memory → native abort when lyrics open. Dart parser has the same amplification.
- Fix: cap timestamps per line (e.g. 64) and total words; ~10 lines.
- Resolution: `e6276a6` (T6). Verified with a bounded release-build reproduction before the fix: a ~47 KB line with 2,000 timestamps and 2,000 word tags expanded to 2,001 lines in 7.0 s and 2.6 GB RSS (FA-RUST-001's craft would abort the app). Both parsers now cap timestamps per line at 64, words per line at 256, and charge a cumulative expanded-output budget of 16,777,216 units (word counts plus UTF-16 text lengths, charged once per duplicated line) beyond the first occurrence. Pinning tests assert identical arithmetic on both sides (exactly 16 lines for a 1 MB line with 70 timestamps).

### RUST-202 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/cue.rs:117-122` (`parse`, FILE), `CueTrack` :25-35; consumers `rust_backend/crates/local/src/backend/library.rs:232,284`, `scan.rs:446`
- Scenario: multi-FILE cue (one file per track: `FILE "01.flac"`/TRACK 01/INDEX 01 00:00:00, `FILE "02.flac"`...) → `sheet.file_name` overwritten per FILE; all tracks attributed to the last file with their own start times.
- Root cause: no per-track file field.
- Impact: wrong/zero durations and playback offsets; Split into Tracks cuts the wrong audio; no error shown.
- Fix: record file per track and resolve per track, or reject sheets with a second distinct FILE (~5 lines) + test.
- Evidence: assignment at :119; no multi-FILE test.
- Resolution: `8232af13` (T4). Reject a second distinct FILE explicitly: the current CUE DTO/playback contract has one backing file. No tracks can silently inherit the last FILE. Regression covers a two-file sheet.

### RUST-203 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/cue.rs:291-300` (`timestamp`), `rust_backend/crates/local/src/backend/library.rs:431-433` (`cue_library_rows`)
- Scenario: malformed INDEX ("xx:yy:zz") becomes 0.0; ff >= 75, negative values and out-of-order starts accepted → negative durations emitted to the library.
- Root cause: no validation; `unwrap_or(0)`.
- Impact: overlapping/zero-start tracks and negative durations without a parse error.
- Fix: `timestamp` returns Option, rejects ff >= 75 / ss >= 60 / negatives; clamp durations with `.max(0)`; ~10 lines + tests.
- Resolution: `8232af13` (T4). Parse timestamps with checked numeric components, reject invalid seconds/frames/negative values and out-of-order INDEX 01 starts, and clamp derived durations nonnegative. Malformed-index and valid-boundary regressions added.

### RUST-204 [P2] [confidence: medium] [RESOLVED]
- Location: `rust_backend/crates/core/src/cover/library.rs:53-60`, :71 (`library_thumbnail`)
- Scenario: cache mutex held across `resize` of untrusted embedded art; a decoder panic poisons it → every later call fails "thumbnail cache unavailable" until restart.
- Impact: all library covers disappear after one bad image.
- Fix: recover with `into_inner()` on `Poisoned`, or resize outside the lock; ~3 lines.
- Resolution: `8232af13` (T4). Injected poison-state regression confirms recovery without disabling later calls. Discard interrupted cache state, clear poison and retain cancellation polling. The test uses a private mutex so it cannot invalidate concurrent global-cache reuse tests; no claim that a particular malformed image panics.

### RUST-001 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/mobile/src/usb_audio/transport.rs:235, 268, 274, 278, 286, 294` (`completed`, `Slot::submit`, `success`, `actual`)
- Scenario: `submit` passes `self as *mut Slot` as libusb `user_data`, then writes `self.pending` through `&mut self`; later reborrows invalidate the raw pointer's provenance, so the callback's write is UB under Stacked/Tree Borrows. `iso_packet_desc.as_ptr()` on `[T; 0]` has zero-byte provenance.
- Root cause: shared completion flag stored inside a `&mut`-used struct.
- Impact: latent UB only; Opus review: no realistic miscompile today (pointer escapes to libusb, flag reloaded each loop).
- Fix: heap `AtomicBool` passed as `user_data` with `pending()` accessor; `addr_of_mut!(...).cast()` for iso descriptors; ~15 lines.
- Evidence: Opus escalation verdict (Sonnet → Opus).
- Resolution: `8232af13` (T4). libusb user_data now points to a separate heap AtomicBool retained until completion; Slot mutation no longer aliases callback state. Access flexible descriptors via raw field addresses, avoiding references to the zero-length array. Host callback regression covers completion after moving the slot. Miri/sanitizers/device USB execution NOT RUN.

### RUST-002 [P3] [confidence: low] [RESOLVED]
- Location: `rust_backend/crates/mobile/src/usb_audio/transport.rs:626-631` (`run`), :433-436 (`configure`), `descriptors.rs:247-264`
- Scenario: integer-nominal rates (48 kHz @125 µs = 6 frames) with feedback slightly above nominal occasionally need 7 frames; if `wMaxPacketSize` is exactly 6×frame, `run` fails "USB feedback exceeded endpoint capacity".
- Impact: USB bit-perfect playback aborts mid-track on DACs without packet headroom.
- Fix: clamp to endpoint capacity and carry the remainder; ~5 lines.
- Resolution: `8232af13` (T4). Validated the clock/capacity path with accepted 6.01-frame feedback against a six-frame endpoint. Bound each packet to endpoint capacity and carry unsent fractional/integer debt; the regression checks capacity and frame accounting without abort or discarded debt. Physical USB behavior NOT RUN.

### DATA-502 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/tags/library.rs:19-24` (`library_id`), used at :44 and `rust_backend/crates/local/src/backend/library.rs:421`; `lib/services/library_schema.dart:25` (`id TEXT PRIMARY KEY`)
- Scenario: track id = `lib_` + 32-bit DJB2 hash of the path; two distinct files with colliding hashes → `INSERT OR REPLACE` keeps only one row → the other track silently disappears from the library (birthday odds ≈1% at 10k tracks, ≈10% at 30k).
- Root cause: 32-bit hash used as a unique primary key.
- Impact: missing tracks with no error; collections/history entries keyed by that id can point at the wrong song.
- Fix: 64-bit+ hash (or path-based key with collision check) plus an id migration for library, collections and history references; medium, needs a design note.
- Evidence: hash body above; primary key in schema; `INSERT OR REPLACE` noted by storage/native reviewers.
- Resolution: `8232af13` (T4). New IDs are lib_v2_ plus the full SHA-256 of the UTF-8 path. Before publication, native import and Dart streamed/attached publication match exact source_id/file_path and retain the live ID, remapping staged path keys in the same transaction; single/batch upserts do likewise. Existing collection/history/backup keys therefore remain valid without eager ID rewriting or a schema change. Previously missing collision victims receive new IDs on rescan. Tests use two paths with an equal legacy DJB2 hash and verify retained IDs/path keys, including attached staging. Historical associations already corrupted by an old collision cannot be inferred from the hash alone.

### CONC-102 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/local/src/backend/cover.rs:124-136` (`cache_cover`)
- Scenario: cover cache file `cover_<32-bit hash of path|size|mtime>`; on collision the cache-hit path returns the other track's cover without checking the key.
- Impact: wrong artwork for a track, persistent until the cache is cleared (≈10% chance of some collision at 30k tracks).
- Fix: 64-bit or SHA-256-prefix filename (one-time cache invalidation); ~5 lines. Pair with DATA-502.
- Resolution: `8232af13` (T4). Versioned cover filenames now use a full SHA-256 key, invalidating collision-prone legacy cache hits. Existing capability locks plus staged publication already serialize same-key writers. Regression verifies old-hash-colliding keys return distinct covers and concurrent publication returns complete matching bytes.

### CONC-101 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/local/src/backend/library.rs:172-177` (`resolve_cue_audio`), `rust_backend/crates/core/src/tags/library.rs:14` (`library_extension` lowercases)
- Scenario: CUE `FILE` name whose extension changes byte length when lowercased (e.g. `İ` → 3 bytes) → `&name[..name.len() - suffix.len() - 1]` slices inside a UTF-8 character → panic during library scan.
- Root cause: slicing the original string with the lowercased suffix's length.
- Impact: scan aborts on an odd/crafted CUE (panic across FFI; mapping unverified).
- Fix: derive the stem with `rfind('.')` on the original name; ~3 lines + test.
- Resolution: `8232af13` (T4). Derive the CUE fallback stem from an original UTF-8 dot boundary, never the byte length of a lowercased extension. Resolve an exact case-insensitive filename before fallback, keeping capability checks and rejecting ambiguous case matches. CUE scan regression covers mixed-case FILE and Unicode İ suffixes.

### CONC-103 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/local/src/backend/library/scan.rs:363-371`, :392-399
- Scenario: a second scan swaps the shared progress slot before acquiring the owner lock → progress jumps to zero while the first unwinds.
- Fix: swap after acquiring `_owner`; ~6 lines.
- Resolution: `8232af13` (T4). A queued scan cancels the preceding run without replacing its progress slot until owner acquisition. Owner acquisition checks shutdown/request cancellation before waiting on pause, so a pre-paused first run remains visible to cancel/resume. Existing pause/cancel tests and a queued-owner progress regression pass.

### CONC-104 [P3] [confidence: medium] [RESOLVED]
- Location: `rust_backend/crates/local/src/redact.rs`, `rust_backend/crates/local/src/logging.rs` (`add_message`)
- Scenario: redaction covers credentials/tokens only; absolute paths, `content://` URIs and folder names stay in shareable logs.
- Fix: product decision: redact on share or document it.
- Resolution: `8232af13` (T4). Confirmed paths/content URIs remain useful diagnostic data. Chose the documented-export option: both log export headers and selected-log sharing disclose local file paths, folder names and content URIs and ask the user to review before sharing. Credential redaction remains unchanged. Export notice regression added.

### RUST-301 [P3] [confidence: medium] [RESOLVED]
- Location: `rust_backend/crates/mobile/src/native_library.rs:617-619` (`snapshot`)
- Scenario: a library row whose path contains `\n`/`\r` makes every `library_snapshot` fail → incremental scans of that source never succeed (Dart fallback not traced).
- Fix: skip/flag such rows or reject them at import; ~3 lines.
- Resolution: `8232af13` (T4). Confirmed an unrepresentable TSV row aborted snapshot creation. Skip CR/LF paths in the snapshot while retaining their database rows, so other paths can scan and omitted files are eligible for refresh. Regression verifies a normal row exports while a newline row remains stored.

### FA-DATA-009 [P2] [confidence: high] [RESOLVED]
- Source: `fresh-audit-2026-10-23/07-scanner-database.md` DATA-009; mapped in TASKS.md T4.
- Resolution: `8232af13`. Require a .cue base and an exact trailing numeric #track suffix. Real song#track2.wav paths remain physical; incremental scan regression confirms no false deletedPaths. Completes the Rust counterpart of T2 SEC-003.

### FA-DATA-010 [P2] [confidence: high] [RESOLVED]
- Source: `fresh-audit-2026-10-23/07-scanner-database.md` DATA-010; mapped in TASKS.md T4.
- Resolution: `8232af13`. Local incremental scans conservatively re-read CUE dependencies even when the sheet timestamp matches: the existing snapshot has no persisted backing-audio version. A same-size FLAC replacement with changed sample count refreshes duration while the sheet stays untouched. This trades some repeated CUE work for correctness.

### FA-DATA-013 [P2] [confidence: high] [RESOLVED]
- Source: `fresh-audit-2026-10-23/21-tag-library-identity.md` DATA-013; mapped in TASKS.md T4.
- Resolution: `8232af13`. Duplicate of DATA-502. Collision-resistant new IDs and same-source/path retention keep existing references stable; legacy-hash collision regression passes.

### DATA-301 [P2] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/local_song_menu.dart:256-282` (`editLocalSongMetadata`), `lib/controllers/metadata_editor_controller.dart:54`
- Scenario: `PlatformBridge.readFileMetadata` returns `{error: ...}` (no throw) on a transient SAF/IO failure → form prefilled from the DB, `comment`/`album_type`/`upc`/`lyrics` become `''` → user edits only the title → save sends empty values, which clear those tags.
- Root cause: prefill ignores `tags['error']`; fields the DB does not hold are submitted as clears.
- Impact: silent loss of embedded lyrics, comment, release type and UPC.
- Fix: abort with a snackbar when `tags['error'] != null`, or send only dirty fields; ~5 lines + test.
- Evidence: only thrown errors are caught (:258-261); `val()` falls back to DB or `''`.
- Resolution: `4dcb1f9b` (T3). The editor submits only dirty fields, so failed prefill cannot clear unseen tags; paired track/disc totals remain coherent. Controller and persistence regressions cover partial requests.

### DATA-302 [P2] [confidence: high] [RESOLVED]
- Location: `lib/services/ffmpeg_metadata.dart:180-195` (`embedMetadataToMp3`)
- Scenario: tag-only edit on an MP3 whose stream copy reports "Invalid audio stream"/"incorrect codec parameters" (native MP3 editor already failed) → audio silently re-encoded with `libmp3lame -b:a 192k` and the original replaced.
- Root cause: conversion-era retry kept in the tag-write path.
- Impact: lossy, quality-reducing rewrite of the user's file (320k/VBR downgraded) without consent.
- Fix: fail with `MetadataSaveFailure.ffmpeg` instead of re-encoding; ~10 lines removed + test.
- Evidence: code above; reached via `save()` → `_embed` when tags.rs returns `method: "ffmpeg"`.
- Resolution: `4dcb1f9b` (T3). MP3 edits never re-encode audio. Preservation requests refuse FFmpeg fallback after native refusal, retaining unsupported frames and the original audio.

### DATA-306 [P2] [confidence: medium] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafIo.kt:347`, :414 (`writeUriFromPath`); Dart callers `MetadataPersistenceService.writeBack`, `ReplayGainService._updateFile`
- Scenario: SAF write-back opens the original with mode `"wt"` (truncates immediately) then streams the temp copy; IO error, full storage or process death mid-copy leaves the only copy truncated; temp is deleted in `finally`.
- Root cause: non-atomic write-back and unconditional temp deletion.
- Impact: rare but total loss of a music file during SAF tag edit or ReplayGain.
- Fix: check free space/size first; keep the temp on failure and surface a retry; ~15 lines Kotlin.
- Evidence: `openOutputStream(uri, "wt")` at :347 and :414.
- Resolution: `4dcb1f9b` (T3). Back up before truncation; compare backup length with known original size, verify replacement length and verify rollback before deleting recovery. Failed or unverifiable rollback retains the original backup and reports its path. Host policy tests inject short writes and errors; actual provider/device failure injection NOT RUN.

### DATA-303 [P2] [confidence: medium] [RESOLVED]
- Location: `lib/services/ffmpeg_metadata.dart:375-379` (`embedMetadataToM4a`)
- Scenario: M4A edit on the FFmpeg fallback: explicit/`album_type`/`upc`/compilation are written only by `writeM4AReleaseIdentityTags`, whose bool result is ignored; `writeM4AFreeformTags` swallows errors → "saved" while the file is unchanged; UI reverts after re-read. FFmpeg mov muxer also drops unknown freeform atoms (ISRC, ReplayGain) without `-movflags use_metadata_tags`.
- Root cause: post-FFmpeg native write failures not propagated; freeform atoms not preserved.
- Impact: false success; untouched freeform tags lost on the fallback path.
- Fix: return failure when the identity write returns false; add `-movflags use_metadata_tags`; ~4 lines.
- Evidence: unused return value at :378.
- Resolution: `4dcb1f9b` (T3). Confirmed the fallback publication path could lose freeform atoms. Preservation requests now require the native atom editor and fail without modifying the original; explicit non-preserving operations check native post-processing before promotion.

### DATA-304 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/services/replaygain_service.dart:158-170`, `lib/services/ffmpeg_replaygain.dart:188`
- Scenario: native ReplayGain writer fails → FFmpeg `-map 0 -c copy` fallback promotes over the original, then verification runs; for M4A the muxer dropped the atoms → reports failure, but the local file is already rewritten minus freeform tags.
- Root cause: verify after publish.
- Impact: failed apply leaves a modified file with lost custom tags.
- Fix: skip the FFmpeg fallback for .m4a/.mp4/.m4b (like Opus) or verify the temp before promoting; ~3 lines.
- Evidence: reviewer trace.
- Resolution: `4dcb1f9b` (T3). Confirmed the M4A stream-copy fallback could replace the file before verification. M4A/MP4/M4B ReplayGain now requires native writing, as Ogg/Opus already did.

### BUG-104 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/services/id3v23_lyrics.dart:137-161` (`_removeFrames`)
- Scenario: existing ID3v2.3 tag has a zero-size/invalid/overrunning frame → `break` drops every later frame (e.g. APIC) when lyrics are written.
- Impact: cover/tag loss with non-conforming taggers (low exposure: FFmpeg rewrites the tag just before).
- Fix: preserve the remaining payload verbatim or return null to leave the file unchanged; ~5 lines.
- Resolution: `4dcb1f9b` (T3). The Dart USLT writer refuses malformed/nonzero trailing frames and leaves the file untouched. Regression fixtures retain later artwork instead of truncating it.

### DATA-401 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/audio_analysis_widget.dart:913`, :941-963; `lib/services/audio_analysis_cache.dart`
- Scenario: cache key = path hash, validated by `fileSize` only (SAF size 0 skips check) → same-size replacement serves stale analysis.
- Fix: store and compare modified time; ~8 lines.
- Resolution: `4dcb1f9b` (T3). Confirmed that size-only cache validation missed equal-size replacements. Cache v14 records and compares modification time for local/SAF files when available; older caches invalidate. Timestamp serialization regression added. Providers without usable size/time remain a limitation.

### DATA-402 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/library_cover_snapshot.dart:34-45`, `rust_backend/crates/mobile/src/native_cache/unix.rs:353-359`, `lib/services/library_schema.dart:15`
- Scenario: schema version 17 is hard-coded in three places; bumping `LibrarySchema.version` breaks cover pruning (orphan covers accumulate).
- Fix: use `LibrarySchema.version` and pass it to Rust, or a test asserting all three agree; ~5 lines.
- Resolution: `4dcb1f9b` (T3). Use LibrarySchema.version for snapshots and pass schema_version in the native pruning request, with a legacy native default. Snapshot/channel tests assert the shared version.

### RUST-101 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/tags/id3.rs:404-407` (`decode`), :489 (`v1`), :296 (`picture_frame`); `rust_backend/crates/core/src/text.rs:3` (`utf8`)
- Scenario: ID3v1/v2.2/v2.3 text in ISO-8859-1 (encoding 0, e.g. "Beyoncé" with 0xE9) → decoded as lossy UTF-8 → "Beyonc\u{FFFD}"; UTF-16 surrogate pairs (emoji) become two U+FFFD.
- Root cause: encoding 0 routed through UTF-8 (Go-parity decoder); no `decode_utf16`.
- Impact: corrupted titles/artists/albums for older/Windows-tagged MP3s; saving writes the replacement characters back permanently.
- Fix: Latin-1 for encoding 0 when not valid UTF-8; `char::decode_utf16`; ~15 lines; update Go-parity tests.
- Evidence: `decode` and `utf8` bodies; reached from `read_tags` "mp3" branch (tags.rs:208).
- Resolution: `4dcb1f9b` (T3). Decode Latin-1 text and UTF-16 surrogate pairs correctly; retain compatibility with valid UTF-8 tagged as encoding zero. Reader regressions cover accents and emoji.

### RUST-102 [P2] [confidence: medium] [RESOLVED]
- Location: `rust_backend/crates/core/src/tags/write/id3.rs:278-300` (`read_frames`), :71-80 (`edit_header`)
- Scenario: (1) a zero-length or bad-size frame → `break`, Ok with frames so far → rewritten tag drops every later frame (APIC, TXXX, POPM); reader errors on the same input. (2) compressed/encrypted v2.3/v2.4 frames and unknown v2.2 IDs dropped. (3) every save replaces all COMM and USLT frames (editor always sends comment/lyrics), including iTunSMPB/iTunNORM and other-language lyrics. (4) zero-length tag header returns Err, pushing Dart to the FFmpeg fallback (DATA-302).
- Root cause: lossy rewrite that fails silently on frames it cannot re-emit.
- Impact: loss of untouched artwork/metadata and gapless info in MP3s with slightly malformed tags.
- Fix: copy remaining raw bytes or return Err instead of truncating; drop only COMM with empty descriptor and same language; pass through encrypted frames raw; ~30 lines + tests. Related: BUG-104 (Dart USLT writer has the same `break` pattern).
- Evidence: `break` at :298-300.
- Resolution: `4dcb1f9b` (T3). Refuse unsupported/truncated frames; handle empty tags and version-specific extended headers; preserve unrelated COMM/USLT descriptions and languages. UTF-16 BOM descriptions and v2.4 unsynchronization have regressions. MP3 fallback cannot bypass refusal.

### RUST-103 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/tags/id3.rs:302` (`picture_frame`), `rust_backend/crates/core/src/tags/write/id3.rs:182-186` (`cover`)
- Scenario: UTF-16 APIC description terminator found with unaligned `windows(2)` → image offset wrong by one → corrupt cover (re-embedded for RIFF/AIFF).
- Fix: aligned search like `separator()`; ~5 lines.
- Resolution: `4dcb1f9b` (T3). Find UTF-16 APIC description terminators on code-unit boundaries; cover extraction regression checks exact image bytes.

### RUST-104 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/tags/comments.rs:18-22`, `containers.rs:291`, `write/ogg.rs:109-117`, `write.rs:737`
- Scenario: writer accepts Ogg covers up to 16 MB (≈21 MB base64) but reader caps 10 MB → covers above ~7.4 MB written then read back as missing; reader processes only the first 100 Ogg comments (ReplayGain/R128/picture beyond that ignored).
- Fix: align limits; bound by bytes, not count.
- Resolution: `4dcb1f9b` (T3). Remove the 100-comment cap and allow picture comments large enough for the writer limit. Regressions cover later comments and an 8 MiB cover with a base64 comment above 10 MB.

### RUST-105 [P3] [confidence: medium] [RESOLVED]
- Location: `rust_backend/crates/core/src/tags/write/riff.rs:46, 94-96, 152`, `write/ape.rs:19-40`, `write/mp4.rs:138`, `tags/mp4.rs:45`
- Scenario: WAV/AIFF ID3 chunk rebuilt only from parsed fields (TXXX/unknown/extra APIC lost; odd final chunk without pad fails save); APE edit deletes trailing ID3v1; MP4 `number as u16` wraps; `covr` type 13 for non-JPEG; legacy rtng 4 not read as explicit.
- Fix: individually small; batch with RUST-102.
- Resolution: `4dcb1f9b` (T3). Confirmed container-specific loss paths. Reuse retained ID3 frames for WAV/AIFF, accept an unpadded final odd chunk, preserve trailing APE ID3v1, clamp MP4 indices, reject unsupported MP4 cover types and recognize legacy explicit rating 4. Container regressions cover preservation, index bounds and rejected artwork.

### RUST-106 [P3] [confidence: medium] [RESOLVED]
- Location: `rust_backend/crates/core/src/tags/write.rs:403-407`, :737-776 (`picture`)
- Scenario: replacement cover >16 MB that cannot be shrunk → `picture()` Ok(None) after old pictures were removed → save succeeds, artwork gone; oversize decode uses image crate default 512 MB limit.
- Fix: return Err or keep old pictures; set `image::Limits`.
- Resolution: `4dcb1f9b` (T3). Rejected/oversized replacement artwork now returns an error before publishing output. Bound decoded dimensions; full FLAC regression preserves the existing source and emits no replacement on rejection.

### RUST-402 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/mobile/src/native_id3.rs:155-170` (`make_tag`, from `write_lyrics`)
- Scenario: zero-size, oversize or invalid-ID frame → `break`, later frames (APIC, TXXX) dropped, `committed: true`.
- Impact: silent cover/tag loss when USLT is written to an MP3. Same pattern as BUG-104 (Dart) and RUST-102 (tag writer).
- Fix: if non-zero bytes remain after `break`, return `Ok(false)` (file untouched); skip size-0 frames; ~10 lines + test. Batch with RUST-102/BUG-104.
- Resolution: `4dcb1f9b` (T3). Native USLT writing refuses malformed/truncated frame tails and preserves untouched metadata; native regression fixtures cover malformed frames and UTF-16 lyrics.

### FA-DATA-001 [P1] [confidence: high] [RESOLVED]
- Source: `fresh-audit-2026-10-23/04-metadata-integrity.md`, DATA-001; mapped in TASKS.md T3.
- Resolution: `4dcb1f9b`. Same destructive SAF publication as DATA-306; verified backup/rollback and retained recovery now protect both native and fallback callers.

### FA-DATA-002 [P2] [confidence: high] [RESOLVED]
- Source: `fresh-audit-2026-10-23/04-metadata-integrity.md`, DATA-002; mapped in TASKS.md T3.
- Resolution: `4dcb1f9b`. Version-specific ID3v2.4 extended-header sizing preserves private frames; dedicated regression added.

### FA-DATA-003 [P2] [confidence: high] [RESOLVED]
- Source: `fresh-audit-2026-10-23/04-metadata-integrity.md`, DATA-003; mapped in TASKS.md T3.
- Resolution: `4dcb1f9b`. Invalid oversized FLAC replacement fails before publication; full rewrite regression leaves existing source/artwork intact.

### FA-DATA-004 [P2] [confidence: high] [RESOLVED]
- Source: `fresh-audit-2026-10-23/04-metadata-integrity.md`, DATA-004; mapped in TASKS.md T3.
- Resolution: `4dcb1f9b`. Same WAV/AIFF frame-loss path as RUST-105; edit retained raw ID3 frames instead of rebuilding from parsed fields.

### FA-DATA-005 [P2] [confidence: high] [RESOLVED]
- Source: `fresh-audit-2026-10-23/04-metadata-integrity.md`, DATA-005; mapped in TASKS.md T3.
- Resolution: `4dcb1f9b`. Clearing APE date removes DATE and YEAR case-insensitively; regression preserves title/audio/trailing ID3v1.

### UX-221 [P3] [confidence: high] [RESOLVED]
- Location: `lib/constants/language_choices.dart`, `lib/screens/settings/appearance_settings_page.dart` (Language)
- Scenario: "System Default" is hard-coded English in Appearance (setup localizes it).
- Fix: map `system` to `l10n.setupLanguageSystemDefault`; ~4 lines.

- Resolution: REMOVED with the Appearance Language option (owner: English only, 2026-10-23).

### UX-204 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/setup_screen.dart:657-709` (`_buildLanguageList`)
- Scenario: language rows expose selection only by a check icon; no `Semantics(selected:)` → TalkBack does not announce the active language.
- Fix: `Semantics(selected: isSelected, button: true)`; ~3 lines.

- Resolution: REMOVED with the setup language step (owner: English only, 2026-10-23).

### UX-238 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/app_snack_bar.dart` (3 s cap)
- Scenario: every snackbar is capped at 3 s, overriding the 6 s restore hint and the 8 s USB volume warning. Product decision: honour longer durations or keep the cap.

- Resolution: FIXED in 23b1b46: longer-than-default snackbars keep their time up to 8 s; others still close within 3 s (owner decision 2026-10-23).

### UX-227 [P3] [confidence: high] [RESOLVED]
- Location: `lib/constants/language_choices.dart` (`('pt_PT', 'Português (Brasil)')`), `lib/l10n/supported_locales.dart` (`Locale('pt', 'PT')`, `'pt_PT'`), `lib/l10n/arb/app_pt_PT.arb`
- Scenario: the label says Brazil, but the locale code is Portugal. The translation itself is Brazilian Portuguese (it uses "arquivo", "você", "tela" and "configurações").
- Owner decision (2026-10-23): the translation is Brazilian, so keep the label "Português (Brasil)".
- Fix: change the locale code to `pt_BR`: rename the arb file, update `supported_locales.dart` and `language_choices.dart`, and migrate a saved language of `pt_PT` to `pt_BR` so existing users and old backups keep their choice. Regenerate the l10n files with the repo tooling.

- Resolution: FIXED in 23b1b46: locale code renamed to pt_BR with pt_PT migration (owner decision 2026-10-23).

### UX-105 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/local_album_screen.dart:402`, `lib/widgets/track_detail_actions.dart:54`
- Scenario: hard-coded English `min` in album header and list footer in every locale.
- Fix: l10n key (e.g. `durationMinutes`) + ARB entries; ~6 lines.
- Resolution: FIXED before 8e11147: track_detail_actions uses listeningStatsMinutes and the album header no longer prints minutes (UI audit re-check 2026-10-23).

### UX-103 [P3] [confidence: low] [RESOLVED]
- Location: `lib/screens/local_artist_screen.dart:547-548` (`rowHeight`)
- Scenario: at ~2.0× font scale the fixed row height (92px) is smaller than the ListTile content (~104px) → Popular rows clip/overflow. Arithmetic only.
- Fix: derive height from scaled title/subtitle line heights or use a min-height row; ~3 lines.
- Resolution: FIXED before 8e11147: Popular rowHeight now scales with text (64 + extra scaled line height); fits to about 2x (UI audit re-check 2026-10-23).

### UI-102 [P3] [confidence: low] [RESOLVED]
- Location: `lib/widgets/player_lyrics.dart:764-766,904-907`, `lib/widgets/player_lyrics_section.dart:82`
- Scenario: RTL locale with `TextAlign.start` lines → scale origin `Alignment.centerLeft`, gap dots `centerLeft`, options button `Positioned(left:)` sit on the physical left while text hugs the right.
- Fix: `AlignmentDirectional.centerStart` / `PositionedDirectional(start:)`; ~5 lines. Not run under RTL.
- Resolution: FIXED before 8e11147: lyrics and landscape player use AlignmentDirectional/PositionedDirectional (UI audit re-check 2026-10-23).

### DEAD-001 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/ffmpeg_decryption.dart` (169), `FFmpegService.decryptWithDescriptor` (`ffmpeg_service.dart:46-57`), `DownloadDecryptionDescriptor` (`ffmpeg_models.dart`), `FFmpegExecution.command`, `FFmpegOutput.plan`, `FFmpegMetadata.embedMetadata`/`FFmpegService.embedMetadata`, `FFmpegMetadata.embedChunkTagsNative`, `returnTempPath`/`onTempReady` params of ReplayGain writers
- Scenario: download-era decryption and conversion-era helpers with no production callers.
- Impact: ~250 lines + `test/ffmpeg_decryption_output_test.dart` (215) and part of `test/maintainability_contracts_test.dart`.
- Fix: delete; trim tests.
- Evidence: `grep -rln` over lib/ test/ finds only definitions, self-references and tests.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-002 [P3] [confidence: high] [RESOLVED]
- Location: `lib/utils/ffmpeg_reenrich.dart` (145), `lib/utils/re_enrich_result.dart` (51), `lib/utils/re_enrich_release_policy.dart` (8), `lib/utils/lyrics_metadata_helper.dart` (209: `cleanLyricsForDisplay`, `hasUsableLyricsContent`, `hasEmbeddedLyricsMetadata`, `isInstrumentalLyricsMarker`, `mergePlatformMetadataForTagEmbed`, sidecar writers), `PlatformBridge.writeSafSidecarLrc` (`platform_bridge.dart:830`)
- Scenario: online re-enrich/lyrics flow removed; nothing calls `applyFfmpegReEnrichResult`; the helpers are reachable only from it or tests.
- Impact: ~410 lines + tests (`re_enrich_result_test`, `re_enrich_release_policy_test`, helper tests), likely orphan `trackReEnrich*` l10n keys and native `write_external_lrc`.
- Fix: delete with tests, plus the `writeSafSidecarLrc` Kotlin handler (`MainActivity.kt:1447`); keep `writeTempToSaf` (live callers in replaygain/metadata persistence); check l10n keys in the dead-code sweep.
- Evidence: `grep -rln` per symbol over lib/.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-003 [P3] [confidence: high] [RESOLVED]
- Location: `lib/utils/cover_art_utils.dart` (`highResCoverUrl`), `lib/widgets/cached_cover_image.dart:136,149` (`urlTransform`), callers `library_tracks_folder_screen.dart:530,566`
- Scenario: Spotify/Deezer CDN URL rewrite passed as `urlTransform`, which `LocalCoverImage` never reads.
- Impact: dead remote-artwork code (~30 lines + test).
- Fix: delete the file/test, the parameter and its two uses.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-004 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/downloaded_embedded_cover_resolver.dart:210` (`scheduleRefreshForPath`), :232 (`invalidate`), `_pendingRefresh` branches
- Scenario: no non-test callers; staleness is handled by the mod-time poll. Class name/comments still say "downloaded"/"online fallback".
- Impact: ~50 lines dead API; misleading naming.
- Fix: remove dead methods; fix comments; rename if cheap.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-201 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/platform_bridge.dart:268` (`prepareRuntimeState`), :277 (`setDownloadDirectory`), :305 (`buildFilename`), :316 (`sanitizeFilename`); `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:917`, :925; `CoreBackend.kt:13-14`
- Scenario: no `PlatformBridge.` callers; native branches for buildFilename/sanitizeFilename unreachable (not in `nativeBackendMethods`), others have no handler.
- Fix: delete wrappers, branches and interface members (~40 lines). (`SettingsNotifier.setDownloadDirectory` is a different symbol — see UX-003.)
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-202 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/platform_bridge.dart:415, 429, 494, 510, 528, 563, 688, 776, 792, 808` (`resolveSafFile`, `inspectSafFiles`, three `create*SafFile*` variants, `shareMultipleContentUris`, `checkHiResAuthenticity`, `ensureAC4Config`, `writeAC4Metadata`, `rewriteSplitArtistTags`) and their MainActivity handlers
- Scenario: download/conversion-era wrappers with zero callers; native handlers unreachable.
- Fix: remove wrappers, handlers and CoreBackend members in one batch; keep `writeM4AFreeformTags` and `safCreateFromPath`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-203 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/platform_bridge.dart:574, 591, 607, 658` (`getLyricsLRC`, `getLyricsLRCWithSource`, `embedLyricsToFile`, `fetchAndSaveLyrics`); `android/app/src/rust/kotlin/com/zarz/spotiflac/SelectedCoreBackend.kt:34-54`, :390-406
- Scenario: Embed lyrics and fetch-and-save were removed (AGENTS.md) but remain wired end to end; no `lib/` callers.
- Fix: delete wrappers, Kotlin branches and plumbing; update tests.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-206 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/platform_bridge.dart:223, 333-339`; `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:965-970`; `android/app/src/main/kotlin/com/zarz/spotiflac/SetupFolderPickerStore.kt`
- Scenario: setup folder step removed; native still persists `for_setup` picks and emits `setupFolderSelectionChanged`; nothing reads it.
- Fix: remove Dart members, handlers, `for_setup` branch and the store (~60 lines).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-207 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/platform_bridge.dart:1167-1230` (iOS bookmark/directory methods), `lib/widgets/ios_library_folder_sheet.dart`, `lib/providers/local_library_provider.dart:636-644, 917, 1586-1608`, `lib/screens/settings/library_settings_page.dart:150`
- Scenario: Android-only project (no `ios/`); methods have no handler.
- Fix: remove iOS methods, sheet and branches (~150 lines); include `migrateIosContainerPaths`, `lib/utils/ios_container_paths.dart` in the dead-code sweep.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-208 [P3] [confidence: high] [RESOLVED]
- Location: `android/app/proguard-rules.pro:48-53`
- Scenario: keep rules for nonexistent `DownloadService` and `DownloadQueueWidgetProvider`.
- Fix: delete both blocks; update the stale comment in `NativeReplayGainPolicy.kt:4` (see KT-001).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. Kept independently owned haptic/decoder SAF jobs. Removed orphan resource-pool types only.

### DEAD-301 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/isrc/**` (931 lines), `rust_backend/crates/local/src/files/index.rs` (~110), `pub mod isrc` in `core/src/lib.rs`
- Scenario: ISRC duplicate index (`IndexCache`, `IndexFiles`, `NativeFiles`, `read_isrc`) has no consumer outside its own tests.
- Fix: delete (~1,050 lines).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-302 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/lyrics/models.rs`, `lyrics/matching.rs`, `lyrics/json.rs`, parts of `lyrics.rs` and `lyrics/lrc.rs`, `core/src/metadata.rs`, `core/src/matching.rs` (`normalize`, `compare_*`)
- Scenario: online lyrics provider schemas (Netease/Apple/QQ/Kugou/Genius/Spotify/YouTube) and matching with zero callers.
- Fix: delete (~1,000 lines); keep `lowercase`/`uppercase`, `lyrics::file::{extract,sidecar}`, `lrc::has_usable_content`; check internal dependencies first.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-303 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/filename/**` (565), `rust_backend/crates/core/src/filename.rs` (99), `rust_backend/crates/mobile/src/filename.rs`, `rust_backend/crates/mobile/src/lib.rs:25-27`, `SelectedCoreBackend.kt:411-414`
- Scenario: Rust side of DEAD-201 (download filename templating).
- Fix: delete with DEAD-201 (~700 lines); regenerate uniffi bindings.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-304 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/local/src/backend/lyrics.rs` (~190), `rust_backend/crates/mobile/src/lyrics.rs` (~75)
- Scenario: Rust side of DEAD-203 (embed/fetch lyrics); only integration test and mocks reach it.
- Fix: delete with DEAD-203; update `integration_test/lyrics_file_access_test.dart`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-401 [P3] [confidence: high] [RESOLVED]
- Location: `lib/models/settings.dart` (`albumFolderStructure`, `hasSearchedBefore`, `embeddedCoverMaxDimension`), `lib/providers/settings_provider.dart:89-95, 241-243, 275-277, 317-322, 459-464, 477-480`
- Scenario: download-era settings with no readers outside settings files; `artistTagMode` has no setter.
- Fix: delete (~40 lines); old JSON still loads.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-402 [P3] [confidence: high] [RESOLVED]
- Location: `lib/models/track.dart:236-262` (`ServiceAvailability`), `Track.deezerId`/`spotifyId` fallbacks :107-111
- Scenario: provider-era model (tidal/qobuz/amazon/deezer) with no references.
- Fix: delete and regenerate; check `deezerId` users first.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-403 [P3] [confidence: high] [RESOLVED]
- Location: `lib/models/download_history.dart:257` (`DownloadHistoryState`), `DownloadHistoryItem.storageMode/downloadTreeUri`
- Scenario: `DownloadHistoryState` unused; the rest ties into history DB columns and backups.
- Fix: delete `DownloadHistoryState` now; history schema cleanup is a separate decision (see API-001).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-501 [P3] [confidence: high] [RESOLVED]
- Location: `lib/utils/provider_resource_ids.dart`
- Scenario: provider-era helpers referenced only by their test.
- Fix: delete file and test; then check `lib/constants/music_services.dart`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-502 [P3] [confidence: high] [RESOLVED]
- Location: `lib/utils/ttl_cache.dart`, `chunked_list.dart`, `periodic_async_task.dart`, `cache_byte_budget.dart`
- Scenario: not imported in `lib/`; tests only (ChunkedList: nowhere).
- Fix: delete with tests; check `native_cache_maintenance.dart` afterwards.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-503 [P3] [confidence: high] [RESOLVED]
- Location: `lib/utils/audio_format_utils.dart` (quality-variant filename helpers, `resolveDisplayQuality`, `finalizedAudioFileName`, `estimateAverageBitrateKbps`, etc.), `lib/utils/string_utils.dart` (`formatMegabytes`, `shortMonthNames`, `isPlaceholderQualityLabel`), `lib/utils/artist_utils.dart` (`primaryArtistName`)
- Scenario: download/quality-variant naming logic with zero `lib/` callers.
- Fix: delete the group; keep `buildLibraryAudioQualityLabel`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-504 [P3] [confidence: high] [RESOLVED]
- Location: `lib/utils/editorial_notes.dart:15` (`albumDescriptionFromMetadata`)
- Scenario: referenced only by `test/album_description_test.dart`.
- Fix: delete with its test.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### UX-104 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/home_search_logic.dart` (Spotify URL/URI detection), `lib/screens/track_history_snapshot.dart` + `historyRequest` (`library_tracks_folder_data.dart:13`), `lib/widgets/track_list_tile.dart`, `lib/widgets/track_collection_quick_actions.dart`, `lib/widgets/track_collection_action_policy.dart` (`downloadAnotherQuality`), `loveAllTracks` (`track_detail_actions.dart:80`)
- Scenario: no production callers; tests only. Provider/download-era leftovers.
- Fix: delete with their tests (~400 lines) via the graphify feature-removal workflow. Fold into the final dead-code sweep.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-601 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/material_player_layout.dart`, `lib/widgets/player_queue_sheet.dart`, `lib/widgets/expressive_seek_track.dart`, and `!isMornye` branches in `now_playing_screen.dart`, `player_playback_controls.dart`, `mini_player.dart`, `player_details_sheet.dart`, `player_lyrics.dart`
- Scenario: `MornyeThemeWrapper` always builds Mornye (`mornye_theme_wrapper.dart:19,27`), so these are reachable only from dead `!isMornye` paths.
- Fix: delete (never restore Material Expressive); update `test/expressive_seek_track_test.dart`, `test/now_playing_lyrics_transition_test.dart`. `PlayerPlaybackModeButton` goes with the queue sheet. Final dead-code sweep.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-602 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/smoothed_progress.dart`
- Scenario: download-era progress smoother; zero references in lib/ and test/.
- Fix: delete.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-603 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/view_queue_snackbar_action.dart`
- Scenario: no lib/ callers; only `test/app_snack_bar_test.dart`, `test/shell_navigation_service_test.dart`.
- Fix: delete and trim the tests.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-611 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/queue_tab.dart:980-988`, `queue_tab_filter_widgets.dart:64-69,261-309`, `queue_tab_collection_items.dart:199-213`, `queue_tab_widgets.dart` (`_FilterChip`)
- Scenario: in Mornye, overview `QueueTab` always returns `MornyeLibraryScreen` → filter-mode PageView, `_FilterChip`, track grid/pinch resize and `collectionEntries` rows are dead; Songs rows wrap `LibraryPlaylistDragSource` with no `DragTarget` on screen (inert long-press drag).
- Fix: remove after checking widget tests that build a non-Mornye overview.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-631 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/animation_utils.dart` (`TrackListSkeleton`, `ArtistHeaderActionsSkeleton`, `ArtistScreenSkeleton`, `HomeSearchSkeleton`, `SkeletonCrossfade`, `DownloadSuccessOverlay`)
- Scenario: no lib/ caller outside the file (~600 of 1197 lines); download/home-search leftovers.
- Fix: delete them and their private-only helpers; keep `StaggeredListItem`, `AlbumTrackListSkeleton`, `AnimatedSelectionCheckbox`, `AnimatedBadge`, `slidePageRoute`, `ShimmerLoading`, `SkeletonBox`; trim tests.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. TrackListSkeleton remains: new artist/library loading screens use it. Only orphan skeletons/overlays retired.

### DEAD-632 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/cached_cover_image.dart:302-378` (`resolveMetadataArtworkSource`, `metadataBackdropCacheExtent`, `precacheMetadataBackdrop`, `precacheCoverImage`)
- Scenario: helpers of the removed details route, incl. http/`remoteCoverUrl` branches; tests only.
- Fix: delete with `test/cached_cover_decode_test.dart` / `test/downloaded_embedded_cover_resolver_test.dart` cases; keep `cachedCoverImageProvider`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-633 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/theme/material_expressive.dart:8` (`materialExpressiveEnabled`, `MaterialExpressiveScope`) and branches in `expressive_button`, `expressive_icon_button`, `expressive_navigation_bar`, `app_switch`, `app_loading_indicator`, `app_content_card`, `app_choice_chip`, `settings_group`; `ExpressiveNavigationBar` only at `main_shell.dart:773` (non-Mornye arm)
- Scenario: `materialExpressiveEnabled` is `!isMornye && …` and Mornye is always installed → expressive branches never run; `material_3_expressive`/`material_ui` packages kept for dead code.
- Fix: collapse callers to the non-expressive branch, delete the scope/helper/nav bar, then drop the packages if unused (cleanup, not restoration). Pair with DEAD-601.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-621 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/donate_icons.dart`, `priority_settings_scaffold.dart`, `reorderable_priority_item.dart`, `discard_changes_dialog.dart`
- Scenario: no use in lib/ or test/ outside the files (~500 lines); download/provider-priority/donate leftovers.
- Fix: delete, plus arb keys that become unused (e.g. `dialogDiscardChanges`).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-622 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/main_shell.dart` (`SlidingIcon` :931 unused; `BouncingIcon` :892 and `SpinIcon` :978 only in non-Mornye destinations; non-Mornye `PageView` path with `_tabJumpOpacity/_tabJumpScale` :57-64,:639-660; `if (!context.isMornye) const SettingsTab()` :542)
- Scenario: `isMornye` is always true in production → these branches never run.
- Fix: collapse the shell to the Mornye path (~150 lines); do together with DEAD-633 (`ExpressiveNavigationBar`) and DEAD-601.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### TEST-201 [P2] [confidence: medium] [RESOLVED]
- Location: `test/library_browse_sqlite_paging_test.dart:25-33`, `test/support/sqlite_process_database.dart:37-52,160-168`, `test/support/library_paging_fixture.dart:84-91`
- Scenario: probable cause of the known flake — one monolithic test does ~8000 sequential pipe round-trips to a `python3` subprocess to build a 4000-row fixture per setUp, then 7 paging scenarios, all under the default 30 s timeout; parallel/loaded runs can time out. `close()` awaits the subprocess exit with no bound.
- Fix: explicit timeout, build the fixture in `setUpAll`, split scenarios, optionally one `executemany` request; ~10–20 lines. Confirm by looping the file 10× under `--concurrency=8` and checking for 30 s timeouts.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. Fixture is initialized once per file with a 3-minute timeout and bounded subprocess close; ten runs with --concurrency=8 pass. No performance claim.

### TEST-202 [P3] [confidence: high] [RESOLVED]
- Location: `test/library_collections_hydration_test.dart:106,164,181,211,227,265,292`, `test/library_collections_mutation_test.dart:629,702`, `test/music_player_automix_test.dart:32`
- Scenario: system temp directories created and never deleted (hydration fixtures reach 20000-row ndjson).
- Fix: `addTearDown(() => dir.delete(recursive: true))` right after each creation; ~10 lines.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### TEST-204 [P3] [confidence: high] [RESOLVED]
- Location: `test/file_stat_boundary_test.dart:64-84`
- Scenario: as uid 0, `chmod 000` does not block traversal → known spurious failure in root containers; skip covers only Windows.
- Fix: condition-based skip when `id -u` is `0`; ~4 lines.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### TEST-304 [P3] [confidence: medium] [RESOLVED]
- Location: `scripts/` (no CI, no `.github`)
- Scenario: nothing runs the 63 Kotlin unit tests (`android/app/src/test`, 12 files) or the device-only androidTest/integration_test suites; only `check_rust_backend.sh` exists.
- Fix: `scripts/check_android.sh` running `./gradlew :app:testDebugUnitTest`, referenced from AGENTS.md; ~5 lines.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. Added scripts/check_android.sh. Unit tests run on host; instrumentation sources compile only. Physical/device tests NOT RUN.

### DEAD-701 [P3] [confidence: high] [RESOLVED]
- Location: `lib/l10n/arb/app_*.arb` (20 files)
- Scenario: 54 of 769 keys are unused (28 with zero references) or used only by code already marked dead:
  - Zero references:
    - artist tag mode (9)
    - embedded cover size (3)
    - output-folder and Files/Metadata pages (9)
    - external player (5)
    - `setupSkip` and `libraryShowMore`
  - Used only by dead code:
    - re-enrich (8)
    - iOS sheet (3)
    - quick actions (6)
    - discard dialog (3)
    - view-queue snackbar (2)
    - old queue sheet (3)
    - `libraryInLibrary`
  - 10 more SAF-repair keys go with API-203: `downloadFolderAccessLost*`, `safMigration*`, `storageAutomaticFolder`, plus `setupSelectFolder` and `updateLater` if they are not used elsewhere.
- Fix: delete the keys and their `@key` metadata in every arb, then run `flutter gen-l10n`. Re-run the usage scan after the other DEAD batches: build the key list from `app_en.arb`, grep each `\bkey\b` over `lib/` excluding `lib/l10n`, and subtract files that are already dead.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-703 [P3] [confidence: high] [RESOLVED]
- Location: `pubspec.yaml:123-126` (`Google Sans Flex` → `assets/fonts/GoogleSansFlex.ttf`, 277 KB)
- Scenario: the font of the removed Material Expressive theme is still bundled. Mornye uses `Inter`, and only the test themes name this family.
- Fix: remove the pubspec font block and the TTF, and update `test/support/material_test_theme.dart`.
- Repo-only cleanup (not bundled into the app): `assets/readme/*` (1.7 MB, unreferenced).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-704 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/platform_bridge.dart:618` (`copyLocalCoverToFile`), :705 (`readDisplayAudioMetadata`)
- Scenario: no lib/ callers. They are tested only in `offline_artwork_test.dart:44,50` and `platform_bridge_metadata_test.dart:86,125`. Their native handlers stay live through other callers.
- Channel cross-check: every Kotlin handler has a Dart caller name. The Dart names with no handler (`prepareRuntimeState`, `setDownloadDirectory`, iOS bookmark methods) are all inside DEAD-201/207 methods, which would throw if called.
- Fix: delete both methods and their tests.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-706 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/file_access_check.dart`, `lib/utils/saf_display_path.dart` (no importers). Transitively dead: `lib/constants/music_services.dart` (via DEAD-501), `lib/widgets/in_library_badge.dart` and `lib/utils/local_playback.dart` (via UX-104).
- Scenario: an import graph over all of `lib/` shows no live inbound edge to any of them (~290 lines). Every other zero-importer file is already in FINDINGS.
- Fix: delete them with their tests. Trim, rather than delete, `file_stat_boundary_test.dart` (see TEST-204) and `track_metadata_badges_line_test.dart`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-801 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/history_database.dart:333-370,552-1342` (`HistoryDatabase` query/migration API; `normalizeSpotifyId`, `spotifyLookupCandidates`)
- Scenario: outside the file, only `.instance.database`, `getAll`, `upsertBatch`, `clearAll` and `schemaVersion` are used (backup paths; source-confirmed). About 25 other methods have no callers, for example `migrateIosContainerPaths`, `migrateFromSharedPreferences`, `upsert`, `findExisting*`, `getBy*`, `deleteBy*`, `updateFilePath`, `updateAudioMetadata` and `getEntriesWithPathsPage` (~700 lines).
- Fix: keep the schema create/upgrade code and the 5 backup members, and delete the rest. Check the tests that read the file as text (`native_backup_contract_test`, `album_completeness*_test`).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-802 [P3] [confidence: high] [RESOLVED]
- Location: `lib/services/app_state_database.dart:255-352,420-501,534,561-584` (pending download queue, hidden recent downloads, `getRecentDownloadsClearedAt`)
- Scenario: download-queue persistence. The only live caller is `clearPendingQueueAfterInstallationRestore` (`main.dart:232`), which clears it.
- Fix: delete the methods (~180 lines) and reduce the restore reset to the session and prefs. Update the fake in `test/recent_access_persistence_test.dart:60-101`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-803 [P3] [confidence: high] [RESOLVED]
- Location: `lib/providers/theme_provider.dart:14-17,81-84,113-131` (`setStyle`, `setUseDynamicColor`, `setSeedColor`, `setUseAmoled`), `lib/models/theme_settings.dart` (`useDynamicColor`, `seedColorValue`, `useAmoled`, `AppThemeStyle`), `lib/providers/playback_notification_provider.dart:22-24`
- Scenario: these are multi-theme leftovers. The setters are never called (`setUseAmoled` only in a test), the fields are never read, and `AppThemeStyle` has the single value `mornye`, so the check is always true.
- Fix: remove them (~80 lines) but keep parsing the old keys for imports. Update `models_and_utils_test.dart:649-679` and `appearance_settings_test.dart:412`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. Old JSON/preference keys are accepted and ignored; retained theme/player/font fields round-trip. No persisted schema migration.

### DEAD-804 [P3] [confidence: high] [RESOLVED]
- Location: 22 zero-reference symbols in live D1 files:
  - `library_collections_provider.dart`: `removeFromLoved`, `removeTrackFromPlaylist`, `exportCollections`, `exportPlaylistCovers`
  - `settings_provider.dart`: `setLocalLibraryPath`, `setLocalLibraryBookmark`
  - `download_history.dart`: `isDownloaded`
  - `library_collections.dart`: `isFavoriteArtist`
  - `track.dart`: `hasPreview`
  - `csv_import_service.dart`: `pickAndParseCsv`
  - `m3u_playlist_service.dart`: `writeExportFile`
  - `library_database.dart`: `albumKeyFor`, `getCoverPaths`
  - `mornye_glass_warmup.dart`: `isReady`
  - `notification_service.dart`: `embeddingMetadataLabel`
  - `platform_bridge.dart`: `isForegroundServiceStartNotAllowed` (+ its code constant), `notificationPercentTotal`
  - `music_player_service.dart`: `restoreMusicAudioSessionAfterVideo`, `setPlaybackNormalizationEnabled`, `setUsbOutputOptions`, `musicPlayerHandler`, `musicPlayer{MediaItem,PlaybackState,Queue}Events`
  - `file_access.dart`: `isSameContentUri`, `openFile`
  - `supported_locales.dart`: `translationThreshold`
- Check: `grep -rnw "<name>" lib test android assets rust_backend/crates`
- Fix: delete (~250 lines). Grep Kotlin for the foreground-service code constant first.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-805 [P3] [confidence: high] [RESOLVED]
- Location: symbols used only by tests. Each is listed with the test that uses it:
  - `metadata_editor_controller.dart` `beginLookup`/`selectEmptyFields` (metadata_editor_controller_test)
  - `track.dart` `isDolbyAtmos` (models_and_utils_test:504)
  - `playback_provider.dart` `playLocalPath` (playlist_playback_test:551)
  - `album_completeness.dart` `albumInventorySql` (album_completeness_test:150)
  - `backup_service.dart` `hasExtensions`/`buildEnvelope` (backup_service_v2_test:161,179)
  - `ffmpeg_service.dart` `parseReplayGainScan` (ffmpeg_replaygain_scan_test). First check whether ReplayGain scan parsing now happens elsewhere.
  - `history_maintenance.dart` `mergeInto` (history_maintenance_test:102)
  - `library_collections_database.dart` `loadPlaylistTracks` (library_collections_mutation_test fake)
  - `library_database.dart` `getQueueAlbumPage` (album_completeness_query_test)
  - `library_database_models.dart` `withAudioMetadata` (models_and_utils_test:115,234)
  - `audio_format_utils.dart` `replayGainMetadataWasRead`, `isoBmffAudioExtensionForCodec`, `detectedAudioFormatFromMetadata` (models_and_utils_test)
  - `isrc_utils.dart` `canonicalIsrcForCopy` (issue_542_utils_test). The same-file wrapper may be live.
  - `adaptive_layout.dart` `adaptiveContentMaxWidth` (adaptive_layout_test:27)
  - `local_library_provider.dart:1684-1714` `getByIsrcAsync`/`findByTrackAndArtistAsync`/`findExistingAsync`. These go with PERF-404 (`hasIsrc`/`hasTrack`/`existsInLibrary`).
  - Fold into existing entries: `useAppFolderStorage` → API-203; `DownloadDecryptionDescriptor.fromDownloadResult` → DEAD-001; `isInstrumentalLyricsMarker` → DEAD-002.
- Fix: delete each symbol with its test case.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. canonicalIsrcForCopy remains live through same-file isrcForCopy. Retained ReplayGain scan parser is tested directly; only its unused facade removed.

### DEAD-851 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/settings_group.dart:692-718` (`SettingsChoiceGrid`), `lib/widgets/app_alert_dialog.dart:33-68` (`AppDialogSurface`), `lib/widgets/error_card.dart:1-95` (`ErrorCard`; keep `EmptyState`)
- Scenario: these three public widgets have zero references in lib/ or test/ (source-confirmed).
- Fix: delete them (~160 lines).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. ErrorCard remains: album, artist and Home error states now use it. Orphan SettingsChoiceGrid/AppDialogSurface removed.

### DEAD-852 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/audio_quality_badges.dart:124-210,244-264` (`DolbyAtmosBadge`, `DolbyAtmosLogo`, `DolbyLogoPainter`, `buildQualityBadges`), `lib/models/track.dart:37,70,150,188,221,227` (`audioModes`, `isDolbyAtmos`)
- Scenario: the only caller of `buildQualityBadges` is the dead `track_list_tile.dart` (UX-104). Nothing produces `audio_modes`/`DOLBY_ATMOS`, so the field is always null.
- Fix: remove these together with UX-104 (~110 lines), then drop `audioModes`. Keep `ExplicitBadge` and `AudioQualityBadge`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-853 [P3] [confidence: high] [RESOLVED]
- Location: widget parameters that no call site ever sets, along with the branches they control:
  - `SettingsGroup.glass` (~36 sites)
  - `SettingsItem.footer` (~27 sites)
  - `SettingsInfoCard.tone` (always neutral, so the `warning`/`error` arms are dead) and `.action`
  - `AppDialogAction.outlined` (~50 sites)
  - `AppSearchField.prefixIcon`
  - `StaggeredListItem.staggerDelay`/`.duration`
  - `EditMetadataSheet.sourceTrackId` (write-only)
  - `artworkAspectRatio` in `mornye_player_layout.dart`/`mornye_player_background.dart`
  - `MornyeArtistHeader.listeners`/`.badge`/`logoUrl` and `MornyeArtistSurface.logoSource` (remote-artist leftovers; logo set only in tests)
  - `AppTokens.coverCompact` (never read)
- Fix: delete the parameters and branches (~150 lines), and update the tests that set the logo params. Check with `grep -rnE "\b<param>:" lib test`, then confirm which class each hit belongs to.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. artworkAspectRatio remains live in Immersive view. SettingsInfoCard.glass remains live. Only parameters with no retained caller removed.

### DEAD-854 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/album_description.dart` (`AlbumDescription`), `lib/widgets/mornye_chrome.dart` (`MornyeFilterChip`), `lib/widgets/collection_scaffold.dart:22,38,117` (`bottomInset`), `lib/app.dart:50` (`/tutorial` redirect route)
- Scenario: these are used only by tests, or never navigated to.
- Fix: delete the widgets with their tests, decide whether to keep `NowPlayingScreen.metadataControllerFactory` as a test seam, and drop the `/tutorial` alias. The `album_description_test` deletion is shared with DEAD-504.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. NowPlayingScreen.metadataControllerFactory remains a useful test seam. /tutorial alias and orphan widgets removed.

### DEAD-901 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/progress/{mod,reporter,subscription}.rs` (726 lines), `core/src/lib.rs:15`
- Scenario: the download progress registry has zero users outside its own directory (source-confirmed).
- Fix: delete the directory and the `pub mod` line.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-902 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/media/hires/**` (~1,920 lines + 1,128 test lines), `mobile/src/hires.rs`, `core/src/tags/write/mp4/ac4.rs`, `core/src/tags/write.rs:217-250`, `local/src/backend/tags.rs:14,259,284`, `mobile/src/tags.rs:218,274,288`; Kotlin `CoreBackend.kt:17`, `SelectedCoreBackend.kt:147,323,351-355`, `MainActivity.kt:1257-1440` handlers, `MainActivitySafIo.kt:295`
- Scenario: these are the native tails of the dead DEAD-202 Dart wrappers `checkHiResAuthenticity`, `ensureAC4Config`, `writeAC4Metadata` and `rewriteSplitArtistTags`. `platform_bridge.dart:688` has no caller (source-confirmed). About 2,600 Rust and 130 Kotlin lines are unreachable.
- Fix: delete them together with DEAD-202 and regenerate the uniffi bindings. Keep `native_audio_analysis` (Audio Quality Analysis) and `writeM4aFreeformTags`. Note: RUST-201 (`hires/mod.rs`) sits in this dead code and becomes moot.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-903 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/clock.rs`, `core/src/cancellation.rs:240,256,297` (`observe_thread`, `active_request_cancelled`, `wait_cancelled`), `core/src/cover.rs:10` (`MAX_DOWNLOAD_BYTES`), `core/src/lib.rs:18` (`normalize_json_surrogates` re-export)
- Scenario: these are transitively dead. `clock` is used only by the dead `filename/date.rs` (DEAD-303), and the others appear only at their declarations.
- Fix: delete them after DEAD-303, then re-run the orphan check (`text::json_surrogates` may follow).
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-904 [P3] [confidence: high] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/SafFileOps.kt:118,146,405,419` (`copyContentUriToTemp`, `writeFileToSaf`, `deleteContentUri`, `mimeTypeForExt`), `CoreBackend.kt:9-10,29` (`routesApplication`, `supportsOutputDescriptors`, `scanCueForLibrary`), `SelectedCoreBackend.kt:280`, `mobile/src/tags.rs:130` (`scan_cue_file_for_library` export)
- Scenario: nothing references these except their declarations (`writeFileToSaf` is used only by an androidTest).
- Fix: delete them (~90 lines). Keep the local-crate `scan_cue_file_for_library`, which `scan.rs:471` uses.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-905 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/mobile/Cargo.toml` and `rust_backend/Cargo.toml` (`scraper`), `core/Cargo.toml:21-22` (`tz-rs`), `local/Cargo.toml` (android dev-dep `libc`)
- Scenario:
  - `scraper` (which pulls in html5ever, cssparser and selectors) has zero uses.
  - `tz-rs` is used only by `clock.rs`, so it goes with DEAD-903.
  - local's `libc` dev-dep has no uses.
- Fix: remove the lines, then run `cargo update -w --offline`. After the DEAD-301..303/903 batches, re-check `rustix`, `unicode-normalization`, `unicode-general-category` and `chrono` in core.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-906 [P3] [confidence: high] [RESOLVED]
- Location: `android/app/src/main/res/drawable/ic_notification_airplay.xml`, `res/values/colors.xml:4-7` (`widget*` colors), `res/values-night/colors.xml`, `res/values-v31/colors.xml`, `res/values-night-v31/colors.xml`
- Scenario: these resources are unreferenced. The `notification_keep.xml` wildcard only stops the shrinker from removing them; it is not a use.
- Fix: delete them. Keep `ic_launcher_background`.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-907 [P3] [confidence: high] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:94-400` (`resolveSafFile`, `inspectSafFiles`)
- Scenario: these are called only by the DEAD-202 handlers (`MainActivity.kt:1083,1090`). They make up ~300 lines, the bulk of that dead feature.
- Fix: delete them with DEAD-202. Keep `SafFileOps.findDocumentDir` while `MainActivitySafScan.kt:282` uses it.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable.

### DEAD-908 [P3] [confidence: high] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/SafFileOps.kt:26-55,167-242` (unique/collision-aware/if-absent writers, `withSafNameLock`, `PublishTrace`, filename counters), `NativeResourcePools.kt:10` (`KeyedLockPool`), `MainActivity.kt:121-123,1137-1250` (`safCreate{IfAbsent,Unique,CollisionAware}FromPath`)
- Scenario: the only Dart callers are the DEAD-202 wrappers at `platform_bridge.dart:494,510,528`. This is ~330 lines of download-era collision handling.
- Fix: delete them with DEAD-202 and update `NativeResourcePoolsTest`. Keep `writeFileToSafLocked`, which `safCreateFromPath` uses.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. Atomic writeFileToSafLocked helper retained as directed. Removed only dead collision entry points; active metadata publication uses MainActivity SAF I/O.

### DEAD-909 [P3] [confidence: high] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/NativeReplayGainPolicy.kt`, `NativeResourcePools.kt:35,41` (`activeKeyCount`, `BoundedRegistry`), `SafDocumentIdentity.kt:8` (`safDocumentMatchKey`), `NativeMediaWorkspace.kt:30` (`withOwnedTemporaryMediaFile`)
- Scenario: each is referenced only by its own Kotlin unit test.
- Fix: delete them with their tests (~150 lines). If `NativeReplayGainPolicy` was meant to gate ReplayGain batches, decide that first: it is never consulted. Related: KT-001, DEAD-208.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. Owner decision: NativeReplayGainPolicy and tests retained for future Media3 work; only orphan NativeResourcePools/SafDocumentIdentity/temp-ownership wrapper removed. This is a disposition, not removal of the policy.

### RUST-201 [P2] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/core/src/media/hires/mod.rs:567-568` (`Source::analyze_window`, FLAC)
- Scenario: FLAC whose STREAMINFO declares more channels than frames carry → `block.channel(index)` slices out of range in claxon → panic inside an FFI call (Audio Quality Analysis).
- Root cause: claxon does not check frame vs STREAMINFO channels; guard exists in `replacement.rs:93-95` but not here.
- Impact: panic on untrusted file data (surfaced as a generic error if uniffi catches it; unverified).
- Fix: return Err when `block.channels()` differs; ~3 lines + test.
- Resolution: `ef8ba64d`; verified in PORT_PLAN batch 16. Physical-device checks remain NOT RUN where applicable. The finding belonged to the unreachable Hi-Res module removed with DEAD-902; active native_audio_analysis remains.


### PLAY-001 [P2] [confidence: medium-high] [RESOLVED]
- Location: `lib/screens/now_playing_screen.dart:474-495` (Immersive artwork inside `MornyePlayerBackground`), `lib/widgets/mornye_player_layout.dart:466-475` (`PlayerTrackSwipe`), :271 (expanded layer skipped when `fullBleed`), `lib/widgets/player_track_swipe.dart:133-136`
- Scenario: Player view = Immersive, swipe left/right on the cover → nothing happens. The background is a sibling of the layout in the `Stack`, so `PlayerTrackSwipeRegion` finds no `_SwipeScope` and returns its child unwrapped; Normal view works. AGENTS.md requires track changes in both views. Upstream has the same structure but only hits it with motion artwork.
- Fix: lift `PlayerTrackSwipe` above the `Stack`, or give the background artwork its own scope; ~20 lines plus a widget test for Immersive swipe.
- Resolution: `3dfa8b73`; verified in PORT_PLAN batch 14. Physical-device checks remain NOT RUN where applicable.

### PLAY-002 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/now_playing_screen.dart:475` (`key: ValueKey(immersive)`)
- Scenario: `immersive` includes `!_landscape`, so rotating in Immersive recreates the background: `CoverPaletteBuilder` and the 380 ms gradient restart (visible pop), and `_expandedArtworkKey` moves between parents in one frame.
- Fix: drop the key or key on `squareArtwork` only; test the Hero/GlobalKey move on rotation.
- Resolution: `822a4656`; verified in PORT_PLAN batch 14. Physical-device checks remain NOT RUN where applicable.

### PLAY-003 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/lyrics_size_setting.dart:46-52`
- Scenario: TalkBack reads a bare percentage on the lyrics size slider; upstream latest (`befcd2ad`) adds `semanticLabel: lyricsTextSize`.
- Fix: one line.
- Resolution: `3dfa8b73`; verified in PORT_PLAN batch 14. Physical-device checks remain NOT RUN where applicable.

### PLAY-004 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/player_queue_dismissible.dart:57`
- Scenario: swipe-to-remove background radius 12 vs queue rows 16, so the red reveal shows mismatched corners. Upstream latest uses 16.
- Fix: one line.
- Resolution: `3dfa8b73`; verified in PORT_PLAN batch 14. Physical-device checks remain NOT RUN where applicable.


### HOME-001 [P2] [confidence: medium-high] [RESOLVED]
- Location: `lib/screens/home_tab_widgets.dart:92-101` (`Image.file` with `cacheWidth` and `cacheHeight`), called with `height: width / 1.5` from `home_tab_feed.dart:215`
- Scenario: Latest Releases (3:2 cards) with an embedded cover: the square cover is decoded to the card's exact 3:2 size, so it is squashed; `BoxFit.cover` cannot undo it. `CachedCoverImage` (`cached_cover_image.dart:65-67`) and upstream decode one axis only.
- Fix: pass only `cacheWidth`; ~3 lines. Check on device.
- Resolution: `0d9dbf9c`; verified in PORT_PLAN batch 13. Physical-device checks remain NOT RUN where applicable.

### HOME-002 [P2] [confidence: medium] [RESOLVED]
- Location: `lib/screens/home_tab_feed.dart:19-45`, :48-60, :89-112; `lib/screens/home_tab.dart:275-299`
- Scenario: any `loadedIndexVersion` bump (scan phases, delete, tag edit) re-runs the watched providers → `AsyncLoading` with the previous value; `.when()` uses Riverpod 3.4.3's default `skipLoadingOnReload: false` (`async_value.dart:197`), so Latest Releases turns into a spinner and the other shelves into `SizedBox.shrink()`; the page jumps and shelf scroll offsets reset. `library_browse_provider.dart:186-187` intends to keep the old data visible.
- Fix: `skipLoadingOnReload: true` (or read the previous value first) in the four `when` calls; ~4 lines. A widget test that bumps `loadedIndexVersion` confirms it.
- Resolution: `0d9dbf9c`; verified in PORT_PLAN batch 13. Physical-device checks remain NOT RUN where applicable.

### HOME-003 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/home_tab_feed.dart:22-29`, :40-43, :58, :110; `lib/screens/home_tab.dart:145`, :296
- Scenario: no pull-to-refresh (upstream `RefreshIndicator`/`AppRefreshIndicator`); empty library shows bare `libraryEmptyCollection` text (upstream icon + `homeEmptyTitle`/`homeEmptySubtitle`, also not telling "library off" from "no folder"); loading is a bare spinner or nothing (upstream `ShimmerLoading`/`SkeletonBox` shelves, `home_tab_explore.dart:100-160`); `_feedRetry` is unstyled.
- Fix: refresh indicator invalidating the feed providers, Mornye empty state, skeleton shelves.
- Resolution: `0d9dbf9c`; verified in PORT_PLAN batch 13. Physical-device checks remain NOT RUN where applicable.

### HOME-004 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/home_tab_feed.dart:134`, :216-238, :242, :99
- Scenario: (a) featured heading prints the raw tag (`2024/3/5`, `20240305`, `2024-03-05T00:00:00Z`); the `?? searchAlbums` fallback is unreachable (SQL drops empty dates). (b) Card text uses hard-coded `TextStyle` 16/14 with no weight; upstream `bodyMedium` w600 title and `bodySmall` `onSurfaceVariant` subtitle. (c) `Semantics(label: name)` omits type/artist and is not `excludeSemantics`, so TalkBack can read the name twice. (d) Artist cards render an empty subtitle line (`subtitle: ''`). (e) Track titles lack the explicit E badge required by AGENTS.md.
- Fix: format the date, theme text styles, full label with `excludeSemantics`, omit empty subtitle, `ExplicitTrackTitle`.
- Resolution: `0d9dbf9c`; verified in PORT_PLAN batch 13. Physical-device checks remain NOT RUN where applicable.

### HOME-005 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/home_tab_feed.dart:155-159`, :168-189, :178-184, :216
- Scenario: card width is fixed 156/180 instead of upstream `145 * responsiveScale(0.82..1.32) * text-scale` (`home_tab.dart:163-170`); section height is estimated from text scale, so large fonts can clip; shelf titles use `titleLarge` with 24 top padding (upstream `titleMedium` bold, 20); cover radius 12 vs 10; no `wideListInset`, so titles hug the edge on tablets while Library/Settings are centered.
- Fix: upstream sizing formula and title style, `wideListInset`. Verify rendered on device.
- Resolution: `0d9dbf9c`; verified in PORT_PLAN batch 13. Physical-device checks remain NOT RUN where applicable.

### HOME-006 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/home_tab_widgets.dart:3-120` (`_DownloadedOrRemoteCover`), `lib/services/library_queue_store.dart:437-440`
- Scenario: when `samplePath` is set, the card extracts the cover natively per file instead of using the indexed `cover_path`; `sample_file_path` (`MAX(file_path)`) and `cover_path` (`MAX(cover_path)`) can come from different tracks, so the card can show another track's art. After a cover edit with the same path the old art stays until the resolver refresh. The widget keeps download-era naming and an `imageUrl` parameter.
- Fix: prefer a local `cover`, fall back to the resolver only when empty; rename the widget; ~15 lines.
- Resolution: `0d9dbf9c`; verified in PORT_PLAN batch 13. Physical-device checks remain NOT RUN where applicable.

### HOME-007 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/home_tab_helpers.dart` (alias `_recentlyAddedProvider = localHomeTracksProvider`), `lib/screens/home_tab_search_results.dart` (only `part of`), `lib/screens/home_tab.dart:25,27`, :221-268
- Scenario: dead leftovers: two empty/alias part files, and the non-Mornye `_buildHomeIntro` branch (brand title, `homeSubtitle`, logo asset) that Mornye-only builds never reach.
- Fix: delete both part files and the branch, then re-run the dead-code checks for `homeSubtitle` and the logo asset. Tier 3 cleanup.
- Resolution: `0d9dbf9c`; verified in PORT_PLAN batch 13. Physical-device checks remain NOT RUN where applicable.

### HOME-008 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/main_shell.dart:353-357` (`_resetHomeToMain`), `lib/screens/home_tab_feed.dart:185-191`, :97, :244
- Scenario: re-tapping Home while scrolled down does nothing (pops only); release/track/playlist cards have no keys, so cover state is reused by index when a shelf reorders; no long-press menu on Home cards (upstream Mornye context menu). Upstream also lacks tab-reselect scroll.
- Fix: scroll to top on reselect; `ValueKey` per card; optional long-press with the local song/album menu.
- Resolution: `0d9dbf9c`; verified in PORT_PLAN batch 13. Physical-device checks remain NOT RUN where applicable.


### MORN-013 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/local_collection_actions.dart:42-77`
- Scenario: Loved and Add-to-playlist circles use non-tonal glass, so they differ from the Play/Shuffle pills; no red tint when all loved; toggle is silent (upstream `loveAllTracks` snackbars) and its error path reuses `showCannotOpenFileSnackBar`. Affects album and playlist headers.
- Fix: `tonal: true` (owner decision 2026-10-20: use the tonal style), `iconColor: error` when all loved, reuse `loveAllTracks` feedback.
- Resolution: `ce2538bf`; verified in PORT_PLAN batch 12. Physical-device checks remain NOT RUN where applicable.

### MORN-014 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/library_tracks_folder_screen.dart:220-223`, :481, :545
- Scenario: backdrop/palette come from the first track's cover while the hero shows the custom cover (playlist) or a grey heart (Loved), so tint and hero disagree.
- Fix: one shared cover source for hero, surface and palette.
- Resolution: `ce2538bf`; verified in PORT_PLAN batch 12. Physical-device checks remain NOT RUN where applicable.

### MORN-015 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/album_detail_header.dart:126`, :198
- Scenario: landscape/split-screen: artwork is `width.clamp(0,440)`, so the title and actions fall below the fold; immersive details `Stack` lacks `alignment: topCenter`, so details misalign on wide screens. Upstream latest fixes both (`min(width.clamp(0,440), max(240, height*0.55))`).
- Fix: port the two upstream lines. Affects album, playlist and Loved.
- Resolution: `c2f38c86`; verified in PORT_PLAN batch 12. Physical-device checks remain NOT RUN where applicable. ALREADY IMPLEMENTED by U-210 in batch 6; no duplicate change.

### MORN-016 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/widgets/mornye_chrome.dart:28`, `lib/theme/mornye_theme.dart:69`, :227
- Scenario: segmented pill height `scale(15)+36` can drop below 48dp per segment; dark accent `rgb(224,61,60)` and the red-accent `onPrimary` special case have contrast issues. Upstream latest: height clamped to ≥56, accent `rgb(255,69,58)`, luminance-only `onPrimary`.
- Fix: port the three upstream changes; check contrast.
- Resolution: `ce2538bf`; verified in PORT_PLAN batch 12. Physical-device checks remain NOT RUN where applicable.


### MORN-006 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/local_album_screen.dart:396-405` (`_buildLocalHeaderMeta`)
- Scenario: (a) genre missing (upstream Mornye shows it first, `album_screen.dart:346-349`); (b) year from `split('-')` shows "2024/05"/"20240501" verbatim, upstream uses `(\d{4})`; (c) `'$totalMinutes min'` is hard-coded English; (d) count/duration repeat the footer.
- Fix: genre item, year regex, localized minutes, drop the duplicate; ~15 lines.
- Resolution: `df09d3ea`; verified in PORT_PLAN batch 11. Physical-device checks remain NOT RUN where applicable.

### MORN-007 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/local_album_screen.dart:409-414` (`_playAll`)
- Scenario: album whose first sorted row is a CUE virtual track → Play shows the "split first" snackbar instead of playing; `_shuffleAll` already filters CUE rows.
- Fix: start at the first non-CUE track.
- Resolution: `df09d3ea`; verified in PORT_PLAN batch 11. Physical-device checks remain NOT RUN where applicable.

### MORN-008 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/local_album_screen.dart:559-562`
- Scenario: selection bar labels the ReplayGain Apply/Remove buttons "Edit Metadata", unstyled.
- Fix: ReplayGain label with the section-label style.
- Resolution: `df09d3ea`; verified in PORT_PLAN batch 11. Physical-device checks remain NOT RUN where applicable.

### MORN-009 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/local_artist_screen.dart:236-244` (Shuffle), :173-180 (Favorite)
- Scenario: the two outer header buttons differ: Shuffle uses default icon size 22 and dark glass, Favorite white 0.10 tint; neither uses `iconColor: primary`. Upstream sets size 50/icon 24/primary/white .10 on both (`artist_screen_widgets.dart:87-93,120-128`).
- Fix: same params on both.
- Resolution: `df09d3ea`; verified in PORT_PLAN batch 11. Physical-device checks remain NOT RUN where applicable.

### MORN-010 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/local_artist_screen.dart:109-120` (`_artwork`)
- Scenario: one placeholder (`CupertinoIcons.person`, size 64) for header, album cards, featured card and 48px song thumbnails: wrong icon and oversized in small slots. Upstream uses `square_stack` (albums) and `music_note` (tracks).
- Fix: placeholder per use, sized to the slot.
- Resolution: `df09d3ea`; verified in PORT_PLAN batch 11. Physical-device checks remain NOT RUN where applicable.

### MORN-011 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/local_artist_screen.dart:52`
- Scenario: collapsed title appears at offset 330; upstream 280.
- Fix: 280.
- Resolution: `df09d3ea`; verified in PORT_PLAN batch 11. Physical-device checks remain NOT RUN where applicable.

### MORN-012 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/local_artist_screen.dart:298-338` (Popular rows), :507-512 and :470-503 (album cards), :414-446 (featured card)
- Scenario: Popular uses stock `ListTile` (upstream: L20/R10 padding, 17/15px text, radius 4, inset hairline divider, `artist_screen_widgets.dart:664-793`); album cards lack the year · track-count subtitle, `Semantics(button)` and responsive tile size (upstream :1061-1072, :915-920, `artist_screen.dart:192-202`); no Single/EP badge; featured card can print "0 tracks" and lacks the 4/8px gaps.
- Fix: port the upstream Mornye row/card styling. Verify on device.
- Resolution: `df09d3ea`; verified in PORT_PLAN batch 11. Physical-device checks remain NOT RUN where applicable. Adapted to retained local inventory: explicit one-track releases get Single badges; EP type is absent from the local browse model, so EP badges are omitted and never guessed from stored file counts.


### MORN-001 [P2] [confidence: high] [RESOLVED]
- Location: `lib/screens/local_album_screen.dart:309-385` (no `leading`/`appBarTitle`/actions swap)
- Scenario: long-press a track on an album → selection mode, but Play/Shuffle row stays, Back pops the route instead of leaving selection, no "N selected" title. Upstream `album_screen.dart:611-671` handles all three.
- Fix: pass close `HeaderCircleButton`, `appBarTitle: selectionSelected(n)` and hide actions while selecting; ~20 lines.
- Resolution: `bc983981`; verified in PORT_PLAN batch 10. Physical-device checks remain NOT RUN where applicable.

### MORN-002 [P2] [confidence: high] [RESOLVED]
- Location: `lib/screens/library_tracks_folder_screen.dart:636-654` (`leading:` override)
- Scenario: playlist/Loved show a Material black 0.4 circle with `Icons.arrow_back` instead of the Mornye glass `chevron_back` back button that albums use (`album_detail_header.dart:147-155`); breaks the AGENTS back-button rule and light mode.
- Fix: no `leading` outside selection; in selection use `HeaderCircleButton(Icons.close)` (upstream latest :665-676). Same for the M3U/rename/cover buttons at :584-634 (`HeaderCircleButton(iconSize: 20)`).
- Resolution: `bc983981`; verified in PORT_PLAN batch 10. Physical-device checks remain NOT RUN where applicable.

### MORN-003 [P2] [confidence: high] [RESOLVED]
- Location: `lib/screens/library_tracks_folder_screen.dart:539-541`
- Scenario: `appBarTitle` is the collection title outside selection, so the toolbar always draws the title over the artwork next to the hero title; the collapse fade is lost. Upstream passes `null`.
- Fix: `: null`.
- Resolution: `bc983981`; verified in PORT_PLAN batch 10. Physical-device checks remain NOT RUN where applicable.

### MORN-004 [P2] [confidence: high] [RESOLVED]
- Location: `lib/screens/library_tracks_folder_screen.dart:252-258`, :298-305
- Scenario: open a playlist before `ensurePlaylistLoaded` finishes (or Loved before collections load) → "playlist is empty" state and a header with no actions flash. Upstream shows `TrackListSkeleton`.
- Fix: skeleton while `!playlist.tracksLoaded` / collections not loaded.
- Resolution: `bc983981`; verified in PORT_PLAN batch 10. Physical-device checks remain NOT RUN where applicable.

### MORN-005 [P3] [confidence: high] [RESOLVED]
- Location: `lib/screens/library_tracks_folder_screen.dart:886-899` (`_CollectionTrackTile`)
- Scenario: playing song in a playlist/Loved never shows Pause; tapping restarts it. `LocalSongRow.isPlaying` exists and the album screen uses it (`local_album_screen.dart:495-516`).
- Fix: pass `isPlaying` and toggle like the album screen.
- Resolution: `bc983981`; verified in PORT_PLAN batch 10. Physical-device checks remain NOT RUN where applicable.

### MORN-017 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/screens/local_artist_screen.dart:247-268`, :274-291; `lib/screens/local_album_screen.dart:234-260`
- Scenario: loading/error/empty states use bare Material widgets (spinner, `TextButton` Retry, plain `Scaffold`/`AppBar`) with no Mornye back button or surface; Popular heading shows while loading and with "No local tracks". Upstream uses skeletons, `ErrorCard` (exists in `widgets/error_card.dart`) and hides empty Popular.
- Fix: skeleton + `ErrorCard` + Mornye empty page; hide empty Popular.
- Resolution: `bc983981`; verified in PORT_PLAN batch 10. Physical-device checks remain NOT RUN where applicable.


- UX-205 (`c29daef`): About page contributors, translators, special thanks, links and social sections removed (owner decision); no remote avatars remain.
- UX-206 (`c29daef`): `_launchUrl` and the `url_launcher` dependency removed with the links.
- DEAD-705 (`c29daef`): Search tab Recent list, `recent_access_provider.dart`, its app-state methods and tables removed (app-state schema v5 drops them). UX-101 (whole-library load when opening a recent album) is resolved with it.

### DATA-501 [P1] [confidence: medium] [RESOLVED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:741-757 (`querySafChildrenOrThrow`), consumed at :930, :1355; Dart `library_database.dart:373`, `library_cleanup.dart:18-27`
- Scenario: a cloud/network DocumentsProvider returns an empty children cursor with `DocumentsContract.EXTRA_ERROR` → treated as an empty folder, `traversalErrors` stays 0 → full scan: `error_count` 0 → `preserveMissing = false` → `deleteReplacedLibraryScanRows` deletes the subtree (or whole source if the root listing is empty); incremental: missing URIs go to `removedUris` → `deleteByPaths`.
- Root cause: only `EXTRA_LOADING` is checked; a 0-row result with no errors is trusted as authoritative.
- Impact: library rows for a folder or the whole source disappear after a transient provider failure (files untouched; restored by a later successful scan).
- Fix: throw `IOException` when `cursor.extras.getString(EXTRA_ERROR) != null` (~3 lines); optionally refuse a full replace yielding 0 rows when the source had rows.
- Evidence: check at :756 only reads `EXTRA_LOADING`; trigger depends on provider behavior (documented DocumentsProvider error contract).
- Resolution: `46c4ea6a`. `querySafChildrenOrThrow` throws on `EXTRA_ERROR`; an empty listing cannot replace rows that a source already has (`safEmptyListingIsUntrusted`, `has_indexed_rows` passed for forced scans because they delete the resume files); incremental scans throw when the listing is empty and rows exist, and pruning only runs for a non-empty listing. `SafScanPolicyTest`, the `has_indexed_rows` forwarding test in `test/library_full_scan_test.dart`: PASS.

### KT-201 [P2] [confidence: high] [RESOLVED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1465-1539 (changed-CUE loop in `scanSafTreeIncremental`), :1427, :1660
- Scenario: a CUE whose mtime changed fails to re-scan (temp copy null, audio missing, parse throws) → catch only does `errors++`; old `cue#trackN` paths never added to `currentUris` → returned as removed → Dart deletes the CUE's tracks. `errors` not returned.
- Root cause: failed re-index treated like deletion.
- Impact: transient read error deletes all tracks of a CUE album from the library.
- Fix: on failure add the existing virtual paths to `currentUris`; return the error count; ~5 lines.
- Evidence: catch block at :1534-1536; `currentUris` extended only at :1401 and :1530.
- Resolution: `46c4ea6a`. A failed changed-CUE re-scan keeps the existing `#trackN` rows in `currentUris` (retaining them only when the CUE previously owned them) and counts the error; a sheet that produced rows claims its audio. `SafScanPolicyTest` covers the suffix/base rules: PASS.

### KT-202 [P2] [confidence: high] [RESOLVED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1604-1613, :1427-1430 (incremental scan)
- Scenario: a `.cue` is added beside an already-indexed, unchanged audio file → CUE tracks indexed, standalone row kept → duplicates until a full rescan.
- Root cause: `cueReferencedAudioUris` only skips changed audio; never removes existing standalone rows.
- Fix: add `existingFiles.keys ∩ cueReferencedAudioUris` to `finalRemovedUris`; ~3 lines.
- Evidence: full scan avoids it via full swap (:1162).
- Resolution: `46c4ea6a`. A CUE that produced or retained rows claims its backing audio, and incremental removal deletes the standalone row through `safReferencedStandaloneUris`. `SafScanPolicyTest` standalone-removal cases: PASS.

### KT-203 [P2] [confidence: medium] [RESOLVED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1003-1012, :1047-1160 (`scanSafTree` resume)
- Scenario: full scan interrupted and resumed; checkpoint rebuilt from surviving NDJSON rows; files deleted/renamed in between stay in the output and are imported.
- Root cause: resumed output not pruned against the current listing.
- Impact: ghost tracks for deleted files.
- Fix: filter stale lines after traversal or discard the resume when the checkpoint has URIs not in the listing; ~15 lines.
- Evidence: reconcile step never consults the current listing.
- Resolution: `46c4ea6a`. The rebuilt checkpoint is pruned against the current listing before its rows are emitted, and resumed rows for unlisted URIs are dropped. `SafScanPolicyTest` checkpoint cases: PASS.

### KT-102 [P2] [confidence: high] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:191-196` (`safTreeLauncher` callback), :219
- Scenario: picker returns OK but `data.flags` has no grant bits (`takeFlags == 0`) or `takePersistableUriPermission` throws (e.g. grant cap reached, see KT-105) → only logged; payload delivered as success.
- Root cause: persist failure not propagated; no READ|WRITE fallback.
- Impact: Dart stores a tree whose grant is lost after restart; the library silently loses access.
- Fix: fall back to READ|WRITE flags when 0; on failure return an error; ~6 lines.
- Evidence: lines 191-196; unconditional `deliver(payload)` at :219.
- Resolution: `46c4ea6a`. `safTreePersistFlags` retries READ|WRITE then READ; a grant without READ counts as no grant; a failed persist delivers `errorJson(...)`, Dart returns null and the picker surfaces a SnackBar. `ErrorJsonTest` and `SafScanPolicyTest` persist-flag cases: PASS.

### KT-103 [P3] [confidence: low] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:756-778` (`onDestroy`), :857-866, :74
- Scenario: engine outlives the Activity; after Activity re-creation during a background scan, a new progress StreamHandler is installed without a Dart re-subscribe → progress stalls; `scope` never cancelled and backend channel handler not cleared → short Activity leak.
- Fix: cancel `scope` in `onDestroy`; confirm `ProgressStreamPoller` re-subscribes.
- Resolution: `46c4ea6a`. Scan state lives in the `MainActivity` companion (`safScanLock`, `safScanProgress`, `safScanCancel`, `safScanPaused`, `safScanActive`); progress runs through the process-scoped `SafScanProgressStream`; `onDestroy` always clears the channel handlers and only stops the stream/cancels the scope when `isFinishing`. Verified by tracing the recreated-Activity path: PASS.

### KT-104 [P3] [confidence: high] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:1459`, :1478
- Scenario: error JSON hand-built with only quote replacement → backslash/newline in a message yields invalid JSON → Dart `jsonDecode` throws.
- Fix: use `errorJson(e.message ?: "unknown")`; 2 lines.
- Resolution: `46c4ea6a`. Native error payloads use `errorJson(...)` (JSONObject escaping). `ErrorJsonTest` covers quotes, backslashes and newlines: PASS.

### KT-105 [P3] [confidence: medium] [RESOLVED]
- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt:193`
- Scenario: `releasePersistableUriPermission` is never called; replaced/removed folders keep grants until the platform cap (128/512) → later picks fail (silently, KT-102).
- Fix: release grants when a library source is removed; ~15 lines.
- Resolution: `46c4ea6a`. `safReleaseTree`/`releaseSafTreeGrant` drop the persisted grant when a `content://` source is removed, only after the row delete, only when no sibling source uses the tree, and never for the legacy `downloadTreeUri` (T5 removes that flow). New `test/library_loading_test.dart` cases cover release, a shared tree and the legacy tree: PASS.

### KT-204 [P3] [confidence: medium] [RESOLVED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1396-1398, :1410
- Scenario: providers without `COLUMN_LAST_MODIFIED` give 0 → edits never detected incrementally; replacing audio under an unchanged CUE keeps stale CUE data.
- Fix: treat 0 as changed; ~2 lines.
- Resolution: `46c4ea6a`. `safFileChanged` treats a zero timestamp on either side as changed, so providers without `COLUMN_LAST_MODIFIED` still pick up edits. `SafScanPolicyTest` zero-timestamp cases: PASS.

### KT-205 [P3] [confidence: high] [RESOLVED]
- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:1094-1096, :1558-1575
- Scenario: resumed scan skips indexed CUEs without `scanned++` (progress under-reports); unchanged-CUE copy failure only logged → audio indexed standalone, duplicating CUE rows.
- Fix: count/progress before `continue`; treat unresolved unchanged CUE as an error.
- Resolution: `46c4ea6a`. An unchanged resumed CUE is resolved before counting totals, its tracks are skipped per audio key (`unresolvedCueAudioKeys`) instead of per directory, and a failed resolution counts as an error rather than indexing the audio standalone. `SafScanPolicyTest` covers the resolution helpers: PASS.

### DATA-204 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/utils/path_match_keys.dart:99-148` (`addNormalized`), :180 (`_androidDocumentMatchKey`)
- Scenario: (A) lowercased keys make `A.flac`/`a.flac` in one folder collide → deleting one drops the other's row until rescan and hides it from duplicates. (B) virtual SAF CUE paths lose `#trackNN` in keys → all tracks of a CUE share a key (latent: current callers guard virtual paths).
- Root cause: case folding on case-sensitive storage; fragment dropped for SAF keys.
- Impact: rare row loss; trap for future callers.
- Fix: keep `#trackNN` in SAF/URI keys; skip lowercase key for non-SAF paths; ~10 lines.
- Evidence: :100-101, :125-131.
- Resolution: `46c4ea6a`. Only Windows drive paths fold case; SAF/URI keys keep the anchored `#track\d+$` fragment; a raw externalstorage alias is skipped when a fragment key exists. Regression tests in `test/models_and_utils_test.dart`: PASS.

### SEC-004 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/utils/saf_display_path.dart:127-139` (`_safDocumentId`)
- Scenario: `Uri.pathSegments` already decodes; `Uri.decodeComponent` decodes again → names with a literal `%XX` display wrongly.
- Root cause: double decoding.
- Impact: display-only.
- Fix: return the segment directly; 1 line.
- Evidence: contradicts `resolveSafDocumentLocation` doc comment.
- Resolution: `46c4ea6a`. The cited `lib/utils/saf_display_path.dart` no longer exists; the live double decodes were `_displayNameForPath` and `_looksLikeRemovablePath` in `lib/providers/local_library_provider.dart` and `_getDisplayPath` in `lib/screens/settings/library_settings_page.dart`. All now use the already-decoded `pathSegments`, and no `Uri.decodeComponent` call remains under `lib/`.

### BUG-001 [P2] [confidence: high] [RESOLVED]
- Location: lib/widgets/local_song_file_actions.dart:191 (`splitLocalCue`)
- Scenario: CUE album split where cover embed throws on one FLAC (native error) → loop aborts; earlier tracks already exported, rest never exported, snackbar says "CUE split failed".
- Root cause: `PlatformBridge.editFileMetadata` call has no per-file try/catch (old `_performCueSplit` caught and logged it).
- Impact: partial split reported as failure; user retries and gets duplicates.
- Fix: wrap the embed in try/catch and continue; ~5 lines + test.
- Evidence: old flow at `26f8e71^` wrapped the same call; current loop 189–201 is unguarded inside the outer catch at 209.
- Resolution: `76f2fb10`. `exportCueSplitOutputs` wraps each cover embed and each SAF create in its own try/catch, so one failure no longer aborts the remaining exports; partial results report `cueSplitPartialSuccess`. `test/cue_split_test.dart` covers a throwing embed and a rejected copy: PASS.

### BUG-002 [P2] [confidence: high] [RESOLVED]
- Location: lib/widgets/local_song_file_actions.dart:100 (`splitLocalCue`)
- Scenario: user reopens the menu during a long split and taps Split again → two FFmpeg jobs, two temp audio copies, duplicate files in the destination.
- Root cause: the `_isSplittingCue` re-entrancy guard from the old flow was dropped when moving to a top-level function.
- Impact: doubled CPU/storage, duplicate output files.
- Fix: module-level in-flight set keyed by the backing CUE path; ~6 lines + test.
- Evidence: old `_performCueSplit` returned early on `_isSplittingCue` (`26f8e71^`); no guard in the new function.
- Resolution: `76f2fb10`. `_cueSplitsInFlight` (module scope, keyed by `stripCueTrackSuffix(path)`) rejects a second split of the same sheet and is cleared in `finally`; a sibling row and a later retry are tested in `test/local_song_menu_actions_test.dart`: PASS.

### DATA-001 [P2] [confidence: low] [RESOLVED]
- Location: lib/widgets/local_song_file_actions.dart:18 (`isCueSong`) vs :81 (`deleteLocalSong`)
- Scenario: a row with filePath `*.cue` or format `cue+*` but no `#trackNN` suffix would show CUE actions, and Remove from device would call `deleteFile` on the backing sheet/audio.
- Root cause: `isCueSong` is wider than `isCueVirtualPath`, but only the latter protects delete.
- Impact: would break the "deleting a virtual row preserves the backing CUE/audio" rule; deletes a file other tracks depend on.
- Fix: make delete use the same predicate as `isCueSong`, or narrow `isCueSong` to `isCueVirtualPath`; ~2 lines + test.
- Evidence: Rust scanner (`rust_backend/crates/local/src/backend/library.rs:422-427`) always emits `cue+*` rows with a `#trackNN` path, so no producing path was found; verify edited/imported rows and older DB rows.
- Resolution: `76f2fb10`. `isCueBackedRow(path, format)` (virtual path, `.cue` path or `cue+*` format) is now the delete predicate in the song menu, batch delete and album multi-select; CUE rows only call `removeItem(s)`, never `deleteFile`. Covered by the CUE tests in `test/local_song_menu_actions_test.dart`, `test/local_album_cue_delete_test.dart` and `test/local_track_batch_delete_test.dart`: PASS.

### UX-001 [P3] [confidence: high] [RESOLVED]
- Location: `lib/l10n/arb/app_en.arb:3108` (`cueSplitConfirmMessage`), all locales
- Scenario: confirm dialog says "Files will be saved to the same directory", then a SAF folder picker opens.
- Root cause: copy not updated when the split moved to a picked destination.
- Impact: misleading prompt; files land outside the expected folder.
- Fix: reword to "You'll choose a destination folder next" in all arb files.
- Evidence: lib/widgets/local_song_file_actions.dart:146 always calls `PlatformBridge.pickSafTree()` after confirm.
- Resolution: `76f2fb10`. `cueSplitConfirmMessage` now says the destination folder is chosen next; the menu test asserts the full localized message: PASS.

### UX-002 [P3] [confidence: medium] [RESOLVED]
- Location: lib/widgets/local_song_file_actions.dart:186-207 (`splitLocalCue`)
- Scenario: split succeeds into a folder outside the scanned library → success snackbar, but no new songs appear.
- Root cause: no library rescan/add after export. Not a regression: the old SAF-source flow also wrote outside the library without rescanning.
- Impact: user must add the folder and rescan manually.
- Fix: after export, trigger an incremental scan when the tree is a library folder, else say where files went; small.
- Evidence: no scan call in the function; old flow (`26f8e71^`) had none either.
- Resolution: `76f2fb10`. After export, `cueSplitDestinationSource` matches the picked tree against library sources through physical-path keys and a removable-volume `<volume>:<relative>` key; a matching enabled source is rescanned via `startSourceScan`, otherwise the snackbar says the tracks were saved outside the library. Covered in `test/cue_split_test.dart` and `test/models_and_utils_test.dart`: PASS.

### UI-001 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/local_song_menu.dart:127-128`
- Scenario: virtual CUE row → menu shows Edit Metadata (always rejected at :246 with a snackbar) and Copy file path (copies `album.cue#track03`).
- Root cause: both options sit outside the `if (!cue)` block.
- Impact: dead option; clipboard gets a non-file path.
- Fix: hide Edit for `isCueVirtualPath`; copy `stripCueTrackSuffix(path)` or hide copy; ~3 lines + test update.
- Evidence: gating at :129 covers only gain/removeGain/analysis.
- Resolution: `76f2fb10`. Virtual CUE rows hide both Copy file path and Edit Metadata; the menu test asserts both labels are absent: PASS.

### BUG-003 [P3] [confidence: high] [RESOLVED]
- Location: `lib/widgets/local_song_menu.dart:183-190`
- Scenario: Rescan ReplayGain → Cancel → returns true; `LocalAlbumScreen._showTrackMenu` (`local_album_screen.dart:188`) refetches and rebuilds for nothing.
- Root cause: `runBatchReplayGain` returns void, branch returns true unconditionally.
- Impact: wasted refresh only; callers cannot tell cancel from change.
- Fix: return a bool from `runBatchReplayGain`; small.
- Evidence: branch body at :184-190.
- Resolution: `76f2fb10`. `runBatchReplayGain` returns `Future<bool>` (false on cancel) and the menu propagates it, so album refresh only runs after a change. `ReplayGain cancel reports no change` in `test/local_song_menu_actions_test.dart`: PASS.

### TEST-001 [P3] [confidence: high] [RESOLVED]
- Location: test/local_song_menu_actions_test.dart:124-152 (popover placement loop)
- Scenario: removing the `MornyeContextMenu` height constraint would still pass: 390x844 viewport with anchors at y=100/650 leaves room for the whole menu.
- Root cause: no short-viewport or mid-screen anchor case.
- Impact: popover scroll/clamp behavior (LTR/RTL, above/below) is unprotected.
- Fix: add a 390x420 case with a mid anchor; assert panel height <= free space and last item reachable only by scrolling.
- Evidence: viewport fixed at :75; only two anchor positions.
- Resolution: `76f2fb10`. Added a 390x420 viewport case with a mid-screen anchor: the panel is clamped above the button and the last item is only hit-testable after scrolling: PASS.

### TEST-002 [P3] [confidence: high] [RESOLVED]
- Location: test/local_song_menu_actions_test.dart (whole file)
- Scenario: Share, ReplayGain apply/remove, Edit Metadata, Go to album/artist and the CUE split confirm path have no tap tests.
- Root cause: tests cover only Play next, Add to queue, Copy path, Delete and split Cancel.
- Impact: regressions there (incl. BUG-001/BUG-002/BUG-003) pass CI.
- Fix: add tests alongside the fixes for those findings (mocked channel + share stub).
- Evidence: tapped labels at :161, :189, :198, :256, :268.
- Resolution: `76f2fb10`. `test/local_song_menu_actions_test.dart` now taps Share, ReplayGain apply/remove, Edit Metadata, Go to album/artist, Split confirm and both CUE delete paths (14 tests): PASS.

### TEST-003 [P3] [confidence: medium] [RESOLVED]
- Location: test/local_song_menu_actions_test.dart:199, :257, :269
- Scenario: a single zero-delay `runAsync` then `pumpAndSettle` waits for async lookups before tapping dialog buttons; a longer await chain could make the tap miss.
- Root cause: timing-based waits instead of a condition.
- Impact: possible flakiness (fails loudly, not silently).
- Fix: pump until `find.text(...)` matches, with a bounded loop.
- Evidence: test-auditor reading; not reproduced.
- Resolution: `76f2fb10`. Replaced fixed delays with `pumpUntilCondition`/`runAction`, which alternate short real delays with frame pumps until a condition holds under a 5 s deadline (loud failure on timeout): PASS.

### SEC-003 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/utils/file_access.dart:272` (`_cueTrackSuffix`)
- Scenario: a real file named `Song #track1` matches `#track\d+$` → cannot be deleted/opened; existence checks test the stripped path and report it missing.
- Root cause: suffix regex not anchored to a `.cue` base.
- Impact: rare; such files become undeletable or are cleaned up as missing.
- Fix: require `\.cue#track\d+$` (case-insensitive); ~3 lines + test.
- Evidence: helpers applied to every path in file_access.dart.
- Resolution: `76f2fb10`. Local paths are virtual only when they match `\.cue#track\d+$` (case-insensitive); `content://` URIs keep any trailing suffix, and `stripCueTrackSuffix` leaves other paths untouched. `test/models_and_utils_test.dart`: PASS.

### DATA-305 [P3] [confidence: medium] [RESOLVED]
- Location: `lib/services/ffmpeg_cue.dart:72-77` (`splitCueToTracks`)
- Scenario: one track fails → partial output not deleted, skipped with `continue`; shorter list returned with no signal; caller reports "n tracks".
- Root cause: no cleanup or partial-failure signal.
- Impact: silently incomplete split; truncated file left in staging.
- Fix: `FFmpegOutput.cleanup(outputPath)` on failure and return the failed count; ~4 lines. Pair with BUG-001/002.
- Evidence: caller `local_song_file_actions.dart:171` iterates `paths` only.
- Resolution: `76f2fb10`. `splitCueToTracks` returns `CueSplitResult(paths, failed)`, deletes a failed output before continuing and dedupes repeated output names with ` (2)`, so cleanup cannot remove another track; the caller merges the count into the partial-failure snackbar. `test/cue_split_test.dart`: PASS.

### SEC-201 [P3] [confidence: high] [RESOLVED]
- Location: `rust_backend/crates/local/src/backend/library.rs:161-170` (`resolve_cue_audio`, `exists`)
- Scenario: `FILE "../../x.flac"` outside granted roots → access-denied error propagates via `?`, so the same-stem/extension fallbacks (e.g. `album.flac` beside the CUE) are never tried; CUE dropped. Not a sandbox escape (`resolve` enforces granted roots).
- Fix: treat resolve/`native_display` errors in `exists` as `Ok(None)`; ~4 lines.
- Resolution: `76f2fb10`. `exists` maps a failed `resolve_legacy`/`native_display` to `Ok(None)`, so the same-stem fallbacks run; `cue_audio_outside_granted_roots_falls_back_to_the_sheet_stem` in `library.rs`: PASS. `check_rust_backend.sh` overall: 93 passed, 2 failed, 1 ignored; both failures (`actual_complete_dart_history_codec_and_path_identity_parity`, `production_dart_row_and_path_codec_parity`) are unchanged `crates/mobile` fixture drift reproduced at `d015e7d9` in a clean worktree (Rust emits lowercase path-key aliases the fixtures omit), outside T2.

### BUG-301 [P2] [confidence: high] [RESOLVED]
- Location: `lib/services/local_track_batch_actions.dart:51-58` (`deleteLibraryTracks`); callers `lib/screens/queue_tab_selection.dart:285`, `lib/widgets/library_search_results.dart:169`
- Scenario: batch-deleting CUE virtual rows from Songs/Search → `deleteFile` refuses virtual paths → counted as failed, rows stay, "delete failed" snackbar.
- Root cause: CUE branch present only in `local_album_screen._deleteSelected` (:145-163).
- Impact: CUE rows can never be removed outside the album screen.
- Fix: mirror the album-screen handling (skip file delete, `removeItems(ids)`); ~10 lines + test. Pair with DATA-001.
- Resolution: `76f2fb10`. `deleteLibraryTracks` skips `deleteFile` for `isCueBackedRow` rows and removes them with `removeItems`, matching the album screen. `test/local_track_batch_delete_test.dart`: PASS.

### TEST-301 [P2] [confidence: medium] [RESOLVED]
- Location: test/ (no file); `lib/widgets/local_song_file_actions.dart:81` (`deleteLocalSong`)
- Scenario: the AGENTS.md rule "deleting one virtual CUE row preserves the backing CUE/audio" has no test (`grep deleteLocalSong test` is empty); a regression would delete the album file under every sibling track.
- Fix: temp dir with album.cue + album.flac and two virtual rows; delete one row; assert both files remain and only that row is removed (~40 lines). Write it with the DATA-001 fix.
- Guards checked: none found.
- Resolution: `76f2fb10`. Added `test/local_track_batch_delete_test.dart` (cue+flac row, plain `.cue` row and a real song in one batch: both CUE files remain and only the song is deleted) plus the menu CUE delete tests: PASS.

## Rejected

### KT-001 [P3] [confidence: high] [REJECTED]
- Report: `reviews/fresh-audit-2026-10-23/` (kotlin; download-era ReplayGain policy)
- Scenario: `NativeReplayGainPolicy.kt` and its test are unused by the shipped player and were reported as deletion candidates.
- Rejection (T7): the owner keeps `NativeReplayGainPolicy` for the planned Media3/ExoPlayer port (STATE.md owner decision 2026-10-20; same decision recorded as R-013 for DEAD-909). The files stay unchanged.

### FA-RUST-001 [P2] [confidence: high] [RESOLVED]
- Report: `reviews/fresh-audit-2026-10-23/19-native-lyrics-parser.md` (RUST-001; Codex)
- Scenario: 100,000 leading `[00:01]` timestamps plus 4 MiB trailing text (~390 GiB of allocations from one crafted LRC).
- Resolution: `e6276a6` (T6). Reproduces RUST-403; the timestamp cap, word cap and expanded-output budget bound the expansion on both parsers (see RUST-403).

### DATA-307 [P3] [confidence: low] [REJECTED]
- Location: `lib/widgets/local_song_menu.dart:297-312`
- Scenario: each metadata edit writes a new `library_covers/edited_<ts>.jpg` and never deletes the previous one.
- Impact: one orphaned image per edit (may be swept by cover snapshot pruning; not verified).
- Fix: delete the old cover if it is under `library_covers` and differs.
- Rejection (T3): existing successful-scan cleanup calls `_pruneLibraryCoverCache` in `local_library_provider.dart`, targeting `library_covers` with reference-aware native/Dart pruning and a one-minute age threshold. Regular-file pruning includes `edited_*`; DB references protect current covers. Cleanup is eventual after a successful scan. Direct deletion before DB upsert was rejected in review and removed.

_False positives and intentional behavior, with one-line reason._

- R-001 (`/code-review` #8, share origin from screen context): Android-only app; `sharePositionOrigin` only affects iPad/macOS.
- R-002 (`/code-review` #9, split logic in a widget file): the old screen implementation was deleted, so there is no duplicate; no demonstrated impact.
- R-004 (test-auditor TEST-004, unawaited popover action): no pending future in that test; an open overlay at test end leaks nothing.
- R-005 (test-auditor TEST-005, plain `.cue` delete test): duplicate of DATA-001; its regression test belongs to that fix.
- R-006 (metadata DEAD-005, `cover_cache_manager.dart`): live upgrade-cleanup affordance used by `cache_management_page.dart`; UX note only.
- R-007 (kotlin KT-101, legacy SAF repair dialog probe): merged into UX-003.
- R-008 (kotlin DEAD-204/DEAD-205): duplicates of DEAD-002 and DATA-101; native parts added there.
- R-003 (`/code-review` #10, graphify commit title `81577e5` missing "code"): historical pushed commit; fixing needs history rewrite. Future commits follow the AGENTS.md wording.
- R-009 (build DEP-003, debug-key release signing): duplicate of SEC-302 from the parallel security pass.
- R-014 (ux-auditor UX-228, storage permission step cannot be skipped in setup): owner decision 2026-10-23, the storage permission stays required to finish setup.
- R-010 (tests TEST-302, settings migration/setup flags untested): covered — `settings_persistence_test.dart:72-73` asserts both flags in one write; `installation_restore_test.dart:97-117` sanitizes legacy download-folder fields.
- R-011 (perf PERF-403, `shuffleLibrary` full load): its only caller is the dead `player_queue_sheet.dart` (DEAD-601); the live `getAll()` caller is UX-101. DATA-002's `shuffleLibrary` part is likewise on that dead path.
- R-012 (SEC-301, `MANAGE_EXTERNAL_STORAGE` on API 30–32): owner keeps the permission.
- R-013 (DEAD-909 `NativeReplayGainPolicy` part): owner keeps it for the planned Media3/ExoPlayer port; the other DEAD-909 symbols stay open.
### OPT-PERF-004 [P2] [confidence: high] [REJECTED]
- Report: `reviews/optimization-2026-10-23/06-native-metadata-parsers.md` (code-optimization-auditor)
- Location: `rust_backend/crates/mobile/src/native_lyrics.rs` (`with_credits`, re-parsing the normalized TTML document after `parse_ttml`)
- Rejected 2026-10-24 (T6): measured before any change on the host (release build, wall time): 100-line TTML execute 3.9 ms with the credits re-parse at 0.6 ms; 500-line 9.8 ms / 1.7 ms; 2,000-line 33.5 ms / 5.2 ms (with songwriters: 24.8 ms / 7.0 ms). The second pass is 0.6–7 ms on pathological 2,000-line documents and sub-millisecond for realistic lyric files, on the bounded worker away from rendering; the audit itself flags the merge as parity-unsafe (the two passes intentionally differ in CDATA treatment). No user-visible cost; rejected with these numbers.
