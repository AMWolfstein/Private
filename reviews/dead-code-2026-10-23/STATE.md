# Dead-code review state

Baseline47039b90 (application source d5d5a02); independent review-only dead-code audit. User requests every divided check have its own commit and immediate push. No removals or graph changes. Further security checks excluded at owner's request. All code is screened for dead-code candidates, including audio engine reachability; public vendor/FFI/generated/test compatibility seams are retained unless proven obsolete.

Chunks: N1 Android complete (01-android.md); D1 Dart logic, D2 Dart UI, N2 Rust, N3 third-party plugin, R1 assets/localization/dependencies/scripts pending. Screening is distinct from exhaustive body review. Each report records limitations; compiler/tree-shaker results NOT RUN unless recorded.

Findings: DEAD-001/002 (P3). Last verified push prior to this audit47039b90. Current checkpoint publication recorded in next chunk.
