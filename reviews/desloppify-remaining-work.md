# Desloppify review: what is not done yet, and why

Branch: `desloppify/code-health`. Strict score after the review import: 77.0 (target 85).
Source: 20 holistic review batches, imported with `desloppify review --import-run`.
Batch 2's prompt file and blind packet named different dimensions; the subagent followed
the prompt file (`high_level_elegance`), so that batch's scores should be re-checked.

## Fixed in this pass (verified in code before changing)

| Finding | Fix | Commit |
|---|---|---|
| naming_quality::double_underscore_state_class | `__AnimatedLibrarySliverGridState` renamed to `_AnimatedLibrarySliverGridState` | be881cf |
| naming_quality::unused_search_key_field | `_GroupedLocalAlbum.searchKey` removed (no readers) | be881cf |
| logic_clarity::async_wrapper_playlist_picker | `showAddTrackToPlaylistSheet` returns its Future directly | be881cf |
| logic_clarity::async_wrapper_update_dialog | `showUpdateDialog` returns its Future directly | be881cf |
| logic_clarity::bool_tail_collapse_update_checker | version comparison tail is one boolean expression | be881cf |
| logic_clarity::navigate_to_artist_unused_param_and_async | unused `artistId` removed (also from `ClickableArtistName` and its caller). The `async` is kept, see below | be881cf |
| type_safety::ignore_without_explanation_hud_protected_member | explanation added above the ignore | be881cf |
| ai_generated_debt::scan_notification_wrapper_boilerplate | six wrappers share `_notifyBestEffort` | next commit |

Partly fixed: `navigateToArtist` still has `async` with no `await`. Removing it changes the
function's return type from an async body, so it was left for a separate change.

## Not done, with reasons

### Needs a design decision first (large or cross-cutting)

- **cross_module_architecture / high_level_elegance: lower layers import screens** (utils, widgets,
  player components, models, theme and services import screens/widgets/providers). Fixing this means
  moving shared types down into lower layers; it touches most of `lib/`. Needs an agreed layer map.
- **package_organization: services depend on UI and providers** (services import providers and
  widgets). Same decision as above.
- **package_organization / high_level_elegance: flat folders** (`lib/widgets/` with about 65 files,
  `lib/services/` root stragglers, `screens/library/` holding only queue tabs, state and route folders
  of one or two files). Moving files is cheap but touches every import; the folder layout is a
  product-owner choice.
- **convention_outlier: shared widget prefixes** (`app_` vs `sistrum_`) and the `LogScreen` vs
  `*Page` naming. Renames across many files; needs a rule first.
- **convention_outlier: Songs/Playlists tab selection** does not use `SelectionModeMixin`. Behaviour
  change in the selection UI; needs UX check.
- **design_coherence: `PlatformBridge` facade breadth, `MusicPlayerHandler` mixed responsibilities,
  `LocalLibraryNotifier` mixed concerns, audio-analysis parsing inside a widget file.** Each is a
  multi-file split of core playback or library code, with risk to playback and scanning.
- **design_coherence / high_level_elegance: shared header primitives in `album_detail_header.dart`**
  (ten-plus screens import them). Moving them is mechanical but needs a header-design pass.
- **abstraction_fitness: AutoMix and Autoplay helpers reach into `MusicPlayerHandler` privates.**
  Fixing needs an explicit interface between the playback part-files and the handler.
- **mid_level_elegance: 20 sites decode library DB rows in two shapes; two access paths to the same
  DB.** A shared row decoder is a data-layer refactor with database-level tests needed.
- **mid_level_elegance: three artist paging loops; mutable priority map in a provider.** Behaviour
  of pagination and ordering needs tests before refactoring.
- **api_surface_coherence: `deleteByPath` vs `deleteByPaths` return contracts; queue paging return
  shapes; two snapshot writers sharing a stem.** Changing return types ripples through callers and
  tests; needs an agreed contract.
- **initialization_coupling: static cover-palette store, `PlatformBridge` static event state,
  `MusicPlaybackDeck` shared native channel state.** Tests must be rewritten around injected state.
- **dependency_health / cycles: `music_player_runtime` <-> `music_player_service`, and
  `clickable_metadata` -> screens -> `clickable_metadata`.** Both are real cycles (confirmed by two
  reviewers). Breaking them moves code across playback and navigation.

### Needs a product decision (behaviour change for users)

- **error_consistency: `ApkDownloader.downloadApk` returns null for SHA mismatch, invalid payload and
  network errors alike; `installApk` swallows installer failures.** Fixing changes what the updater
  shows users; the error copy and the retry behaviour must be chosen.
- **error_consistency: backup archive parsing returns null for corrupt, unsupported and I/O failures.**
  Same issue: the restore UI would need to report distinct failures.
- **error_consistency: mixed null/bool/exception signalling across services.** Needs one convention
  agreed first.
- **contract_coherence: `checkForUpdate` returns null without verification on non-Android.** The app is
  Android-only, so the branch never runs in the shipped app, but host tests can reach it. Changing it
  means changing what the tests assert; left for a decision.
- **mid_level_elegance: song menu lookup maps every exception to "file not found".** Narrowing the catch
  changes error messages users see.
- **mid_level_elegance: player collection lookup fabricates a `Track` when the library match fails.**
  Changing this could hide or show different playback state.

### Blocked by test environment

- **incomplete_migration: `supportsCoreBackend` Dart fallbacks, and `collections_forcelegacy_test_seam`.**
  `supportsCoreBackend` is `Platform.isAndroid`, which is false under the Linux host test runner. The
  Dart paths are what the tests exercise, so removing them means rewriting those tests around a native
  fake. The `forceLegacy` flag is a test seam in production code; removing it has the same dependency.
- **initialization_coupling / test_strategy: static state and wall-clock waits in widget tests.** Making
  these deterministic needs fake clocks and injected state across many test files.

### Test additions not yet made (lower priority)

- **test_strategy: `sistrum_icons.dart`, `player_slider`, `app_content_card`, `main_shell` have no
  direct tests.** Widget tests needed; `main_shell` is large (651 lines).
- **test_strategy: timing and polling waits in widget tests.** See above.

### Low-confidence items, not pursued

- **ai_generated_debt: repeated best-effort delete `try/catch(_)` idiom.** Shared helper would be
  reasonable, but the callers differ in what they log; left unchanged.
- **low_level_elegance: `_loadIndex` is a 160-line function with repeated cancellation guards;
  nested silent cover cleanup.** Refactor needs tests for the cancellation paths first.
- **convention_outlier: part-file vs library module split style.** Taste; no change proposed.
- **mid_level_elegance: silent synthetic track fallback** (low). Needs the product decision above.

## Other findings from this session (not from the review)

- **ProgressStreamPoller drops overlapping stream events.** The in-flight guard also applies to stream
  events, so a second event that arrives while the first is processed is discarded. If the discarded
  event is the latest progress, the UI can show a stale value. Found while writing tests; the test was
  adjusted to wait between events, and the behaviour was not changed. Needs a decision.
- **Dart `part` files are flagged as orphaned and untested by desloppify.** Suppressed locally with
  attestations; the finder should read `part` directives.
- **`supportsCoreBackend` is false in host tests**, which is the root of the blocked item above.

## Second pass (commit 9907c7b)

Fixed and resolved in the queue:
- api_surface_coherence::delete_by_path_return_contract_mismatch: `deleteByPath` now delegates to
  `deleteByPaths` and returns the deleted count.
- convention_outlier::log_screen_suffix_island: `LogScreen` renamed to `LogPage` (file `log_page.dart`).
- logic_clarity::async_callback_no_await_post_frame: `main_shell.dart` post-frame callback drops `async`.
- logic_clarity::async_no_await_hydrate_playlist_tracks: `Future.sync` keeps decode errors on the future.
- logic_clarity::navigate_to_artist_unused_param_and_async: `Future.sync` now; parameter removed earlier.
- mid_level_elegance::ad_hoc_play_count_keying: `_playsFor` helper for the artist ranking.

Deliberately not changed:
- logic_clarity::async_no_await_resolve_or_extract: stays `async`. Its cache-hit path can throw;
  removing `async` would turn a future error into a synchronous throw for callers.

Still open after this pass: 54 items in the queue. Of these, the larger groups are the layer and
package moves, the playback cycles, updater and backup error handling, the library row decoding and
the `supportsCoreBackend` test seam. The widget-test additions (shared icons, player slider, content
card, main shell) and the timing waits in widget tests are next on the list.

## Widget tests pass

Added direct tests for `sistrum_icons.dart`, `AppContentCard` and `SistrumPlayerSlider`. Resolved in the
queue: test_strategy::shared_icons_no_direct_tests and test_strategy::player_slider_and_content_card_untested.

Still open from the test list:
- test_strategy::main_shell_no_direct_test: `MainShell` builds the native playback runtime, so a test
  needs platform-channel fakes first.
- test_strategy::timing_polling_waits_in_widget_tests: widget tests still wait on wall-clock time.

Queue after this pass: 52 items.

## MainShell test attempt (not committed)

A smoke test that mounts `MainShell` under `MaterialApp.router` with a real `MusicPlayerRuntime`
(restore skipped) does not pass yet:

- Without advancing the fake clock, the test ends with a pending zero-delay timer from
  `_LazyTabViewState._schedulePreload` (the Search tab preload is an idle scheduler task that
  only runs when frames run).
- Advancing the clock at all (`pump(Duration)`, `pump(Duration.zero)`) runs that preload, and the
  Search tab then takes minutes to build under the test renderer. Flutter reports the run as "did not
  complete".

Fix options, none taken yet: allow the preload to be disabled for tests (a constructor flag or a
provider that `LazyTabView` reads), or give the shell a fake Search tab. Either is a small app-side
seam, so it needs a decision before it is added.

`main_shell_test.dart` was removed, not committed.

## Third pass (main shell test skipped)

Fixed and resolved in the queue:
- mid_level_elegance::lookup_catch_all_missing_file: only a missing row reports "file not found".
- low_level_elegance::redundant_nested_silent_cover_cleanup: the cache-trim try wraps only the delete.
- type_safety::quality_filter_string_literals: `LibraryQualityFilter` constants. The query keeps the
  string at its boundary, since unknown values must still be ignored (test covers this).
- naming_quality::folder_name_for_playlist_screen: `LibraryTracksFolderScreen` renamed to
  `LibraryCollectionTracksScreen` (only Loved and playlist modes exist).

Queue after this pass: 48 items. The next items are the layer and package moves, the playback cycles,
updater and backup error handling, the row-decoding consolidation, and the test-environment items.

## Fourth pass

Fixed and resolved in the queue:
- mid_level_elegance::shared_mutable_priority_map: the artist Popular random tie-breaks live in a
  small per-page class with a `drawFor` method; the provider no longer returns a mutable map that its
  consumer mutates. Behaviour is unchanged (draws still persist across index refreshes and are
  released with the page's last listener).

Left open with reasons:
- low_level_elegance best-effort delete `catch (_) {}` idiom: it appears at dozens of sites, several
  of which are deliberate best-effort cleanup. A shared helper would touch most of the library and
  audio-analysis files for no behaviour change, so it is not pursued in this pass.

Queue after this pass: 47 items.

## Fifth pass

Fixed and resolved in the queue (commits dc17c94 and the test-helper commit):
- api_surface_coherence::queue_paging_return_shape_drift: `…Page` names return pages, `…Rows` names
  bare lists; the list-only track wrapper is gone.
- api_surface_coherence::snapshot_writer_overload_by_name: `exportNativeFileModTimesSnapshot` (DB
  export) and `writeFileModTimesTsv` (Dart map).
- contract_coherence::update_check_unverified_null_non_android: the contract names the non-Android null.
  Behaviour is unchanged.
- test_strategy::timing_polling_waits_in_widget_tests: `test/support/pump_until.dart` replaces four
  hand-rolled loops, keeping each test's delay and pump step.
- mid_level_elegance::duplicated_paging_loops: the artist playback queue and Popular selection share one
  page generator and one page size.
- logic_clarity::async_no_await_resolve_or_extract: no `async`; `Future.sync` keeps synchronous failures
  on the returned Future.
- mid_level_elegance::silent_synthetic_track_fallback: the fallback is logged at debug level.
- incomplete_migration::collections_forcelegacy_test_seam: production readers no longer take
  `forceLegacy`; tests call the `…ForTesting` Dart readers.
- high_level_elegance::library_folder_holds_queue_tab and state_and_route_homes_split_at_top_level:
  `QueueTab` is `LibrarySectionTab` (files `library_section_tab*`), controllers are in providers and the
  route file is in screens.
- convention_outlier::library_tab_selection_protocol: documented, not migrated. The tab needs range
  anchors, a playlist selection mode and an overlay before the mixin can take it.

Left open with reasons:
- naming_quality::queue_name_for_library_browser: `QueueTab` is renamed, but `QueryLibraryDb*` and the
  browser naming still need a decision on the new names.
- ai_generated_debt::repeated_inline_best_effort_delete (and the earlier note): a shared helper would touch
  dozens of sites for no behaviour change.
- convention_outlier::shared_widget_prefix_split: `app_` and `sistrum_` widgets are both theme-bound, so
  no prefix rule is accurate yet. The owner should choose the rule.
- convention_outlier::part_file_split_style_mixed: needs a convention decision before it is recorded.
- error_consistency::* (APK downloader, backup parsing, failure signalling): these change what the user
  sees and need new localized messages, so they need product decisions first.
- cross_module_architecture, dependency_health, design_coherence, package_organization and the
  player-runtime cycles: these need the layer and package moves approved (see the earlier notes).
- low_level / initialization items (CoverPalette store, PlatformBridge statics, MusicPlaybackDeck state,
  load index sprawl): they need lifecycle designs, not mechanical edits.
- mid_level_elegance::scattered_row_decoding and two_db_access_paths: about twenty row-decoding sites
  and two database access paths. They need one repository boundary decided first.
- main_shell_no_direct_test: blocked as recorded above.

Queue after this pass: 36 items.

## Shared widget names

The rule is in AGENTS.md under "Shared widget names". Classification of the 15 prefixed widgets:

- `sistrum_` (Sistrum's own pieces): `sistrum_bottom_bar`, `sistrum_slider`,
  `sistrum_context_menu`, `sistrum_metadata_row`, `sistrum_artist_header`.
- `app_` (generic building blocks, themed by Sistrum): `app_switch`, `app_alert_dialog`,
  `app_bottom_sheet`, `app_snack_bar`, `app_search_field`, `app_action_button`, `app_choice_chip`,
  `app_content_card`, `app_loading_indicator`, `app_sliver_header`.

No files were renamed. `app_switch`, `app_alert_dialog` and `app_bottom_sheet` read Sistrum theme
values, which the rule treats as styling, not as a reason for the Sistrum prefix. `app_sliver_header`
is the header every tab and settings page uses, and `app_content_card` is a plain surface.

## Playback pass

Resolved in the queue (commits d64dac6, the bridge commit and the graph refresh):
- abstraction_fitness::playback_part_file_handler_leak: AutoMix works through `AutoMixHost`, and
  Autoplay through `AutoplayQueueView`. The handler's private state is reached only by the adapters.
  Autoplay has fake-queue tests.
- cross_module_architecture::playback_runtime_service_export_cycle and
  dependency_health::playback_runtime_service_import_cycle: the runtime imports no service file. The
  handler type it uses is the abstract `PlaybackHandler`, and the concrete handler, the restore function
  and the process runtime are injected through `PlaybackDependencies` from the service library.
- design_coherence::playback_handler_mixed_responsibilities: the sleep timer, play history, audio focus
  and volume/headphone inputs moved into `playback_policies.dart` with unit tests. Session persistence
  still composes in the handler on top of `PlaybackSessionWriter`, and transport and queue stay in the
  handler.
- initialization_coupling::music_playback_deck_shared_native_channel_state: `UsbPcmBridge` holds the
  channel, the shared event stream and the ticket sequence, and each deck receives it.
- low_level_elegance::load_index_guard_and_lease_sprawl: `_loadIndex` is split into announce, lease,
  output and publish steps, with one lease release path.

Not in this pass:
- initialization_coupling::platform_bridge_static_event_state: `PlatformBridge` is the app-wide native
  bridge for SAF, scanning and metadata, not a playback class. It needs its own pass.

## Playback library split

AutoMix and Autoplay are libraries now, not part files of the service. Their adapters
(`_HandlerAutoMixHost`, `_HandlerAutoplayQueue`) live in the service library, which is the only code that
touches the handler's privates, and the service has no `part` directives. `resetAutoplayLearning` moved
beside the handler it configures, and the shared audio context moved to the deck library.

The large-file part-file item still covers the Library, audio-analysis and collection files that keep
their parts, so it stays open for those.

## Layer and header pass

- `lib/utils` has no screen or widget imports now. `clickable_metadata.dart` moved to
  `screens/detail_navigation.dart`, and `confirm_and_delete_tracks.dart` moved to `widgets/`.
- The generic header primitives moved to `widgets/header_controls.dart`. `AlbumPlayActions` stays with the
  album header.

Still open, with reasons:
- The album and artist screens import `detail_navigation.dart`, and it builds those screens, so the cycle
  remains. Breaking it needs a route-builder design, which is a decision.
- `audio_analysis_widget.dart` mixes ffmpeg parsing with the card UI, and it uses part files for its
  models, info card and spectrogram. Splitting it changes its library structure and touches four
  importers, so it is a separate pass.

## Library and navigation move pass

Code commit `580f8e4`, graphify commit `197e07d`.

Done:
- Navigation services moved to `lib/navigation/` (`shell_navigation.dart`, `app_navigation.dart`).
- Library-only helpers moved under `lib/services/library/`; playback helpers under
  `lib/services/playback/`; audio-analysis cache and jobs under `lib/services/audio_analysis/`.
- Library batch and track action widgets moved from services into `lib/widgets/library/`.
- Library folder selection, file deletion and source removal depend on the new
  `LibrarySourceSink` and `LibraryRemovalSink` interfaces (`lib/services/library/library_mutation_ports.dart`),
  which `LocalLibraryNotifier` implements. No `lib/services` file imports providers or widgets.
- No `lib/utils` file imports screens or widgets.

Verification: `flutter analyze` reports "No issues found!"; full `flutter test` passes (serial run).
A stale path in `test/models_and_utils_test.dart` (`lib/services/app_state_database.dart`) was found
by the first run and fixed to `lib/services/storage/app_state_database.dart`.

Still open in the queue (26 items at the end of this pass): the best-effort delete helper, part-file
style rule, the album/artist/detail navigation cycle, audio-analysis parsing in the widget, the
library notifier and PlatformBridge splits, APK downloader failure types, backup parse failures,
the failure-convention doc, CoverPalette instance store, library DB row decoding, QueryLibraryDb naming,
`unified_library_item` importing `library_database_models`, the main-shell test, and the remaining
services and widgets root files. Desloppify has 41 resolved items staged for commit; they are recorded
once the queue is empty and `desloppify scan` runs.

## Cover, download, backup and screen-seam pass

Commits `8feb431` (cover palette), `17e07ea` (APK results), `9e01e2f` (backup parse failures),
`37aa3b8` (screens seam).

Done:
- `CoverPalette` statics became `CoverPaletteCache`, an instance built with its store; the app shares
  `coverPalette`, and tests create their own cache (no manual swap or clear).
- `ApkDownloader.downloadApk` returns `ApkDownloaded` or `ApkDownloadFailed(reason)`, and
  `installApk` returns an `ApkInstallOutcome`. The update dialog shows a message per reason.
- `BackupService.parseFile` throws `BackupParseException` with a reason (not a backup, unsupported
  version, corrupt archive, unreadable) instead of returning null. The restore page words each one.
- Navigation no longer imports screens: `lib/navigation/app_screens.dart` defines `AppScreens`
  (artist, album, collection and now-playing pages), installed through `appScreensProvider` in
  `main.dart` and in the affected tests. The now-playing route moved to `lib/navigation`, the
  metadata editor sheet to `lib/widgets/library`, and `LibraryCollectionMode` to the collections model.
- No `lib/navigation`, `lib/widgets`, `lib/utils`, `lib/services`, `lib/providers`, `lib/theme`
  or `lib/models` file imports `lib/screens`.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (1888 tests).

Still open: the best-effort delete helper, the part-file style rule, the audio-analysis parsing
extraction, the local library notifier and PlatformBridge splits, the failure-convention doc,
supportsCoreBackend fallbacks, the library DB row decoding and database access paths, the
QueryLibraryDb naming, `unified_library_item` importing `library_database_models`, the main-shell
test, and the services and widgets root-file reorganisation.

## Code-health queue pass (commit 343d940)

Queue at the start of this pass: 26 open items (`uvx desloppify plan`). The snapshot
(501f373) was taken before several earlier passes, so some items were already fixed in code
and were verified by import or type checks rather than by changing files.

Resolved in code (verified, 19 items):
- cross_module_architecture: album/artist/clickable-metadata cycle and lower layers importing
  screens (only `lib/app.dart` and `lib/main.dart` import screens now).
- dependency_health: clickable_metadata -> screens cycle (the file moved to `navigation/`).
- design_coherence: audio-analysis parsing moved to `services/audio_analysis/audio_analysis_parsing.dart`
  (the widget re-exports it); `LocalLibraryNotifier` scan notices extracted to
  `services/library/library_scan_notifications.dart`; `PlatformBridge` split into
  `MediaFileBridge`, `LibraryScanBridge` and `CueSheetBridge` over `services/native/native_channel.dart`.
- error_consistency: APK download and install outcomes and backup parse failures were typed in an
  earlier pass; verified.
- high_level_elegance / cross_module: theme no longer imports widgets or providers (cover maths to
  `utils/`, cover palette to `services/`, theme wrapper to `widgets/`); services root regrouped
  (library and playback files moved into their folders); widgets root reduced to six shared files.
- initialization_coupling: cover palette cache is an instance (earlier pass, verified).
- mid_level_elegance: library browser providers read `libraryDatabaseProvider`, so the process
  singleton has one seam in providers (`two_db_access_paths`). Constructor defaults still use
  `LibraryDatabase.instance`.
- model_depends_on_persistence: `LocalLibraryItem` moved to `models/`.
- naming_quality: library browser names use `LibraryBrowse*` / `getBrowse*` (no `Queue` prefix).
- package_organization: no service imports providers, widgets or screens; library screens sit in
  `screens/library/`; widgets are grouped into `header/`, `shell/`, `selection/`, `sheets/`, `status/`.

Partly done (left open in the queue):
- initialization_coupling::platform_bridge_static_event_state: the event stream and handler flag
  moved to `NativeBackendEvents`; the data-job map is still a static in `PlatformBridge`.
- mid_level_elegance::scattered_row_decoding: `LocalLibraryItem.fromEnvelope` covers four
  `{source, item}` sites. `music_player_autoplay.dart` and several other decoders are unchanged.
- ai_generated_debt::repeated_inline_best_effort_delete: `deleteBestEffort` replaces the 19 exact
  `try { if (exists) delete } catch (_) {}` idioms. Other catch shapes stay, since they log or
  act differently.

Open, with reasons:
- convention_outlier::part_file_split_style_mixed: needs an agreed rule (part files vs library
  modules). Not decided in this pass.
- mid_level_elegance::mixed_null_bool_exception_failure_signalling: needs one convention for
  service failures. The APK and backup paths already use typed results; the rest is not migrated.
- incomplete_migration::supports_core_backend_dart_fallbacks: the Dart branches are what the host
  tests run (`supportsCoreBackend` is `Platform.isAndroid`). Removing them needs native channel
  doubles for the data-job, scan, collection and backup paths.
- test_strategy::main_shell_no_direct_test: `MainShell` builds the native playback runtime and
  the lazy Search-tab preload. A test needs platform fakes and a preload switch first.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (1888 tests, exit 0). The desloppify scan was not re-run: `.desloppify/` state is
tracked and was not updated, so the queue in that state is unchanged.

## Open-items pass (commits d5528a1, 2a2b106)

The four items still open after the code-health pass:
- test_strategy::main_shell_no_direct_test: resolved. `MainShell` takes `preloadTabs`, so a test
  can skip the idle Search preload. `test/main_shell_test.dart` mounts the shell under a router
  with the app's localizations and settings, and checks it settles without exceptions.
- convention_outlier::part_file_split_style_mixed: rule written in AGENTS.md ("Part files").
  Twelve hand-written part files remain. Each shares private members with its owning library
  (a `State` class, or the audio-analysis widget internals), so each stays a part. Converting the
  audio-analysis models was tried and reverted: the file also holds private widget helpers.
- mid_level_elegance::mixed_null_bool_exception_failure_signalling: convention written in
  AGENTS.md ("Failure signalling in services"). `MediaFileBridge.editFileMetadata` now returns the
  typed `MetadataEditResult`, and `writeTempToSaf` is removed in favour of
  `writeTempToSafDetailed`. Cover embedding and ReplayGain report failed edits instead of ignoring
  them. Other service APIs are not migrated yet.
- incomplete_migration::supports_core_backend_dart_fallbacks: still open. Removing the Dart
  branches needs native channel doubles for the data-job, scan, collection and backup paths in
  the host tests. That is a separate piece of work.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (1889 tests, exit 0).

## supportsCoreBackend removal (commit 3955d5e)

- incomplete_migration::supports_core_backend_dart_fallbacks: resolved. The
  `PlatformBridge.supportsCoreBackend` getter and every gate on it are gone. Android always runs
  the native backend, so the Dart branches were reachable only on the host. Removed with them:
  Dart ZIP archive reading and writing, Dart scan ingestion and mod-time snapshots, the desktop
  cover-prune worker, the Dart collection restore, the incremental scan wrappers, and the
  `prepareCollectionRestoreCommands` builder.
- Host tests keep the Dart collection reader below the native row threshold. Archive round
  trips (direct JSON, large collections, and the rejection cases) moved to
  `integration_test/native_backup_archive_test.dart`. The stale host tests for the removed Dart
  paths were deleted: `backup_service_v2_test.dart`, `library_scan_snapshot_test.dart`, and three
  cover-prune cases in `library_cleanup_test.dart`. Native coverage for those lives in
  `integration_test/native_cache_maintenance_test.dart` and `native_library_staging_test.dart`.
- The incremental-scan channel handlers in `MainActivity.kt` are removed. The core-backend scan
  stays for the native `library_scan_incremental` job and the instrumentation stress test.
- `archive` moved from runtime to dev dependencies; only test fixtures use it.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (exit 0). `scripts/check_android.sh` could not run in this environment (no Gradle wrapper
or Android SDK), so the Kotlin change is verified by reading only. The Android unit checks and
the device integration suite still need a run on a machine with the SDK.

## Best-effort delete cleanup (commit 4df8207)

- ai_generated_debt::repeated_inline_best_effort_delete: resolved. Exact delete-if-exists
  try/catch blocks in `backup_service`, `metadata_cover_resources`, `library_scan_bridge` and
  the collections provider now call `deleteBestEffort`. The catch blocks left in `lib/` guard
  parsing or callbacks, not deletes.
- The desloppify state files were updated and are committed with this entry. Resolving items
  through `plan resolve` (with notes and attestations) took the queue from 26 items to 17:
  the layer-inversion, import-cycle, services-to-UI, unified model, supportsCoreBackend and
  main-shell items, each checked against the code by grep before resolving.
- Remaining queue (17 items), grouped into five tasks: failure signalling (4), bridges and
  static state (3), library data access (3), layout and naming (5), audio analysis and part
  files (2).

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (exit 0).

## Task 1: failure signalling (commits 6092677, e556ae9)

- error_consistency::apk_download_null_hides_failure_reason and
  apk_install_error_swallowed: already fixed. `ApkDownloader.downloadApk` returns
  `ApkDownloadResult` with a specific `ApkDownloadFailure`, and `installApk` returns
  `ApkInstallOutcome`. The update dialog branches on both.
- error_consistency::backup_parse_failures_collapse_to_null: already fixed. `BackupService.parseFile`
  throws `BackupParseException` with a reason.
- error_consistency::mixed_null_bool_exception_failure_signalling: user-visible ReplayGain writes
  return `ReplayGainWriteResult` with a `ReplayGainWriteFailure`. FFmpeg tag writers and the
  playlist cover resize throw `FFmpegMetadataFailure`. Internal probes such as the trigram FTS
  check keep `bool`, because the user never sees their failure.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (exit 0).

## Task 2: bridges and static state (commits 52a5c86, e659392)

- design_coherence::platform_bridge_facade_breadth: `PlatformBridge` is split into
  `NativeDataJobs` (run, cancel), `NativeDevice` (screen wake, exit, backend identity, memory),
  `NativeBackgroundWork` (foreground-service start, update, stop) and `NativeInstallation`
  (install marker). The facade file is removed.
- initialization_coupling::platform_bridge_static_event_state: the job map and serial moved into
  `NativeDataJobs`, with an `activeJobCount` hook. `NativeBackendEvents` gained
  `debugResetHandler`, so a test that replaces the channel mock can reinstall the handler.
- initialization_coupling::cover_palette_global_store_seam: the global `coverPalette` is now
  `coverPaletteProvider` in `lib/providers`. Widgets read it through `paletteOf(context)` or `ref`.
  `CoverPaletteBuilder` takes its cache as a parameter, and `PlayerWidgetService` receives it at
  `initialize`. `main.dart` runs an explicit `ProviderContainer` so that service can share it.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (exit 0).

## Task 3: library data access (commits c7d0c9c, 23c882c, 5dc5be1, 69cb40a)

- design_coherence::local_library_notifier_mixed_concerns: the scan progress decisions are a pure
  function, `readLibraryScanProgress`, and the stream-then-poll timing lives in
  `LibraryScanProgressPolling`. Both are in `lib/services/library/library_scan_progress.dart`. The
  notifier applies the sample and posts the notice. Cover request keys and batched first-cover
  lookups live in `lib/providers/local_library_cover_providers.dart`.
- mid_level_elegance::two_db_access_paths: database access goes through `libraryDatabaseProvider`.
  Widgets and notifiers read it through `ref`. Helpers without a `ref` take the database as a
  parameter: `runBatchReplayGain`, `navigateToAlbum`, `navigateToArtistCredits`,
  `MetadataIndexReconciler.upsert`, the cover analysis store, and `PlaybackDependencies`. The one
  remaining direct `LibraryDatabase.instance` is the composition root of the background audio
  service (`music_player_service.dart`), which runs outside the widget tree.
- mid_level_elegance::scattered_row_decoding (item 12): the `{source, item}` envelope decode goes
  through `LocalLibraryItem.fromEnvelope` in the section tab.

The desloppify notes recorded for items 3 and 13 in an earlier pass described them as partial.
This entry supersedes those notes.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (exit 0).

## Task 5: audio analysis and part files (commits d97606e, da4721f)

- design_coherence::audio_analysis_parsing_in_widget: FFmpeg log parsing (channel stats, astats
  integers), total-sample estimation, codec and container labels, stored-bit-depth
  classification, and the spectral cutoff estimate moved from the card widget to
  `lib/services/audio_analysis/audio_analysis_parsing.dart`. The card keeps FFmpeg orchestration,
  caching and presentation.
- convention_outlier::part_file_split_style_mixed: the part-file rule is in AGENTS.md. Twelve
  part files remain. Each shares private State or library members with its owner, so each stays a
  part. Services use library modules.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (exit 0).

## Task 4: layout and naming (commits 929721c, 55af2a3)

- package_organization::services_root_stragglers: the Library cover palette moved to
  `services/library`, the backup service to `services/backup`, and the equalizer preset I/O to
  `services/playback`. Seven app-level files remain at the root.
- high_level_elegance::services_flat_catch_all_with_ui_glass: no glass rendering or navigation
  state remains under `lib/services` (checked by grep). The folder holds 95 files in subfolders.
- naming_quality::queue_name_for_library_browser: no `QueueTab` or `queue_tab` identifiers remain.
- package_organization::library_screens_split_across_folders: library section and collection screens
  live in `lib/screens/library`. The screens root holds app-level screens only.
- package_organization::widgets_flat_overload: `lib/widgets` has six top-level files; the rest are
  in subfolders.
- mid_level_elegance::scattered_row_decoding: the `{source, item}` envelope key is read in one
  place, `LocalLibraryItem.envelopeItem`.

Verification: `flutter analyze` reports "No issues found!"; the full serial `flutter test` run
passed (exit 0).

## Naming: app_ and App prefixes

- Every UI identifier now uses the `app_` file prefix and `App` class prefix: the theme is
  `AppTheme` (`lib/theme/app_theme.dart`), and the glass, chrome, slider, context-menu and player
  widgets follow the same scheme. The test-only helper formerly named `AppTheme` is
  `MaterialTestTheme`.
- Kept on purpose: `SistrumApp`, the `sistrum` package and Android package, the displayed app name,
  and persisted or external values (preference keys such as `sistrum_accent`, backup and export file
  prefixes, PNG names, channel names, performance suite labels).

Verification: `flutter analyze` reports "No issues found!". The full serial `flutter test` passed
(1878 tests, exit 0) in the expanded-reporter run. An earlier full run reported one failure
(`lyrics_screen_awake_test.dart` / `local_album_playback_controls_test.dart`, shown as `-1`) that
does not reproduce when those files run alone or in the later full run; it is recorded as an
intermittent, order-dependent failure to investigate separately.
