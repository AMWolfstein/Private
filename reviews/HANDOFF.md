# Upstream port handoff

User authorization: continue all remaining PORT_PLAN batches through completion, without
asking again. This supersedes older one-batch stopping notes. Keep checks/checkpoints per
batch, all feature exclusions and no APK. No worktrees or force-push.

Current phase: batch 13 complete. Next: batch 14 (PLAY-001..004 and U-311).
Branch/repository: ccr-2fb644cd-nmesyt, /workspace/Private.
Read-only upstream /workspace/mornye-upstream at e0563ffa; divergence v5.1.1 78699a91.
Read AGENTS.md, STATE.md, PORT_PLAN.md and PORT_EXECUTION.md; status/branch/latest commit,
fetch origin and verify before edits. Graphify before editing, update after each logical port.

HOME-001..008 adapt the local editorial feed: aspect-preserving indexed artwork with embedded fallback, cached shelves across scans, pull-to-refresh, guided empty/retry states and loading skeletons; localized dates, explicit labels and responsive themed cards; stable identities and Home reselect scrolling. Removed two unused Home parts and the unreachable branding intro.

Source `0d9dbf9c`, lint correction `504a38df` → graph `4b4fe09f`; cached-refresh fixture `f5ec3973` and hydration guard `c4e9e536` → graph `8ad07efd`. Compared upstream Home sizing/skeleton patterns at e0563ffa.

PASS: analysis clean; Flutter 1771 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 8ad07efd, source c4e9e536: 23,983 unique nodes / 46,028 valid links; synchronized, existing vendor extraction warnings remain.
Recently Added ordering and release-tag-only Latest Releases queries unchanged. Optional long-press menus omitted; existing local detail navigation retained. Initial tests exposed viewport assumptions and missing standalone Intl date initialization, corrected before final checks. No music-file writes/dependencies/native changes or APK. Home same-path image invalidation remains with existing metadata/cache ownership. Tablet/device visual comparisons NOT RUN.
No APK, no branding/online/Material restoration or replacement engine. Physical-device
verification NOT RUN. KT-202 remains OPEN, unrelated to the planned UI ports.

Logs: /workspace/batch-13-analyze.log, batch-13-full-tests.log, batch-13-*-graphify.log;
Kotlin/Rust logs only where source changed. Exit files batch-13-flutter.exit plus relevant
native checks. See VERIFICATION.md. Docs checkpoint committed/pushed after checks; verify
HEAD against fetched origin. Latest docs SHA: git log -1 --format=%H -- reviews/HANDOFF.md.

Proceed with prepared /tmp/port_batch14.py after reviewing exact hunks. Lift track swipe scope above player stack while standalone layouts retain scope; remove rotation-dependent background key; adapt U-311 ratio/fade while retaining PlayerView Normal/Immersive. Test immersive gestures and rotation, then finish dependencies and one dead-code patch.

SOL-only policy; identity/effort not exposed, no model switching. Continue MEDIUM preference;
escalate reasoning for Rust/FFI/concurrency when needed. Activate
/workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused. Code → graph → docs commits; tests at batch boundaries.
