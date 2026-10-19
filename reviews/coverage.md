# Full-audit coverage

One row per subsystem (`scripts/review_scope.sh --list-subsystems`; the script owns the path
mapping). Status: `not reviewed` · `partial` · `reviewed` · `stale` (code changed since).
`Reviewed SHA` must be a bare commit SHA so the script can diff against it.

| Subsystem | Name | Status | Reviewed SHA | Chunk / notes | Findings |
|---|---|---|---|---|---|
| ui | Flutter UI (screens, widgets, theme, routes) | not reviewed | - | 162 files | - |
| state | State management and app services | not reviewed | - | 60 files | - |
| scanner | Library scanner and file access (Dart) | reviewed | a9df85a | 2 reviewers: data-integrity (cleanup, duplicates, search, genres), security (file access). Check in kotlin/state: empty full-import stage with errorCount 0 wipes a source (`deleteReplacedLibraryScanRows`); duplicates also read download-era `history_db.history` | DATA-201..204, SEC-001..004 |
| metadata | Metadata, tags, covers, lyrics, ReplayGain, CUE | reviewed | c26265b | 3 chunks: tag/ReplayGain/CUE (data-integrity), lyrics (bug-hunter), covers + leftovers (data-integrity). Not covered: Rust native tag writers, resolver body :488-1068 line by line, Rust `parse_lyrics` parity | DATA-301..307, DATA-401..402, BUG-101..105, DEAD-001..004 |
| rust | Rust backend crates | reviewed | d2a8907 | 6 chunks in 2 rounds (rust-safety ×5, concurrency ×1) + Opus escalation for RUST-001. `cargo test -p spotiflac-mobile native_` 74 passed. CUE `../` resolution confirmed sandboxed. Not covered: write/mp4/ac4.rs, volume.rs tests, uniffi panic mapping | RUST-001..002, RUST-101..106, RUST-201..205, RUST-301, RUST-401..403, CONC-101..104, SEC-201, DATA-502, DEAD-301..304 |
| kotlin | Kotlin integration, SAF, channels | reviewed | cd88dab | 3 chunks: MainActivity + SAF I/O + manifest (kotlin-android), SAF scanner (kotlin-android), Dart↔native contracts (api-compat; no live mismatch). Not covered: Rust/Kotlin implementation bodies behind dispatch, usb_pcm/audio_output/widget channel details, `resolveActivity` with `<queries>` on API 30+ | DATA-501, KT-102..105, KT-201..205, UX-003, SEC-101, DEAD-201..203, DEAD-206..208 |
| audio | Audio playback (Dart, Kotlin, C++) | reviewed | b98c51c | 3 chunks: core Dart (concurrency), features (bug-hunter, PASS), native (kotlin-android). Open: AAudio callback quiescence on flush, OEM AudioOutputActivity focus | CONC-001..004, KT-001, KT-002 |
| storage | SQLite, backups, collections, history | reviewed | 5fef271 | 3 chunks: library DB (data-integrity), collections (data-integrity), backup/history (api-compat). Not covered: Rust native import/backup jobs, settings/collections restoreFromBackup, scan serialization guard for fixed TEMP tables | DATA-002..004, DATA-101, API-001..003 |
| tests | Tests and integration tests | not reviewed | - | 262 files | - |
| build | Dependencies, build, toolchains | not reviewed | - | 19 files | - |
