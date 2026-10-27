# Whole-project audit plan and path ledger

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

2026-10-21: workflow maintenance only. Application review units below are NOT RUN.
Current anchor: 4faf09ba (pre-maintenance checkpoint); refresh baseline to actual source
revision when starting each unit. Source after the upstream ports is authoritative.
Preserve prior findings and owner decisions; no Media3 migration or removed features.

## Completion contract

Run `scripts/review_scope.sh --coverage-status` at the start, then select the first ready
unit by priority. Expand path seeds below against current tracked/untracked files; a seed
is not proof of coverage. Partition each unit into <=25 files/~6k lines before assigning.
Record exact planned and read paths in this ledger (or a linked committed path manifest),
source revision plus dirty paths, owner, endpoints/dependents, exclusions, finding IDs,
checks with PASS/FAIL/NOT RUN/BLOCKED and evidence. Unread bodies, pending risk checks or
failed required verification keep a unit partial/BLOCKED. Deleted files require historical
blobs and callers. A changed shared contract invalidates its dependent unit, even if the
unit's own files are unchanged. Do not use a global reviewed SHA to close unknown paths.

## Prioritized remaining units

| Unit | Priority / owner | Path seeds / scenario | Required evidence | Status |
|---|---|---|---|---|
| CONTRACT-01 | P1 api-compat + concurrency | lib/services/platform_bridge.dart, lib/services/library_native_adapter.dart, lib/services/native_*, android/app/src/main/**/MainActivity*.kt, rust_backend/crates/mobile/src/{lib,data_jobs,cancellation}.rs; expand actual channel/JNI/bindgen endpoints | call/return types, error/null mapping, cancel/dispose/late completion, generation drift; endpoint fixtures and exact signatures | not reviewed |
| DATA-01 | P1 data-integrity + rust-safety | Rust metadata writers and Dart metadata/CUE/ReplayGain callers, corresponding SAF I/O | disposable-file round-trip, unrelated tag/artwork/lyrics/audio preservation, failed replacement/rollback, malformed/large inputs, no user music writes | not reviewed |
| DATA-02 | P1 data-integrity + api-compat | lib/services/backup_*, collection_*, library_collections_*, m3u_*, Rust native_backup/native_playlist_write, Kotlin import handlers | legacy and current backup restore fixtures, atomicity/partial failure, playlist ordering/duplicates/missing members, Loved key compatibility | not reviewed |
| SCAN-01 | P1 data-integrity + kotlin-android | Dart library scan/DB paths, Kotlin MainActivitySafScan* and SAF helpers, Rust native_library* | cancelled/empty/partial/failed scans preserve valid rows, concurrent import serialization, source removal, permission revocation, incremental changed/deleted files | not reviewed |
| NATIVE-01 | P1 concurrency + kotlin-android / rust-safety as separate chunk | android/app/src/main/cpp/, audio/USB/AAudio/JNI callbacks and Rust FFI ownership endpoints | stop/flush/dispose quiescence proof, callbacks/buffers lifetime, track/seek/focus/USB races; host/native tests; device results separate | not reviewed |
| BUILD-01 | P2 dependency + security | all nested Cargo manifests/lockfiles, Gradle/CMake/toolchains, AndroidManifest, android/**/res/xml/, .github if present, third_party and vendor local patches | exact dependency/advisory reachability, offline permissions, backup/provider exposure, signing/ABI/minify/16KB policies, licenses; enumerate excluded unchanged vendor bodies | not reviewed |
| UX-01 | P2 ux + flutter-dart | lib/screens and shared widgets/theme/routes; Songs/Loved/playlists/genres/artist/albums, both player views/lyrics/queue/settings | RTL/large text/tablet/split-screen widget and semantics fixtures; TalkBack focus/state, 48px targets, popover anchors, reduced motion, contrast evidence; device NOT RUN when unavailable | not reviewed |
| STATE-01 | P2 bug + concurrency | state gaps: automix_options, recent_access callers, log redaction; state/providers/models changed after old baseline | lifecycle/disposal, logs exclude sensitive paths, startup/import preferences preserve retained behavior; targeted regression evidence | not reviewed |
| METADATA-02 | P2 data-integrity + bug | metadata resolver unread body, Rust parse_lyrics parity, sidecar lookup and artwork cache | Unicode/timestamps, malformed/truncated/large input, cache invalidation and missing artwork fallback; bounded queries/read sizes | not reviewed |
| TEST-01 | P2 test-auditor | test/, integration_test/, Android host/device tests, Rust tests, scripts/test_* | tests exercise new risks, meaningful assertions, bounded async waits, isolated fixtures; skips and zero-test runs explicit; optional targeted fuzz/Miri/sanitizer availability recorded | not reviewed |
| RECONCILE-01 | P2 coordinator | every stale/partial subsystem in coverage.md not closed by preceding units | reviewed-path manifest vs current inventory, source changes/dependents since baseline, chunk and excluded-path totals; create further bounded chunks as needed | not reviewed |
| FINAL-01 | final coordinator + relevant specialist only | cross-subsystem flow after all units/chunks complete | coverage reconciled, offline/Sistrum exclusions preserved, unresolved findings/device limitations disclosed, no unexpected music writes; no blanket regression-free claim | not reviewed |

## Per-chunk evidence record (copy for each execution)

- Unit/chunk and status:
- Reviewed source revision; dirty paths:
- Exact planned paths (or linked manifest):
- Exact paths/symbols read, including historical deletions:
- Owner/reviewer concern; direct dependents and both contract endpoints:
- Explicit excluded paths/checks and follow-up owner:
- Trigger/guards/current evidence; durable finding IDs assigned by coordinator:
- Command, exit code, counts/skips, PASS/FAIL/NOT RUN/BLOCKED, log path:
- Host/fixture/compiler/device distinction:
- Remaining chunks; invalidated dependent units; exact next unit:

## Workflow maintenance evidence

Scope helper now handles deletion/rename/untracked paths, invalid revisions, bundled patches,
CI/resource XML/nested Cargo manifests, graph freshness and reviewer overflow. Regression
suite: scripts/test_review_scope.py (disposable Git repositories, no user music).
Reviewer read-only policy enforcement is prompt-only in this host configuration; Bash
allow entries are not a sandbox. Orchestrator owns checks, edits and final Git status.
No application unit above was reviewed merely by adding its checklist.
