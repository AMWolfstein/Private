# Full-audit coverage

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

One row per subsystem (`scripts/review_scope.sh --list-subsystems`; the script owns the path
mapping). Status: `not reviewed` · `partial` · `reviewed` · `stale` (code changed since).
`Reviewed SHA` must be a bare commit SHA so the script can diff against it.

2026-10-21 reconciliation: these are historical reviews, not current whole-project proof.
All summaries are reopened after the upstream ports. Known gaps remain partial; other
subsystems are stale until their changed paths and dependencies are reviewed. No old
findings or baselines were discarded. `scripts/review_scope.sh --coverage-status` computes
path freshness including deletions and dirty/untracked files; status alone cannot close
planned chunks. `AUDIT_PLAN.md` owns remaining units and exact path/evidence records.

| Subsystem | Name | Status | Reviewed SHA | Chunk / notes | Findings |
|---|---|---|---|---|---|
| ui | Flutter UI (screens, widgets, theme, routes) | partial | 8e11147 | 2026-10-23 re-audit: 160 files in 5 chunks (C1 player, C2 Library lists/selection, C3 detail/Home, C4 settings/setup/shell, C5 shared widgets/theme/glass), each by flutter-dart-auditor + ux-auditor. Partial reads: player_lyrics.dart (handlers/sweep only), listening_rewind_screen.dart after line 750, sistrum_player_ground/background, lyric_* helpers, now_playing_route, home_tab_widgets, local_library_artwork_builder, sistrum_icons; contrast, TalkBack, RTL and large-text claims are static only (NOT RUN) | UI-101, UI-201..206, UI-401..420, UX-102, UX-106, UX-107, UX-201..204, UX-207..244, PERF-201..202, PERF-301, PERF-605, DEAD-604; resolved UI-102, UX-103, UX-105 |
| state | State management and app services | partial | f0f07be | 3 chunks: library providers (bug-hunter), settings/models/startup (api-compat), utils/services/scripts (bug-hunter). Confirmed OK: removed prefs ignored on import, completion flags, Loved keys, Singles from tags on Home/Artist, Latest Releases, Popular cap, badge policy. Not covered: automix_options, recent_access callers (provider looks dead), log path redaction | API-201..205, BUG-201..205, BUG-301..304, DEAD-401..403, DEAD-501..504 |
| scanner | Library scanner and file access (Dart) | partial | a9df85a | 2 reviewers: data-integrity (cleanup, duplicates, search, genres), security (file access). Check in kotlin/state: empty full-import stage with errorCount 0 wipes a source (`deleteReplacedLibraryScanRows`); duplicates also read download-era `history_db.history` | DATA-201..204, SEC-001..004 |
| metadata | Metadata, tags, covers, lyrics, ReplayGain, CUE | partial | c26265b | 3 chunks: tag/ReplayGain/CUE (data-integrity), lyrics (bug-hunter), covers + leftovers (data-integrity). Not covered: Rust native tag writers, resolver body :488-1068 line by line, Rust `parse_lyrics` parity | DATA-301..307, DATA-401..402, BUG-101..105, DEAD-001..004 |
| rust | Rust backend crates | partial | d2a8907 | 6 chunks in 2 rounds (rust-safety ×5, concurrency ×1) + Opus escalation for RUST-001. `cargo test -p sistrum-mobile native_` 74 passed. CUE `../` resolution confirmed sandboxed. Not covered: write/mp4/ac4.rs, volume.rs tests, uniffi panic mapping | RUST-001..002, RUST-101..106, RUST-201..205, RUST-301, RUST-401..403, CONC-101..104, SEC-201, DATA-502, DEAD-301..304 |
| kotlin | Kotlin integration, SAF, channels | partial | cd88dab | 3 chunks: MainActivity + SAF I/O + manifest (kotlin-android), SAF scanner (kotlin-android), Dart↔native contracts (api-compat; no live mismatch). Not covered: Rust/Kotlin implementation bodies behind dispatch, usb_pcm/audio_output/widget channel details, `resolveActivity` with `<queries>` on API 30+ | DATA-501, KT-102..105, KT-201..205, UX-003, SEC-101, DEAD-201..203, DEAD-206..208 |
| audio | Audio playback (Dart, Kotlin, C++) | partial | b98c51c | 3 chunks: core Dart (concurrency), features (bug-hunter, PASS), native (kotlin-android). Open: AAudio callback quiescence on flush, OEM AudioOutputActivity focus | CONC-001..004, KT-001, KT-002 |
| storage | SQLite, backups, collections, history | partial | 5fef271 | 3 chunks: library DB (data-integrity), collections (data-integrity), backup/history (api-compat). Not covered: Rust native import/backup jobs, settings/collections restoreFromBackup, scan serialization guard for fixed TEMP tables | DATA-002..004, DATA-101, API-001..003 |
| tests | Tests and integration tests | stale | 3494027 | 293 files, grep-first in 3 passes: stale/dead-feature tests, flakiness/assertions, coverage of risky findings | TEST-101, TEST-201..205, TEST-301, TEST-303..304 |
| build | Dependencies, build, toolchains | stale | 1791ebd | 14 files + manifest res/xml; dependency + security passes | SEC-301..303, UX-207, DEP-001..002 |
