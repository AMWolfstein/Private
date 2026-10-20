# Upstream port handoff

Current phase: batch 2 completion; stop before batch 3.
Repository/branch: `/workspace/Private`, `ccr-2fb644cd-nmesyt`.
Upstream reference: `/workspace/mornye-upstream`, `e0563ffa` (read-only).
Historical comparison baseline: v5.1.1 `78699a91`; use current PORT_PLAN, not old audit batches.

Completed batch 2:
- U-202 code `0f51f5d02cbd4a099564a11414c9243a1898b7f2`, upstream
  `3dc2d69051ff6a61acc1fc0767cc8c6dc42e993f`. Reviewed WIP reused, `.rej` excluded,
  proper license asset added; WIP deleted in docs checkpoint.
- U-201b `e58217c8`: no applicable local production changes (only removed network scanner).
  Existing local native data-job/scan cancellation and cleanup already present.
- Optional `931b1091` exit-importance diagnostics not needed by U-201; crash notices excluded.
- KT-202 still OPEN; neither scan recovery nor network memory cleanup fixes incremental CUE
  standalone duplicates. No unrelated SAF fix applied.
- Graph `6361145f`, source `0f51f5d0`, validated 23,056 nodes / 44,447 links.
  Existing vendored preprocessor extraction warnings remain.
- No Rust source changed (USB README only), no engine migration, no APK.

Verification: PASS: analysis clean; full Flutter 1,629 passed / 3 skipped / zero failures (4m02s); Android unit 59 passed / 1 skipped; native host CTest 1/1 passed; ARM64 JNI/library build passed.
Logs: `/workspace/batch-2-analyze.log`, `batch-2-full-tests.log`,
`batch-2-kotlin-native.log`, `batch-2-native-host.log`, `batch-2-graphify.log`.
Android ARM64 native library exports all five Flac JNI entry points (llvm-nm verified).
Instrumentation/physical USB or DAP testing: NOT RUN (no device/APK).
Rust fmt/clippy/tests script: NOT RUN, not required for documentation-only Rust change.
Push status: source/graph checkpoint `6361145f` pushed and fetched successfully. This
docs checkpoint is committed/pushed afterward; final remote equality is verified in session
output. On resume fetch/compare active branch before editing. Locate the latest docs SHA
with `git log -1 --format=%H -- reviews/HANDOFF.md`.

Next exact work unit, only when requested: PORT_PLAN batch 3 — U-203, U-212, U-213, U-204.
Read AGENTS.md, PORT_PLAN.md, STATE.md, UPSTREAM.md; inspect status/branch/latest checkpoint
and fetch remote. Inspect upstream source and Graphify links before edits. U-212 must omit
crates/extensions. One code → graph commit per logical port; tests once at batch end;
separate docs checkpoint, push and fetch/compare. No APK and no branding/online/Material ports.

Model policy: SOL only requested; runtime identity/effort not exposed, no switch made.
Recommended thinking effort: HIGH (metadata/artwork parsing and native integrity).
Environment: `source /workspace/toolchains/activate.sh`; Graphify at
`/workspace/toolchains/graphify/bin/graphify`. Host CMake/CTest at
`/workspace/toolchains/android-sdk/cmake/4.1.2/bin/`. Reuse checksum-verified libFLAC
source in `/workspace/toolchains/native-sources/flac-1.5.0` via FETCHCONTENT_SOURCE_DIR_FLAC.
