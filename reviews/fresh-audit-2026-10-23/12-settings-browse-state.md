# Settings and local browse state

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

## Scope

Source d5d5a02 unchanged at HEAD5179dfea. Roles bug-hunter, two disjoint chunks. No app edits; prompt-only read restrictions. Graph queries for settings and browse completed but were truncated, used only as navigation; explain LibrarySearchStore/LibraryQueueStore completed.

STATE-01 complete: lib/providers/settings_provider.dart1–593,theme_provider.dart1–124,user_profile_provider.dart1–39,custom_font_provider.dart1–8; lib/models/settings.dart1–308,settings.g.dart1–154,theme_settings.dart1–138,metadata_separators.dart1–73,sistrum_glass.dart1–59 (1,496 lines).
S1: lib/main.dart65–115,420–510; app.dart24–62; screens/settings/backup_restore_page.dart27–155,appearance_settings_page.dart22–38,135–155; screens/now_playing_screen.dart145–175,track_metadata_edit_sheet.dart302–335; widgets/local_song_menu.dart245–300; controllers/metadata_editor_controller.dart60–112; providers/local_library_provider.dart580–650; services/user_profile_store.dart1–127,custom_font_service.dart1–96,sistrum_glass_migration.dart1–41. T1 test source: settings_persistence_test.dart1–239,theme_provider_persistence_test.dart1–133.

STATE-02 complete: lib/providers/library_browse_provider.dart1–234,library_search_provider.dart1–55,local_artist_provider.dart1–201,local_home_feed_provider.dart1–50; lib/models/album_track_order.dart1–38,download_history.dart1–241,track.dart1–224,track.g.dart1–69,unified_library_item.dart1–149 (1,261 lines).
S1/S2 complete: lib/services/library_search.dart,library_playlist_search.dart,library_database_models.dart; test/local_artist_popular_test.dart,local_home_feed_test.dart. Ranges: library_database.dart145–185,600–650; library_queue_store.dart1–240,400–540,760–835; widgets/library_search_results.dart1–160,185–240,280–410; screens/settings/library_settings_page.dart450–490; screens/sistrum_library_screen.dart225–240,280–310; screens/local_artist_screen.dart45–72,100–155,265–290. local_library_provider.loadedIndexVersion increments searched, not whole-file certification.

## Findings

### BUG-001 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/providers/settings_provider.dart:198, _drainSettingsSave.
- Scenario: settings backup restore hits setString(false) or a thrown persistence error; UI reports successful restore but settings disappear after restart.
- Root cause: drain ignores boolean failure and catches errors before completing successfully.
- Impact: false durable-restore success.
- Fix: checked persistence path for restore; preserve ordinary setters' intentional logged-error API if needed.
- Evidence: restore245 awaits drain; backup_restore_page125–128 awaits restore then142–150 displays success.
- Cross-refs: backup_restore_page.dart; settings_persistence_test179–208 preserves ordinary setter behavior only.
- Guards checked: coalescing waits but never propagates failure; page error handler cannot see it; setFirstLaunchComplete separate checked save does not protect restore. Coordinator independently reread drain/restore and UI success path.

### BUG-002 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/providers/settings_provider.dart:236, restoreFromBackup.
- Scenario: completed installation imports legacy backup with isFirstLaunch:false but missing hasCompletedTutorial; import defaults tutorial false and immediately recreates setup routing.
- Root cause: backup import does not preserve completion or apply legacy completion normalization.
- Impact: unexpected onboarding after restore, persisting when migration version already12.
- Fix: preserve installation completion or normalize before publishing import.
- Evidence: settings.g87 missing-field false; restore236–243 preserves only storage; app27/31–49 watches both flags and routes /setup.
- Cross-refs: _runMigrations166–169 repairs legacy state only during initial loading below current migration version.
- Guards checked: glass migration unrelated; model default/version gate do not protect import. Coordinator reread migration, restore and routing.

### BUG-003 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/providers/library_search_provider.dart:51, librarySearchProvider.
- Scenario: disable Local Library after indexing; Library overview search still returns its tracks/albums/artists and song results play.
- Root cause: watched localLibraryEnabled value discarded; includeLocal always true.
- Impact: search bypasses disabled-library setting.
- Fix: forward watched setting to includeLocal.
- Evidence: LibrarySearchResults330 watches provider without gate; SistrumLibraryScreen299 displays it for overview query; database157–171 forwards flag; LibrarySearchStore honors false; search result191–209 plays local item directly.
- Cross-refs: lib/services/library_search.dart,library_database.dart; widgets/library_search_results.dart; screens/sistrum_library_screen.dart,settings/library_settings_page.dart.
- Guards checked: library_visible enforces individual source availability only; setting watch recomputes without filtering. Coordinator independently read full provider and caller/result ranges.

### BUG-004 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/services/library_queue_store.dart:409–412, _queueAlbumUnionSql.
- Scenario: artist release A date20250101 and newer B date2026-01-01; raw descending text comparison places A before B and features it.
- Root cause: only release-date-newest applies date normalization; artist-releases-newest uses raw tags.
- Impact: incorrect artist featured release/discography chronology for valid mixed date formats.
- Fix: normalize artist release ordering with metadataReleaseDateSql too.
- Evidence: artist screen45–50 selects mode; query450 sets sort_release from raw releaseOrder; order816–820 descends it; artist290 features first entry; helper20–35 supports compact/ISO.
- Cross-refs: local_artist_screen.dart,library_browse_provider.dart,library_queue_store.dart.
- Guards checked: entry mapping/screen preserve SQL order; releaseDatedOnly excludes artist mode. Coordinator reread409–412 and ordering terms.

## Verification / limits

Static guards reread as recorded. Tests listed are source inspection only; no Flutter/runtime tests/builds/devices executed. No findings asserted for Popular cap/full-queue separation or artist navigation: coordinator checked _openPage106 and confirmed LocalArtistScreen guard. Broader SQL/provider lifecycle coverage remains separate. Result FINDINGS: four P2.
