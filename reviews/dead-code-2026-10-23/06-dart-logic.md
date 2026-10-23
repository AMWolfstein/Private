# Dart logic dead-code review (D1)

## Scope

Role dead-code-hunter; baseline47039b90, applicationd5d5a02 unchanged. All144 paths in lib/{services,providers,controllers,models,utils} filename/import/export and declaration candidate-screened; not whole-body correctness review. Graph unused/orphan query completed truncated; explain HistoryMaintenanceUpdate/navigateToTrackAlbum each showed definition edge only, source proof authoritative.

Bounded reads: services/csv_import_service.dart1–177,history_maintenance.dart1–69; providers/music_player_provider.dart130–215,local_library_provider.dart35–90; utils/clickable_metadata.dart1–132,audio_format_utils.dart130–220; test/album_completeness_query_test.dart75–110. Final candidate search across lib,test,integration_test,Android,Rust crates,assets/config/scripts excluding reports/generated graphs/vendor bodies. Coordinator independently reread all five declaration bodies and searched candidate refs.

## Findings

### DEAD-007 [P3] [confidence: high] [VALIDATED — static]

- Location: lib/services/history_maintenance.dart:7, HistoryMaintenanceUpdate.
- Scenario: maintain current local player; obsolete uncalled API remains alongside retained implementation.
- Root cause: definition remained after consumers disappeared.
- Impact: unnecessary API/behavior maintenance; no runtime or measured binary-size claim.
- Fix: Remove class7–15 and now-unused DownloadHistoryItem import (~10 lines).
- Evidence: Class/constructor are the only references; transaction helpers never use it.
- Cross-refs: repository production/test/config reference census and enclosing file.
- Guards checked: plain Dart declaration, no framework/interface override, generated/native/channel, serialization/asset/reflection entrypoint; tests checked beyond simple token counts.
- Removal risk: low static risk; analyze/full tests required for actual removal.

### DEAD-008 [P3] [confidence: high] [VALIDATED — static]

- Location: lib/providers/music_player_provider.dart:181, MusicPlayerController.shuffleLibrary.
- Scenario: maintain current local player; obsolete uncalled API remains alongside retained implementation.
- Root cause: definition remained after consumers disappeared.
- Impact: unnecessary API/behavior maintenance; no runtime or measured binary-size claim.
- Fix: Remove181–194 (~14 lines), preserve live shuffle/playback controls.
- Evidence: No production/test invocation or tear-off. Test local variable shuffleLibrary108–111 is localized text, not method call.
- Cross-refs: repository production/test/config reference census and enclosing file.
- Guards checked: plain Dart declaration, no framework/interface override, generated/native/channel, serialization/asset/reflection entrypoint; tests checked beyond simple token counts.
- Removal risk: low static risk; analyze/full tests required for actual removal.

### DEAD-009 [P3] [confidence: high] [VALIDATED — static]

- Location: lib/utils/clickable_metadata.dart:74, navigateToTrackAlbum.
- Scenario: maintain current local player; obsolete uncalled API remains alongside retained implementation.
- Root cause: definition remained after consumers disappeared.
- Impact: unnecessary API/behavior maintenance; no runtime or measured binary-size claim.
- Fix: Remove wrapper/private helper/Track import (~18 lines).
- Evidence: No caller; private _preferredAlbumArtist solely used by this wrapper. navigateToAlbum remains live independently.
- Cross-refs: repository production/test/config reference census and enclosing file.
- Guards checked: plain Dart declaration, no framework/interface override, generated/native/channel, serialization/asset/reflection entrypoint; tests checked beyond simple token counts.
- Removal risk: low static risk; analyze/full tests required for actual removal.

### DEAD-010 [P3] [confidence: high] [VALIDATED — static]

- Location: lib/utils/audio_format_utils.dart:195, displayFormatForCodec.
- Scenario: maintain current local player; obsolete uncalled API remains alongside retained implementation.
- Root cause: definition remained after consumers disappeared.
- Impact: unnecessary API/behavior maintenance; no runtime or measured binary-size claim.
- Fix: Remove195–211 (~17 lines), retain live normalization functions.
- Evidence: Repository exact-symbol search yields declaration only; no exported alias or dispatch mapping.
- Cross-refs: repository production/test/config reference census and enclosing file.
- Guards checked: plain Dart declaration, no framework/interface override, generated/native/channel, serialization/asset/reflection entrypoint; tests checked beyond simple token counts.
- Removal risk: low static risk; analyze/full tests required for actual removal.

### DEAD-011 [P3] [confidence: high] [VALIDATED — static]

- Location: lib/providers/local_library_provider.dart:72, LocalLibraryState.existsInLibrary.
- Scenario: maintain current local player; obsolete uncalled API remains alongside retained implementation.
- Root cause: definition remained after consumers disappeared.
- Impact: unnecessary API/behavior maintenance; no runtime or measured binary-size claim.
- Fix: Remove72–81 (~10 lines), keep other lookup methods.
- Evidence: No caller/test/callback; hasTrack has regression consumers and remains retained.
- Cross-refs: repository production/test/config reference census and enclosing file.
- Guards checked: plain Dart declaration, no framework/interface override, generated/native/channel, serialization/asset/reflection entrypoint; tests checked beyond simple token counts.
- Removal risk: low static risk; analyze/full tests required for actual removal.

## Retained exceptions / verification

CsvImportService has native-parser fixture/fallback compatibility tests, not removable from missing production import alone. History transaction helpers, quality/timeline/database test seams, playSingle/runtime/automix wrappers and libraryBrowseQuery paging fixtures retained. M3U remains live through Library export. Channel wrapper internal/native counterparts retained. Findings total approximately69 lines, not five whole-file removals.

No analyzer/tests/builds or code edits/security checks. Regex screening misses unusual declarations and same-name collisions; no blanket proof that all remaining code is live. Engine included for reachability only. Result FINDINGS, five P3.
