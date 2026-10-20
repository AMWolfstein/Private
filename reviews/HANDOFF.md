# Upstream port handoff

Current phase: batch 4 completion; stop before batch 5.
Branch/repository: `ccr-2fb644cd-nmesyt`, `/workspace/Private`.
Entry checkpoint `6419d21e`; remote fetched/equal and working tree clean at start.
Read-only upstream clone `/workspace/mornye-upstream` at `e0563ffa`.
Baseline v5.1.1 `78699a91`; use PORT_PLAN for current batch order.

Batch 4 source → graph:
- U-205 upstream `f426b2d1f0cc256d34267b511665c0e8de6d16c8`:
  `6e44c6be` → `a95ffcf6`. Ordinary audio error forwarding, playback error state and
  foreground feedback, stop/retry without treating error as completion. Vendor MediaPlayer
  changes preserve the existing descriptor patch. No EQ or replacement engine imported.
  Patch recorded in third_party/audioplayers_android/SPOTIFLAC_PATCHES.md.
- U-216 upstream `9ded49f31e2d8dd341bba528b7fb3dfe7060a03a`:
  `95e2b158` → `4c66e5e7`. CurrentMediaItemNotifier notifies identity changes for same-ID
  snapshots; ID selectors unchanged. OverrideWithBuild migration covers current local tests
  and integration fixtures. Provider regression and Mornye light/dark late-duration tests.
- U-206 upstream `97d8ee3695384cf3f32b89d610f761c90c601f8f`: no applicable code port;
  legacy material_player_layout.dart still exists as fallback code, but production AppThemeStyle
  has only Mornye. REJECT Material-only UI changes. Mornye header
  builds the current title directly through PlayerTrackSwipeTitles; no outgoing-title stack.
- U-207 upstream `186c66aeb8c07025402afe78e58a76e4578f6cfa`:
  `d0818d7a` → `a85b4965`. Context SAF parent/sidecar helpers ask provider ancestry, verify
  returned tree/end and verify fallback child identity. Existing native channel returns
  failure; Dart requested sidecar writes propagate failure. Online reEnrichFile handler and
  extension/download Rust tests excluded; no conversion/mode UI restored. Two native provider
  tests imported; three Dart sidecar cases check timing, unchanged audio and write errors.
- Graph source d0818d7a2b22c27b088e3d988a98aa211e219183: 23,112 unique nodes /
  44,630 valid links, final graph commit a85b4965. Existing vendor syntax warnings remain.
- KT-202 remains OPEN; no unrelated CUE reconciliation fix made.

Batch 4 verification: PASS: analysis clean; full Flutter 1,657 passed / 3 skipped / zero failures (4m10s); Android unit 59 passed / 1 skipped; changed plugin and instrumentation Kotlin/Java compiled (1m58s).
Analysis clean. No Rust source changes: Rust fmt/clippy/test script not required/run.
Gradle tasks checked for absence of APK/assemble packaging. Instrumentation execution and
physical-device output/SAF behavior NOT RUN; compilation is distinct from device testing.
Logs: /workspace/batch-4-analyze.log, batch-4-full-tests.log, batch-4-kotlin.log,
batch-4-gradle-dry-run.log, batch-4-U205-graphify.log, batch-4-U216-graphify.log,
batch-4-U207-graphify.log. Exit files batch-4-flutter.exit and batch-4-kotlin.exit.
Push status: source/graph `a85b4965` pushed and fetched successfully. This docs checkpoint
is committed/pushed afterward; final remote equality is checked in session output.
Fetch/compare remote HEAD before edits on resume. Latest docs SHA:
`git log -1 --format=%H -- reviews/HANDOFF.md`.

Next exact work unit, only when requested: batch 5 — U-214, U-215, U-208, U-209.
Read AGENTS, STATE, PORT_PLAN, UPSTREAM; status/branch/checkpoint then Graphify before edits.
U-215 affects third_party/audio_service: record its patches note; U-209 skips download/iOS.
One code → graph checkpoint per logical port; checks once at batch end, docs, push/fetch.
No APK, branding, Material, online, player replacement or premature later batches.

Model policy SOL only; identity and runtime effort not exposed, no model switch.
User requested MEDIUM effort for batch 4, overriding prior HIGH recommendation.
Recommended next effort MEDIUM unless source evidence requires escalation.
Activate /workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused; no configuration changes or new worktrees.
