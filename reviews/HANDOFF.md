# Upstream port handoff

User authorization: continue all remaining PORT_PLAN batches through completion, without
asking again. This supersedes older one-batch stopping notes. Keep checks/checkpoints per
batch, all feature exclusions and no APK. No worktrees or force-push.

Current phase: batch 14 complete. Next: batch 15 (shared dependency comparison against refreshed upstream main).
Branch/repository: ccr-2fb644cd-nmesyt, /workspace/Private.
Read-only upstream /workspace/mornye-upstream at e0563ffa; divergence v5.1.1 78699a91.
Read AGENTS.md, STATE.md, PORT_PLAN.md and PORT_EXECUTION.md; status/branch/latest commit,
fetch origin and verify before edits. Graphify before editing, update after each logical port.

PLAY-001..004 and U-311 adapt Immersive cover proportions/fade and a shared artwork/title swipe scope, retain the background across rotation, label the lyrics-size control and match queue swipe corners. Separate inset/full-bleed artwork keys and bounded ownership prevent rotation/rapid-view conflicts; queue-index selection avoids transport rebuilds on clock updates.

U-311 upstream `05a56133` → source `3dfa8b73` → graph `140ecef1`; lint `45c40118` → `9f62788e`; fixtures `5fd4892a` → `72145734`; ownership/subscription correction `822a4656` → `3c9fe836`, labels `53a17a8e`. PLAY-003 behavior also present in upstream befcd2ad; adapted using Semantics around the installed Flutter Slider.

PASS: analysis clean; Flutter 1775 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 53a17a8e, source 822a4656: 23,988 unique nodes / 46,040 valid links; synchronized, existing vendor extraction warnings remain.
Normal remains default; persisted Immersive and landscape two-column behavior retained. Existing backdrop saturation and full-bleed Hero gating already match useful upstream behavior. Focused regressions caught and fixed GlobalKey ownership and clock-rebuild defects; ten corrected regressions pass. Transparent foreground artwork gesture region intentionally receives Immersive drags. Physical side-by-side visuals NOT RUN. No engine/dependencies/native changes, user-music writes or APK.
No APK, no branding/online/Material restoration or replacement engine. Physical-device
verification NOT RUN. KT-202 remains OPEN, unrelated to the planned UI ports.

Logs: /workspace/batch-14-analyze.log, batch-14-full-tests.log, batch-14-*-graphify.log;
Kotlin/Rust logs only where source changed. Exit files batch-14-flutter.exit plus relevant
native checks. See VERIFICATION.md. Docs checkpoint committed/pushed after checks; verify
HEAD against fetched origin. Latest docs SHA: git log -1 --format=%H -- reviews/HANDOFF.md.

Upstream origin/main refreshed to unchanged e0563ffad6df9f01d3e73e6099f74417422374de. /tmp/batch15-dependency-comparison.json resolves workspace versions: no retained version differences; toolchain pins identical. Document batch 15 without redundant unchanged-source full tests (reuse batch 14 checks explicitly), then perform batch 16 one dead-code patch. Graphify before removals. /tmp/mornye_constant_fold.dart is an AST review aid, compiled with no inputs only; NOT executed on repository. Recheck live references: loveAllTracks/ErrorCard/artworkAspectRatio/SAF haptics now live; keep NativeReplayGainPolicy and MANAGE_EXTERNAL_STORAGE.

SOL-only policy; identity/effort not exposed, no model switching. Continue MEDIUM preference;
escalate reasoning for Rust/FFI/concurrency when needed. Activate
/workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused. Code → graph → docs commits; tests at batch boundaries.
