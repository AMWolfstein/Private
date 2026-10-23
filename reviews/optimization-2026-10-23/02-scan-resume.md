# Native scanner I/O hot paths (N1)

## Scope

Role code-optimization-auditor; source d5d5a02 unchanged, baseline968fbe57. Seven principal paths/4,443lines candidate-screened. Bounded reads: Android MainActivitySafScan.kt70–235,350–438,730–865,970–1078,1490–1568; SafScanPolicy.kt1–85,SafScanProgressStream.kt1–115; rust_backend/crates/local/src/backend/library.rs1–160,260–440,library/scan.rs240–365,500–600; mobile/src/native_library.rs360–465; core/src/tags/library.rs130–215. Graph scanner/import query completed truncated, navigation only. Prior immutable-source correctness guards retained; not fresh full-body performance certification.

## Findings

### PERF-002 [P2] [confidence: high] [NEEDS VERIFICATION]

- Location: android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafScan.kt:180–188, repairSafScanOutput.
- Scenario: interrupted full scan leaves large partial final NDJSON row; resume scans backward with one seek/read per byte (about1million pairs for1MiB partial row).
- Root cause: byte-at-a-time backward newline search.
- Impact: potentially prolonged resume latency/redundant filesystem calls; magnitude unmeasured, not a rendering-thread claim.
- Fix: benchmark fixed-size backward block search retaining last-newline truncation and no-complete-line behavior.
- Evidence: position decrements by1 after seek/readByte; full-scan812 repairs before checkpoint reconciliation/work;843–851 writes full metadata rows.
- Cross-refs: same file; core tags/library metadata composition.
- Guards checked: absent file skips work and complete newline common path short; no bound on work for long interrupted row. Runs off rendering. Coordinator independently reread168–198.
- Required measurement: temporary output fixtures4KiB/256KiB/1MiB/8MiB partial rows,elapsed time/seek-read counts on host then representative Android cache storage; compare block implementation with identical truncation fixtures. No speedup asserted.

## Verification / limits

No benchmarks/profiling/builds/tests. Existing bounded listing prefetch/in-flight workers,64KiB Rust output/result channel,transaction/cached-statement importer and shared FLAC tag/artwork reads retained. Per-row checkpoint/output flush preserves resume ordering, so no blind batching recommendation. Audio engines excluded. Result FINDINGS, measurement required.
