# Library and lyrics UI hot paths (U1a)

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

## Scope

code-optimization-auditor; baseline968fbe57/appd5d5a02 unchanged, graph46c4ea6a reported fresh. Principal5,496 lines: lib/widgets/player_lyrics.dart1–2249,lib/screens/queue_tab.dart1–1247 (unchanged full reads retained, hot ranges reread),local_artist_screen.dart1–752,local_album_screen.dart1–662,sistrum_library_screen.dart1–586. S1 queue_tab_helpers.dart185–235,queue_tab_filter_widgets.dart42–78 (earlier unchanged part bodies retained). Graph explain SyncedLyricsView completed before reads. No edits.

## Findings

### PERF-001 [P2] [confidence: medium] [NEEDS VERIFICATION]

- Location: lib/screens/queue_tab.dart:1007, build.
- Scenario: many300-row Songs pages loaded; selection toggle/page arrival rebuilds complete accumulated lists three times.
- Root cause: currentPageData,unconditional selectionItems and rendered filter content separately resolve page/filter data without snapshot reuse.
- Impact: potentially growing UI-isolate allocations/build cost; frame-budget impact unmeasured.
- Fix: after profiling, reuse active page/filter snapshot per build; preserve paging/stale-row/selection behavior before considering longer-lived caching.
- Evidence: pageData984–991 calls resolver;1007 and getFilterData1028–1030/1121 resolve again. _QueueLibraryPageData.combine192–211 allocates three lists and copies every cached page after one-page fast path expires.
- Cross-refs: queue_tab_helpers185–235,queue_tab_filter_widgets42–78.
- Guards checked: lazy row widgets do not avoid list combination; individual pages cached but combined snapshot not; active prior pages retained280–286. Coordinator independently reread970–1035 and combine185–217.
- Required measurement: representative lower-tier Android profile build,300/3,000/15,000 loaded rows; UI build duration,allocation/GC events and combination call counts during page arrivals and selection toggles; compare snapshot reuse to identical baseline. No speedup asserted.

## Verification / limits

Static source only; no benchmarks/builds/Flutter tests/devices. Existing lazy rows,cached album ordering,bounded lyric measurement,hidden/background suspension and reduced-motion/glass gates checked and retained. Other4 principal files yielded no additional actionable performance candidate. Query/image internals outside chunk. Result FINDINGS, measurement required.

U3 follow-up: library_section_list.dart52–73 regroups on items identity changes,so combined list recreation can also invalidate grouping/label-formatting cache. Same PERF-001; include this cost in profiling, no new finding.
