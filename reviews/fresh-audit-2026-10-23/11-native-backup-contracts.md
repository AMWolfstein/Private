# Native backup and collection contracts

## Scope

DATA-02-N, api-compat-auditor; application baseline d5d5a02, final observed review HEAD294ff66b. No edits. Fresh05 report read for deduplication only; old audits not imported. Engine excluded; prompt-only read restrictions.

Principal complete reads (2,073 lines), under rust_backend/crates/mobile/src/: native_backup.rs1–556; native_backup/archive.rs1–308,collections.rs1–214,legacy.rs1–232; native_collections.rs1–171; native_playlist_write.rs1–210; native_playlists.rs1–382.

Named DATA-02-N-S1 supplements: lib/services/backup_service.dart190–325,390–610; collection_restore_codec.dart1–105; m3u_playlist_service.dart1–195; csv_import_service.dart1–177; library_collections_database.dart1–25,390–465,580–620,795–825,875–980; collection_track_batch.dart1–267; library_collections_hydration.dart235–285,439–490; history_database.dart18–110,438–555. Native data_jobs.rs40–125 dispatch/completion (engine branches excluded).

Named DATA-02-N-T1 fixture source reads: native_backup/tests.rs1–294; native_backup/archive/tests.rs1–297; native_backup/collections/tests.rs1–217; native_collections/tests.rs1–218, all under rust_backend/crates/mobile/src/. Inline playlist tests included in principal reads. test/fixtures/collection_restore_contract.json complete; native_backup_contract.json1–966 complete, truncated middle reread in bounded ranges; native_metadata_parsers.json1–107 inspected, only playlists80–107 evaluated (listing fixtures excluded).

## Findings

None new. DATA-007 independently confirmed: archive94 exports with u64::MAX;211 rejects metadata over MAX_METADATA_BYTES on import; Dart export imposes no matching metadata bound. Keep existing ID.

## Guards checked

History schema v15 and collections schema v3 match Dart storage contracts. History imports stage rows and paths before immediate publication; malformed rows/count mismatch/cancellation precede commit. Collection command kinds/nullability/columns agree with Dart; duplicate playlist replacement clears earlier staged members. Parent-before-member publication uses foreign keys; Dart publishes closed staging DB through live transaction. Snapshot kinds/counts match hydration; native read transaction/noclobber publication and Dart total-row validation are present. Playlist staging key/track rows/count/filename/path/publication flags agree; duplicates and incomplete/excess input rejected, Dart validates response before publication. Legacy split preserves last duplicate history-field semantics, skips non-object entries and retains non-history data. Archive creates local destination names, bounds entries, validates versions/profile, cleans failed staging with RAII and transfers successful ownership through committed flag. Dispatcher delivers committed results despite cancellation. CSV/M3U field shapes, aliases, EXTINF and request fields agree with Dart.

## Verification

graphify query 'native_backup native_collections native_playlists native_playlist_write' --budget1800 completed (truncated, navigation only). Exact source/fixture reads above complete. Rust tests, fixture execution, Flutter analysis/tests, builds, SQL failure injection, cancellation timing and device execution NOT RUN. Reading test source is not execution.

## Limitations / result

PASS for bounded additional static contract coverage, no new findings; DATA-007 stays open. Kotlin/JNI transport/lifecycle not rereviewed. Backup subsystem runtime evidence remains incomplete.
