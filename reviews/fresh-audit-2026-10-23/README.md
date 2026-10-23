# Independent current-branch audit

- Source: `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`, branch `ccr-2fb644cd-nmesyt`.
- Fresh checkout: `/workspace/Private-audit`; report folder created for this request.
- Evaluate current implementation independently. Do not compare against or import old audit findings.
- Review only; no application fixes. Specialist definitions: `.claude/agents/`. Coordinator follows `.claude/skills/audit-project/SKILL.md` and `reviews/PROTOCOL.md`, with the owner's fresh-audit instructions taking precedence over old-finding reconciliation.
- Exclude the audio engine: decoding/rendering, USB audio transport, DSP, audio focus/engine lifetimes, vendored audio-player internals, and engine-specific tests. Retained application UI, library/metadata/file operations, persistence, permissions, and non-engine lifecycle remain in scope.
- Graphify CLI installed outside checkout; existing graph reported fresh by scope helper (built from `46c4ea6a`). Graph has 23,088 nodes. Queries identify navigation leads; findings require direct source evidence.
- Reviewers are instructed read-only; enforcement is prompt-only. Coordinator owns edits, checks, commits and pushes. Maximum three active specialist reviewers per bounded unit, with named chunks and concerns.
- Application builds/device checks are not implied by static review. Record unrun/blocked checks explicitly.

## Planned audit order

1. Cross-language contracts and non-engine cancellation/lifecycle.
2. Metadata/file-write integrity, backups/collections/playlists, scanning/database integrity.
3. Non-engine Rust safety, Android storage/security, build/dependencies.
4. State/business logic, Flutter implementation, UX/accessibility, optimization/dead code.
5. Tests, documentation, inventory reconciliation and final task list.

Each audit type receives a report and commit/push checkpoint. `TASKS.md` is generated after the reviews; old reports remain untouched. Exact planned/read path ledgers and verification evidence accompany each unit.

## CONTRACT-01 planned scope

Owner: api-compat-auditor, secondary concurrency-auditor. Baseline above; clean working tree before report creation.
Planned paths: `lib/services/platform_bridge.dart`, `lib/services/library_native_adapter.dart`, `lib/services/activity_attachment.dart`, `lib/services/native_cache_maintenance.dart`, `lib/services/native_log_source.dart`, `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt`, `android/app/src/rust/kotlin/com/zarz/spotiflac/NativeDataJobs.kt`, `rust_backend/crates/mobile/src/lib.rs`, `rust_backend/crates/mobile/src/data_jobs.rs`, `rust_backend/crates/mobile/src/cancellation.rs`, `rust_backend/crates/core/src/cancellation.rs`.
Concerns are distinct: API names/types/error mapping versus cancellation/disposal/late completion. Split direct endpoint additions into further <=6k-line chunks; record actual reads. Exclude audio-specific methods in shared files.
Graph navigation: `graphify query 'platform bridge data jobs cancellation library native' --budget 1800` (truncated; narrow queries required); `graphify explain PlatformBridge` identified source at L110.
Status: in progress. No readiness claim.

## DATA-01 planned scope

Baseline remains current application source `d5d5a02`; intervening commits contain reports only. Owner data-integrity-auditor; secondary rust-safety-auditor. Two disjoint chunks, each below 12 principal files/~6k lines:

- Dart chunk: `lib/services/ffmpeg_{cue,metadata,models,probe,replaygain,service,support}.dart`, `metadata_cover_resources.dart`, `metadata_persistence_service.dart`, `id3v23_lyrics.dart`, `replaygain_service.dart`, `lib/controllers/metadata_editor_controller.dart`. Direct caller additions require separate named supplemental chunks.
- Rust/SAF writer chunk: `rust_backend/crates/core/src/tags/write.rs`, `tags/write/{ape,id3,mp4,ogg,riff}.rs`, `rust_backend/crates/local/src/backend/tags.rs`, `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafIo.kt`, nonaudio `writeTempToSaf` handler in `MainActivity.kt`, `NativeMediaWorkspace.kt`. Concern: replacement/rollback, unrelated-data preservation and malformed input; SAF destination opened with truncation must be checked against actual caller recovery.

Round-trip/failure injection not executed yet. Audio playback engine excluded; retained metadata/ReplayGain file editing is included.

## DATA-02 planned scope

Current-source baseline unchanged. Backup/persistence unit, separate disjoint bounded chunks:

- data-integrity-auditor: `lib/services/{backup_service,collection_restore_codec,collection_track_batch,library_collections_database,library_collections_hydration,m3u_playlist_service,history_database,history_maintenance,app_state_database,user_profile_store}.dart` (10 files/~4.2k lines). Trace restore partial failures, ordering/duplicates, keys, schema and transaction ownership; supplemental direct-caller chunks explicitly logged.
- api-compat-auditor: `rust_backend/crates/mobile/src/native_backup.rs`, `native_backup/{archive,collections,legacy}.rs`, `native_collections.rs`, `native_playlist_write.rs`, `native_playlists.rs`, corresponding fixtures and Dart endpoint ranges (split supplemental chunk if >12 files). Check native/persisted schemas against Dart and legacy compatibility from current readers, not prior audit reports.

Tests/provider/device evidence remain separate; no audio engine.

## SCAN-01 planned scope

Current-source baseline unchanged. Split into bounded current-source chunks:

- Dart scan/DB data integrity: `lib/providers/local_library_provider.dart`, `lib/services/{library_database,library_schema,library_native_adapter,sqlite_native_snapshot}.dart` (~4.1k lines), supplemental cleanup/deletion callers as needed.
- Native scanner/platform chunk: `android/app/src/main/kotlin/com/zarz/spotiflac/{MainActivitySafScan,SafScanPolicy,SafScanProgressStream,LibraryScanExitInfo}.kt`, `rust_backend/crates/local/src/backend/library.rs`, `backend/library/scan.rs`, `rust_backend/crates/mobile/src/native_library.rs`, `native_library/{dart_date,path_keys}.rs` (~4.5k lines). Primary kotlin-android-auditor; verify cancellation/partial scans/permission loss and trace producer-consumer guards. Explicit separate supplemental chunks for tests or other endpoints.

## BUILD-01 planned scope

dependency-auditor processes manifest/toolchain, Gradle/Android policy, and script/license chunks separately (<=25 paths/~6k lines each), using exact `build` category paths in inventory.json plus current scripts and vendored patch notices. Review version/lock agreement, platform/ABI/16KiB policy, offline permissions, license coverage and repeatable commands. Audio-engine implementation bodies remain excluded; no engine replacement recommendations. Dependency advisories require actual resolved/reachable evidence; do not infer a defect from package presence alone.

## UI-01 planned scope

Flutter implementation chunk: `lib/app.dart`, `lib/routes/now_playing_route.dart`, `lib/screens/{main_shell,mornye_library_screen,local_artist_screen,local_album_screen,library_tracks_folder_screen,setup_screen}.dart` (~5.2k lines, 8files). Concern: widget lifecycle/navigation/list identity/layout/async context.

UX player/lyrics chunk: `lib/screens/{now_playing_screen,queue_tab,lyrics_share_screen}.dart`, `lib/widgets/player_lyrics.dart` (~5.4k lines, 4files). Concern: retained UI accessibility/RTL/large text/reduced motion/loading/error states. Audio playback implementation is excluded; UI controls/navigation remain in scope. Shared primitives/direct callers require separately named bounded supplemental chunks before reads. Later chunks cover remaining widgets/settings, state and performance.
