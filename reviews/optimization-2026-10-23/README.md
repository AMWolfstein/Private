# Code optimization review

Review baseline968fbe57; applicationd5d5a02 unchanged. **Eight P2 candidates,all NEEDS VERIFICATION.** No source changes. Repository-wide candidate screen and focused hot-path review; [coverage/limits and measurement queue](14-reconciliation.md),[inventory](inventory.json).

| Chunk | Report | Candidates | Separate commit,pushed successfully |
|---|---|---|---|
|U1a|[01](01-library-lyrics-ui.md)|PERF-001|c19cdb55|
|N1|[02](02-scan-resume.md)|PERF-002|59d0aa04|
|D1|[03](03-query-indexes.md)|PERF-003|5948eb22|
|U1b|[04](04-home-search-rows.md)|None|b7e7cb3f|
|U2|[05](05-glass-grounds.md)|None|9a96bbe3|
|N2|[06](06-native-metadata-parsers.md)|PERF-004/005|1b388b04|
|D2|[07](07-collections-backup-memory.md)|PERF-006/007|1233a514|
|A1|[08](08-artwork-image-caches.md)|None|7b1225eb|
|U3|[09](09-shared-ui-lists.md)|PERF-001 extra evidence|42930ab8|
|N3|[10](10-native-jobs-inventory.md)|None|e8d2df5e|
|D3|[11](11-metadata-cue-logging.md)|PERF-008|9e9ce5fc|
|U4|[12](12-player-shared-rendering.md)|None|8b5f6672|
|R1|[13](13-runtime-build-shaders.md)|None|86f10c94|

| Candidate | Opportunity |
|---|---|
|PERF-001|Reuse accumulated Songs page/filter snapshots; avoid repeated list copies/regrouping|
|PERF-002|Block-based repair of interrupted scan-output tail|
|PERF-003|Track-key-leading playlist membership index; synthetic host evidence supports measuring on Android|
|PERF-004|Avoid duplicate TTML normalization/XML parsing for credits|
|PERF-005|Share Ogg comment reads for tags and artwork|
|PERF-006|Stop playlist cover lookup after first usable ordered batch|
|PERF-007|Export stable collection snapshot without hydrating every playlist UI graph|
|PERF-008|Measure accurate seek/shared decode for multi-track CUE split|

Host-only evidence: [SQLite plans/raw timing samples](playlist-picker-host.json); no Android/app speedup asserted. All other improvements are hypotheses with source evidence and concrete measurement plans. Flutter/device/GPU/power/engine profiling remains unrun; compiler/testing gates are for subsequent implementation. Legacy playback pure optimization and upstream internals deferred by reviewer policy; screen-only bodies remain uncovered by focused analysis. Security checks skipped as previously requested.
