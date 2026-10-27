# Library playlist UX audit

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

## Scope

Role ux-auditor. Application baseline d5d5a02 unchanged; no application edits. UI-02 principal reads complete: lib/screens/queue_tab_batch_actions.dart1–40,queue_tab_collection_items.dart1–185,queue_tab_filter_widgets.dart1–614,queue_tab_helpers.dart1–316,queue_tab_item_widgets.dart1–136,queue_tab_navigation.dart1–323,queue_tab_selection.dart1–267,queue_tab_widgets.dart1–13 (1,894 lines).

Named supplements: UI-02-UX-S1 queue_tab.dart895–950,1070–1135,867–885 (whole file read in UI-01); S2 lib/widgets/library_search_results.dart1–430; S3 lib/screens/sistrum_library_screen.dart310–345. Search hypothesis dropped: global LibrarySearchResults does include playlists. The obsolete QueueTab Albums grid is not asserted reachable; production Albums uses SistrumLibraryPage.albums.

## Findings

### UX-003 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/queue_tab_filter_widgets.dart:248, _buildFilterContent.
- Scenario: Library → Playlists with existing playlists displays cards in a grid.
- Root cause: reachable dedicated Playlists branch builds _AnimatedLibrarySliverGrid.
- Impact: dedicated section violates explicit row-layout product requirement.
- Fix: use playlist rows, preserving open/selection/deletion actions.
- Evidence: sistrum_library_screen325 calls onOpenSection('playlists'); queue_tab873–879 pushes section;917–919 selects mode;1117–1124 passes mode; filter_widgets228–270 constructs grid via collection item builder.
- Cross-refs: lib/screens/queue_tab.dart,sistrum_library_screen.dart,queue_tab_collection_items.dart.
- Guards checked: only playlist-mode/nonempty guards, no production row alternative. Coordinator independently read filter_widgets1–280 and direct caller/root ranges.

### UX-004 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/screens/queue_tab_filter_widgets.dart:228, _buildFilterContent.
- Scenario: visit Playlists with no playlists, or delete final playlist; no Create action remains, only Home.
- Root cause: creation control is nested under playlistIndexes.isNotEmpty; empty action unconditionally navigates Home.
- Impact: first playlist cannot be created from its dedicated section; users must find another screen's action.
- Fix: retain creation control when empty or make it the empty-state action.
- Evidence:234–238 Create enclosed by228 guard;428–432 playlist message;445–448 Home action. Production route as UX-003.
- Cross-refs: lib/screens/queue_tab.dart,sistrum_library_screen.dart,queue_tab_navigation.dart.
- Guards checked: create dialog exists but has no empty-section caller; Songs/Singles controls belong to other modes; search has no create action. Coordinator reread empty/control branches and root header.

## Verification

Reviewer ran graphify explain QueueTab --budget1000 successfully; source navigation only. Both findings independently checked by coordinator. No runtime fixtures, Flutter analysis/tests, TalkBack or device execution. Shared overlay/dialog/persistence internals not covered by this UI chunk. Prompt-only read restrictions.

## Result

FINDINGS: two P2; eight principal part files complete within stated scope.
