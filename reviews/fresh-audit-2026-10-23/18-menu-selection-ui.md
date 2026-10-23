# Track menus, editor and selection UI

## Scope

UI-05 flutter-dart-auditor, source d5d5a02 unchanged at5179dfea. Complete: lib/widgets/local_song_menu.dart1–369; lib/screens/track_metadata_edit_sheet.dart1–981; lib/widgets/duplicate_review_sheet.dart1–371,local_song_row.dart1–144,batch_progress_dialog.dart1–185,player_details_sheet.dart1–103,library_search_results.dart1–430 (2,583 lines; search full read retained/race ranges reread). explicit_track_title.dart absent; S1 audio_quality_badges.dart74–157 contains class. S2 local_song_file_actions.dart1–230; S3 providers/library_search_provider.dart1–55; S4 services/library_database.dart800–825. Graph explain showLocalSongMenu completed. No edits.

## Findings

### CONC-002 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/widgets/library_search_results.dart:100, _selectAllVisible; also85–91 _toggleSelection.
- Scenario: pending Select all/long-press resolution completes after search query changes or selection closes; old songs reenter selection.
- Root cause: completion checks mounted only, not query/selection generation.
- Impact: selection reappears with hidden old-query songs; subsequent queue/ReplayGain/deletion acts on stale set.
- Fix: capture/invalidate selection generation on query change/exit and reject stale results.
- Evidence:94–105 awaits Future.wait then inserts;85–91 resolves then inserts; didUpdateWidget58–63 and exit108–114 clear but do not invalidate; actions143–174 consume selected values. Provider24–28 awaits DB lookup.
- Cross-refs: lib/providers/library_search_provider.dart.
- Guards checked: mounted does not change on query/selection reset; keyed search providers do not guard selection futures. Coordinator independently reread80–114; distinct from UI-002 and CONC-001.

### UI-003 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/widgets/duplicate_review_sheet.dart:232, build.
- Scenario: duplicate query fails (e.g.DB open/read failure); completed FutureBuilder displays no duplicates.
- Root cause: snapshot.data??[] without hasError branch.
- Impact: failed review reported as successful absence, no retry.
- Fix: error/retry branch invoking existing _reload.
- Evidence: init49 assigns query;226–230 handles pending;232–242 assumes empty; database807–811 propagates failure.
- Cross-refs: lib/services/library_database.dart800–825.
- Guards checked: delete-operation catch does not cover initial/reloaded future; reload lacks error-state caller. Coordinator independently reread218–248.

## Verification / limits

Static source only; no Flutter/device fixtures. Synchronous ellipsis anchor capture/fitToAnchorSpace and virtual-CUE backing-file protection checked. Metadata backend/resource internals and shared context-menu/editor fields outside chunk. Existing batch root-pop CONC-001 not duplicated. Prompt-only review restrictions. Result FINDINGS, two P2.
