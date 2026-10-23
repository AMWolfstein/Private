# Library query and membership-index review (D1)

## Scope

code-optimization-auditor, source d5d5a02 unchanged at baseline968fbe57. Nine principal files candidate-screened. Complete reads lib/providers/library_browse_provider.dart1–234,library_search_provider.dart1–55,local_artist_provider.dart1–201,local_home_feed_provider.dart1–50; services/library_search.dart1–191,library_playlist_search.dart1–114. Ranges: library_queue_store.dart1–750,library_database.dart150–184,575–660,732–805,library_collections_database.dart88–163,246–465,478–535,1039–1125. S1 widgets/playlist_picker_sheet.dart35–153,providers/library_collections_provider.dart829–839,services/library_schema.dart1–74,225–260,listening_statistics.dart206–230,336–367. Other bodies query/loop screened. Graph query completed truncated, navigation only.

## Findings

### PERF-003 [P2] [confidence: medium] [NEEDS VERIFICATION]

- Location: lib/services/library_collections_database.dart:1078, readPlaylistPickerSummaries.
- Scenario: Add to playlist with many selected tracks and large playlist membership table.
- Root cause: repeated500-key membership filters by track_key lack a track-key-leading live index.
- Impact: potentially repeated full membership scans delaying summary; Android latency/write tradeoff unmeasured.
- Fix: benchmark covering(track_key,playlist_id) index and migrate only if measurements justify space/write cost.
- Evidence:1071–1086 loops500 unique keys WHERE track_key IN/group playlist_id; schema108–132 PK(playlist_id,track_key),playlist_id/added_at indexes, upgrades137–163 no reverse key. Picker81–86/142–144 requests; provider831–839 forwards.
- Cross-refs: playlist_picker_sheet.dart,library_collections_provider.dart,schema/index helpers.
- Guards checked: dedup/chunking/lightweight summaries bound arguments/transfers but do not create indexed reverse lookup. Planner may differ by SQLite version/statistics. Coordinator independently reread schema106–136/query1039–1092.
- Required measurement: Android EXPLAIN + warm/cold p50/p95 at100k/1m memberships and1/500/5000 selection; before/after index plus DB size/bulk add/delete and exact counts/order parity.

## Host fixture evidence

Coordinator ran Python sqlite3 SQLite3.54.0 in-memory fixture:100k memberships,1000 playlists,20k distinct keys,warm cache,5 timed repetitions. Exact membership SELECT/GROUP BY with current three indexes compared against added(track_key,playlist_id). Current plan SCAN covering PK; reverse-index plan SEARCH track_key (plus grouping temp B-tree for500keys). Median membership-query-only milliseconds:1key4.598→0.0058;500keys15.856→1.011. Returned group counts unchanged. Raw plans/samples: playlist-picker-host.json. This is a synthetic host-query comparison, NOT application picker time, Android performance or measured app speedup. Does not include first aggregate query,persistence,transfer/UI or index storage/write cost. Candidate remains NEEDS VERIFICATION.

## Verification / limits

No Flutter/native app tests/builds/profiling/devices. Existing benchmark sources discovered, not executed. Home shelves12,browse40/cursors,FTS fallback,lightweight bounded ranking/native collection projections retained. Full artist scans/full playback queues preserve required semantics. Result FINDINGS, one candidate with host plan evidence; device verification pending.
