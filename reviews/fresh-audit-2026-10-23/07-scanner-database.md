# Scanner/database integrity audit

Source d5d5a02. Roles `.claude/agents/data-integrity-auditor.md` and `.claude/agents/kotlin-android-auditor.md`; `.claude/skills/audit/SKILL.md`. Independent current-source review; audio engine excluded.

### DATA-008 [P2] [confidence: high] [VALIDATED — static]

- Location: `lib/providers/local_library_provider.dart:1720`, clearLibrary.
- Scenario: Clear Library during an active scan; UI reports cleared, then the earlier scan publishes rows and tracks return.
- Root cause: clear does not cancel/wait for scan or invalidate the data-publication generation.
- Impact: clearing unexpectedly reverses itself.
- Fix: serialize clear with scan cancellation/completion and queued reconnect starts, or check a generation inside publication transaction.
- Evidence/cross-refs: settings/library_settings_page709–717 enables Clear while scanning and217–218 calls clear; provider1720–1734 increments `_sourceVersion` but does not cancel/wait; library_database934–946 retains sources; native adapter254–256 checks only cancellation/path/enabled before303–311 publication.
- Guards checked: `_sourceVersion` protects summary/probe state, not native data publication; single-flight scan guard does not serialize Clear. Coordinator re-read clear/UI and publication predicate.
- Verification: two reviewers traced current endpoints. Dynamic completer/queued reconnect regression NOT RUN.

### DATA-009 [P2] [confidence: high] [VALIDATED — reproduced]

- Location: `rust_backend/crates/local/src/backend/library/scan.rs:589–593`, cue_base.
- Scenario: existing unchanged physical `song#track2.wav` (or FLAC) is incorrectly marked deleted on local incremental scan.
- Root cause: any `#track` occurrence is treated as a virtual suffix, including inside a real filename.
- Impact: existing songs disappear on refresh.
- Fix: require the exact trailing numeric virtual-CUE suffix, consistent with SAF.
- Evidence/cross-refs: scan407–413 false base creates deletion;421–431 unchanged file skipped; native_library525–545 retains removal; library_native_adapter283–288 deletes live row.
- Guards checked: preserveMissing does not suppress explicit removals; cancellation/source-current checks do not correct path identity. Coordinator directly inspected scanner375–505/589–593 and adapter162–205/272–304.
- Verification: actual compiled current Backend API returned `existing_song=true`, deletedPaths containing that song, scanned=[], skipped=1. Harness `reproductions/local_scan.rs` uses only disposable generated WAV and removes its temporary directory.

### DATA-010 [P2] [confidence: high] [VALIDATED — static]

- Location: `rust_backend/crates/local/src/backend/library/scan.rs:421–431,449–450`.
- Scenario: replace/change backing audio of an indexed local CUE album without modifying CUE; incremental refresh leaves virtual duration/quality/artwork stale.
- Root cause: unchanged CUE timestamp suppresses its task while parsed CUE still claims and suppresses backing audio's task.
- Impact: audio-file changes are not reflected until full refresh/CUE modification.
- Fix: include backing-audio version in dependent CUE invalidation and schedule refresh before deduplication.
- Evidence/cross-refs: cue_times404–410; task421–431; ownership442–450; backing task suppressed494–496; CUE timestamp passed461–469 and library430. SAF1300–1306 has an equivalent backing-file invalidation guard absent locally.
- Guards checked: deduplication parses the unchanged sheet but does not emit refreshed rows. Coordinator inspected the complete scheduling/ownership path.
- Verification: static; changed-backing-file/unchanged-CUE fixture NOT RUN.

### DATA-011 [P2] [confidence: high] [VALIDATED — static]

- Location: `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:918`, full scan.
- Scenario: initial/full SAF source has readable album.flac and malformed CUE with valid FILE reference but no usable tracks. CUE fails and standalone audio is omitted.
- Root cause: backing URI is claimed before successful CUE row production.
- Impact: malformed sidecar hides playable songs in a new/fully rescanned library.
- Fix: claim only after usable rows are produced; otherwise scan backing audio normally.
- Evidence/cross-refs: resolve901–906; claim918; parse935–944; failure951–953; skip987–991. provider1019–1020 auto-selects full scan for empty source; SafIo341–354/native library298–330 are parse endpoints.
- Guards checked: error-count preservation cannot preserve missing initial rows; incremental path already checks cueArray.length()>0 at1476–1480. Coordinator independently read full/ incremental guards.
- Verification: static; disposable-provider regression NOT RUN.

## Read ledger

Dart principal chunk complete: provider/local_library_provider1–1949; services/library_database1–1119,library_schema1–463,library_native_adapter1–414,sqlite_native_snapshot1–138. Supplemental: library_cleanup1–280,deleted_library_files1–16,source_deletion_events1–30,file_access1–169,library_row_mapper1–126,sqlite_helpers1–150/330–462; settings/library_settings_page175–290/625–730.

Native principal chunk complete: MainActivitySafScan1–1645,SafScanPolicy1–85,SafScanProgressStream1–115,LibraryScanExitInfo1–46; local/backend/library.rs1–692 and library/scan.rs1–806; mobile/native_library.rs1–692,native_library/dart_date.rs1–99,path_keys.rs1–331. Native paths under android/app/src/main/kotlin/com/zarz/spotiflac and rust_backend/crates respectively.

Supplemental endpoints: library_native_adapter1–414;library_database110–157;local_library_provider918–1025/1095–1290;NativeDataJobs45–108;SafIo325–357;SafScanPolicyTest1–62 (remainder not certified);library_partial_scan_test1–77. Other test references searched without full-body certification.

## Verification and limits

Graphify queries narrowed to LibraryNativeAdapter; ambiguous scanSafTreeIncremental graph result not used as evidence. Guards present for detached staging/owner transactions, cancellation/source identity, full-scan error preservation, tri-state cleanup, and failed DETACH retention. Coordinator ran spotiflac-local tests:20 passed,0 failed; doc tests0 (no doc-test coverage claimed). Rust core tags14 passed. Existing tests do not invalidate missing regressions. Android provider/device and Flutter execution NOT RUN. Remaining search/queue/model modules scheduled separately.

Prior test-audit checkpoint e0de186 pushed successfully; no app source edits.
