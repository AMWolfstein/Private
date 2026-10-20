# Upstream port handoff

Current phase: batch 3 completion; stop before batch 4.
Repository/branch: `/workspace/Private`, `ccr-2fb644cd-nmesyt`.
Upstream reference: `/workspace/mornye-upstream`, `e0563ffa` (read-only).
Historical baseline: v5.1.1 `78699a91`; current PORT_PLAN is authoritative for batch order.
Entry checkpoint: `3e4be675`; remote fetched and matched at task start; clean working tree.

Completed batch 3 (source → graph):
- U-203 `080df889`: local album/header/grid missing/empty scan artwork recovery through
  existing bounded embedded cache. Local controls and light/dark retained.
  `e70ae974` → `b680bdd4`; upstream widget tests adapted to retained local Mornye UI.
- U-212 `9dc86e13`: aligned ID3 PIC/APIC description parsing shared with container cover
  reader; strip NUL padding only before recognized image signatures; repair old app-owned
  cached JPEG previews. No user music rewrite, schema migration or dependencies.
  `1d8e8f76` → `c5086af3`; crates/extensions hunks rejected; Rust/Dart regressions added.
- U-213 `60d00191`: local-path playback joins SAF embedded-art recovery; helper filters
  nonlocal sources. Existing remote references can be replaced by local extraction, never
  fetched; retained request-generation checks protect queue/session updates.
  `d256e0c7` → `a7cc1b9f`; playback artwork tests adapted.
- U-204 `161a216b`: wait for effect progress and alignment before handoff; render sufficient
  source for faster effects. Existing engine, dry fallback, cancellation and cleanup kept.
  `a41d3d4e` → `de32a041`; production patch applies unchanged; stalled-effect test uses a
  four-second event deadline so it does not race the production two-second timeout.
- Final Graphify built from `a41d3d4e1660fe623c2965916f3f03c2c933d632`:
  23,093 unique nodes / 44,593 valid links. Existing vendor/preprocessor warnings remain.
- Prior batches 1/1b/2 complete. U-201 does not fix KT-202, which remains OPEN.
  U-202 saved WIP already removed in batch 2; no patch/stash to restore.

Batch 3 verification: PASS: analysis clean; full Flutter 1,644 passed / 3 skipped / zero failures (3m55s); Rust fmt/Clippy clean, 231 passed / 1 ignored.
Confirmed: flutter analyze clean; Rust fmt, Clippy -D warnings, 231 tests passed / 1 ignored.
No Kotlin source changed: Gradle/Kotlin checks NOT RUN this batch (passed in batch 2).
No APK, instrumentation, physical-device audio/SAF checks, or runtime profiling.
Logs: `/workspace/batch-3-analyze.log`, `batch-3-full-tests.log`, `batch-3-rust-check.log`,
`batch-3-U203-graphify.log`, `batch-3-U212-graphify.log`, `batch-3-U213-graphify.log`,
`batch-3-U204-graphify.log`. Logs are cloud-local; results persisted in VERIFICATION.md.
Push status: source/graph checkpoint `de32a041` pushed and fetched successfully. This docs
checkpoint is committed/pushed afterward; final remote equality is verified in session
output. Check remote HEAD on resume; final docs SHA can be found with
`git log -1 --format=%H -- reviews/HANDOFF.md`.

Next exact work unit, only when requested: PORT_PLAN batch 4 — U-205, U-216, U-206, U-207.
Read AGENTS, PORT_PLAN, STATE, UPSTREAM and source diffs; inspect status/latest checkpoint,
fetch active branch, query Graphify before code edits. Code → graph per logical port,
checks once at batch end, docs checkpoint then push/fetch/compare. No APK, online, Material
or branding imports; preserve retained artwork, metadata, lyrics, statistics and playback.

Model policy: SOL only requested; identity/effort not exposed, no switch made.
Recommended thinking effort: HIGH (decoder ownership, duration updates and file/resource safety).
Environment: `source /workspace/toolchains/activate.sh`; Graphify at
`/workspace/toolchains/graphify/bin/graphify`. Toolchain already prepared; no environment
configuration changes required this batch. Use existing checkout; no new worktrees.
