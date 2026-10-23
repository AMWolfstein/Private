# Optimization scope and measurement reconciliation

## Scope

Baseline968fbe57/appd5d5a02 unchanged. Repository-wide static candidate inventory,not line-by-line measured performance proof. Exact root counts in inventory.json. All328 lib paths assigned:144logic,162UI,20ARB/2localization support(cold/generated-interface scope). UI40principal hot paths bounded-body reviewed;logic17D1/D2+10D3+4root domain paths focused/read. Native304tracked paths triaged,173visible code files marker-screened,23principal native scanner/parser/job paths focused;430vendor paths retained dependency/interface context. Build/tooling/tests/config/assets classified by runtime relevance; tests/benchmarks are future measurement tools,not evidence of a production bottleneck.

Screen-only does NOT mean performance-pass:122UI paths before root artwork supplement and113logic paths outside focused sets retain exact classifications in reports09/11/12. Some deferred playback/analysis-adjacent files contain application/presentation code and are eligible for later bounded profiles. Legacy playback pure optimization is deferred by reviewer policy,not a recommendation to replace the engine. Upstream library internals were not independently profiled or rewritten.

## Findings and status

Eight P2 opportunities PERF-001..008,all NEEDS VERIFICATION. Source traces establish repeated work/index gaps/materialization patterns; actual Android impact remains unknown. No guessed speedup/device pass. Native-job/glass/artwork/list/startup chunks with no finding are valid scoped source passes,not performance certification.

Only measured evidence: synthetic host SQLite3.54.0 query plans/timings for PERF-003,100k in-memory memberships,warm5repetitions,query-only. Recorded samples in playlist-picker-host.json and report03. Android planner/storage/UI/bulk-write effects remain unrun. The other7 candidates have explicit benchmark plans,not benchmark results.

## Measurement queue

1. PERF-003 reverse membership index: Android plan/latency plus write/size tradeoff; host evidence makes this the clearest first experiment.
2. PERF-001 loaded-page combination/grouping: profile UI allocations/frame time with300/3000/15000rows.
3. PERF-006 first-cover batching: measure ordered first-cover lookup across large playlists.
4. PERF-007 backup hydration/whole-graph peak: cold100k-member export heap/RSS/worker count and round-trip parity.
5. PERF-002 interrupted-row repair: boundary-preserving byte vs block scan fixtures/device I/O.
6. PERF-004/005 TTML parse reuse/Ogg shared read: valid fixture CPU/allocations/bytes with compatibility parity.
7. PERF-008 CUE seek/decode strategy: long-album CPU/read/time and exact sample boundaries.

Drop or lower-prioritize any opportunity whose measured cost is insignificant. No optimization implementation approved or applied by this review. Preserve source identity,queue/ranking/selection order,restore/cancel/publication safeguards,exact audio precision,glass gates and visual behavior.

## Verification

All8finding IDs checked unique; report links/filenames verified. git diff --check passed. Application/native/build/test/assets source diff from968fbe57 empty. No Flutter analyzer/full tests,Android build,Rust workspace gate or device/GPU/power profile executed; source unchanged. Graph not updated(review-only). Each report01–13 committed/pushed independently; last verified before reconciliation86f10c94. No security or dead-code findings folded in. Result: repository-wide candidate-screen complete with bounded hot-path reviews; runtime profiling and screen-only bodies remain explicit limits.
