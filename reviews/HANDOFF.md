# Upstream port handoff

User authorization: continue all remaining PORT_PLAN batches through completion, without
asking again. This supersedes older one-batch stopping notes. Keep checks/checkpoints per
batch, all feature exclusions and no APK. No worktrees or force-push.

Current phase: batch 9 complete. Next: batch 10 (MORN-001..005 and MORN-017; FIX_PLAN M1+M2).
Branch/repository: ccr-2fb644cd-nmesyt, /workspace/Private.
Read-only upstream /workspace/mornye-upstream at e0563ffa; divergence v5.1.1 78699a91.
Read AGENTS.md, STATE.md, PORT_PLAN.md and PORT_EXECUTION.md; status/branch/latest commit,
fetch origin and verify before edits. Graphify before editing, update after each logical port.

U-301 adds the owner-selected optional per-player Android equalizer: 5/10/15/31 bands, tone/preamp/balance, headroom, limiter/compressor, local presets and bounded JSON import/share. A Mornye-only editor and player/settings menu routes use retained grouped controls. Audio-info now reports EQ/bypass/native errors. Existing playback transport and direct/exclusive output remain intact.

U-301 source `8e05cbbf` → graph `babdbbbe` (ecf594aa + 68c739df); installed picker/API and bounded stream import correction `892eb173` → `5c602c59`; scrolled-control test fixture `c7924c53` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1753 passed / 3 skipped / zero failures (04:16); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph fd1a520b, source 892eb173: 23,940 unique nodes / 45,919 valid links; synchronized, existing vendor extraction warnings remain.
No dependencies/schema changes, user-music writes, Darwin backend or engine replacement. EQ defaults off and native failures are visible; direct/exclusive output bypass is covered by mocked transport tests. Physical sound/driver support and share/picker targets NOT RUN. Initial Dart/native check failures were installed picker/theme API mismatches, fixed before final verification; focused widget fixtures now settle scrolling before interaction. Model/preset/native-payload/transport/input-boundary tests imported or added. No APK.
No APK, no branding/online/Material restoration or replacement engine. Physical-device
verification NOT RUN. KT-202 remains OPEN, unrelated to the planned UI ports.

Logs: /workspace/batch-9-analyze.log, batch-9-full-tests.log, batch-9-*-graphify.log;
Kotlin/Rust logs only where source changed. Exit files batch-9-flutter.exit plus relevant
native checks. See VERIFICATION.md. Docs checkpoint committed/pushed after checks; verify
HEAD against fetched origin. Latest docs SHA: git log -1 --format=%H -- reviews/HANDOFF.md.

Continue batch 10: verify findings against current source, adapt album selection header/close/action visibility; playlist/Loved circular toolbar and collapse title; loading skeletons, retained Mornye errors/empty states; playlist row Pause/resume semantics. Keep Songs/Genres/Loved Songs navigation and local menu actions unchanged. Read FINDINGS.md and use Graphify before edits. User authorized all remaining batches through 16. Native EQ service remains a small future-Media3-compatible boundary.

SOL-only policy; identity/effort not exposed, no model switching. Continue MEDIUM preference;
escalate reasoning for Rust/FFI/concurrency when needed. Activate
/workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused. Code → graph → docs commits; tests at batch boundaries.
