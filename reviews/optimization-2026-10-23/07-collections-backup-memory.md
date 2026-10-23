# Collection hydration and backup memory (D2)

## Scope

code-optimization-auditor, appd5d5a02 unchanged. Eight paths5,941lines candidate-screened. Focused: lib/providers/library_collections_provider.dart82–139,710–727 (prior full read retained),local_library_provider.dart230–310,576–615,1660–1949; services/library_collections_hydration.dart1–70,126–239,294–438,493–617,collection_track_batch.dart1–150,backup_service.dart1–75,200–233 (prior full read),history_database.dart550–595,listening_statistics.dart1–429,listening_rewind.dart1–436. S1 screens/library_tracks_folder_screen.dart185–207,216–260,settings/backup_restore_page.dart37–68; services/library_database.dart732–779,sqlite_helpers.dart301–342. Graph collection/backup query completed truncated, navigation only.

## Findings

### PERF-006 [P2] [confidence: high] [NEEDS VERIFICATION]

- Location: lib/providers/local_library_provider.dart:1936, localLibraryFirstCoverProvider.
- Scenario: large playlist has no stored cover references; early matching local song has art, but header waits for all member lookups.
- Root cause: resolves full request via findExistingBatch before first-usable-cover inspection.
- Impact: potentially unnecessary queries/full-row decoding/allocations delay header; timing unmeasured.
- Fix: benchmark ordered bounded batches,stop at first usable cover while preserving matching precedence/order.
- Evidence: folder232–237 fallback;185–201 includes all entries;provider1936–1943 resolves all then1944–1948 picks first;database732–777 builds complete maps,sqlite316–326 full rows per450keys.
- Cross-refs: named folder/database/SQLite supplements.
- Guards checked: SQL argument chunking not total lookup bound; provider cache avoids repeats but not initial lookup. Coordinator independently reread provider1920–1949.
- Required measurement:1k/10k/50k members,cover positions1/450/end/none; first-cover time,query/row counts,allocation/frame cost; exact selected-cover parity.

### PERF-007 [P2] [confidence: medium] [NEEDS VERIFICATION]

- Location: lib/providers/library_collections_provider.dart:722, exportCollectionsJson.
- Scenario: large backup after startup has many lazily unloaded playlists; export hydrates all into persistent UI state before worker JSON export.
- Root cause: ensurePlaylistsLoaded Future.wait for all,then whole-graph export accumulator.
- Impact: potentially high peak memory/per-playlist worker/snapshot overhead; measured peak/time unknown.
- Fix: benchmark bounded stable-database-snapshot export without UI hydration; preserve format/order/snapshot consistency.
- Evidence: export722→ensure139;loads94–105 create snapshots/hydrate and119–126 publish;worker547–572 receives bounded messages but580–616 accumulates entire graph before419 encoding. Backup page51–55 calls export.
- Cross-refs: hydration,backup service/page.
- Guards checked: per-playlist dedup,membership identity,worker parsing and256-entry acknowledgements preserve correctness/transfer bounds but not full state/graph peak. Coordinator reread provider83–143/710–728 and worker accumulation ranges.
- Required measurement:100/1000 unloaded playlists/100k memberships;peak heap/RSS,worker count,temp I/O,UIp95,elapsed and round-trip ordering/duplicate metadata parity versus snapshot streaming.

## Verification / limits

No tests/builds/profiles/devices; source-only opportunities. Acknowledged worker messages/Isolate.exit,large track staging,native streamed history export,SQL listening aggregates and24filesystem/500SAF backfill bounds retained. No security/dead-code/engine changes. Result FINDINGS, two unmeasured candidates.
