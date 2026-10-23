# Dead-code review state

Baseline47039b90 (application source d5d5a02); independent review-only dead-code audit. User requests every divided check have its own commit and immediate push. No removals or graph changes. Further security checks excluded at owner's request. All code is screened for dead-code candidates, including audio engine reachability; public vendor/FFI/generated/test compatibility seams are retained unless proven obsolete.

Chunks: N1 Android complete (01-android.md); D1 Dart logic complete (06-dart-logic.md), D2 Dart UI, N2 Rust complete (05-rust-entrypoints.md), N3 third-party plugin, R1 assets/localization complete (02-localization-assets.md); R2 dependencies/scripts complete (03-dependencies-scripts.md). Screening is distinct from exhaustive body review. Each report records limitations; compiler/tree-shaker results NOT RUN unless recorded.

Findings: DEAD-001..011 (P3). Last verified pushbd91cb78 (N2), successful to origin/ccr-2fb644cd-nmesyt. Current checkpoint publication recorded in next chunk.

R3 test-support chunk complete (04-test-support.md):254 Dart runner roots retained,12 support paths screened.
