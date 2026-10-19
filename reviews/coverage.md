# Full-audit coverage

One row per subsystem (`scripts/review_scope.sh --list-subsystems`; the script owns the path
mapping). Status: `not reviewed` · `partial` · `reviewed` · `stale` (code changed since).
`Reviewed SHA` must be a bare commit SHA so the script can diff against it.

| Subsystem | Name | Status | Reviewed SHA | Chunk / notes | Findings |
|---|---|---|---|---|---|
| ui | Flutter UI (screens, widgets, theme, routes) | not reviewed | - | 162 files | - |
| state | State management and app services | not reviewed | - | 60 files | - |
| scanner | Library scanner and file access | not reviewed | - | 14 files | - |
| metadata | Metadata, tags, covers, lyrics, ReplayGain, CUE | not reviewed | - | 27 files | - |
| rust | Rust backend crates | not reviewed | - | 111 files, excludes vendor | - |
| kotlin | Kotlin integration, SAF, channels | not reviewed | - | 47 files | - |
| audio | Audio playback (Dart, Kotlin, C++) | reviewed | b98c51c | 3 chunks: core Dart (concurrency), features (bug-hunter, PASS), native (kotlin-android). Open: AAudio callback quiescence on flush, OEM AudioOutputActivity focus | CONC-001..004, KT-001, KT-002 |
| storage | SQLite, backups, collections, history | not reviewed | - | 18 files | - |
| tests | Tests and integration tests | not reviewed | - | 262 files | - |
| build | Dependencies, build, toolchains | not reviewed | - | 19 files | - |
