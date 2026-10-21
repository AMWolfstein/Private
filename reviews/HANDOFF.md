# Upstream port handoff

User authorization: continue all remaining PORT_PLAN batches through completion, without
asking again. This supersedes older one-batch stopping notes. Keep checks/checkpoints per
batch, all feature exclusions and no APK. No worktrees or force-push.

Current phase: batch 15 complete. Next: batch 16 (one reviewed dead-code patch and final compatibility report).
Branch/repository: ccr-2fb644cd-nmesyt, /workspace/Private.
Read-only upstream /workspace/mornye-upstream at e0563ffa; divergence v5.1.1 78699a91.
Read AGENTS.md, STATE.md, PORT_PLAN.md and PORT_EXECUTION.md; status/branch/latest commit,
fetch origin and verify before edits. Graphify before editing, update after each logical port.

Refreshed upstream main remains e0563ffa. Compared all shared Pub declarations and overrides, resolved shared Cargo versions through both workspaces, and checked Flutter/Gradle/Android toolchain pins. No retained dependency version changes are available; no manifest or lockfile changes required.

Comparison-only checkpoint. Evidence: reviews/upstream-v5.2.0-dependencies.json; upstream e0563ffad6df9f01d3e73e6099f74417422374de. Source remains batch 14.

REUSED batch 14 verification for identical source; no redundant test execution in documentation-only batch 15. PASS: analysis clean; Flutter 1775 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 53a17a8e, source 822a4656: 23,988 unique nodes / 46,040 valid links; synchronized, existing vendor extraction warnings remain.
33 shared runtime packages, eight development packages, one common override and 20 shared workspace Cargo dependencies have matching versions; direct mobile workspace declarations resolve to the same roxmltree/rusqlite versions. Local-only crate has no equivalent upstream path. Upstream-only network, service, iOS and branding dependencies rejected. No dependency additions or APK.
No APK, no branding/online/Material restoration or replacement engine. Physical-device
verification NOT RUN. KT-202 remains OPEN, unrelated to the planned UI ports.

Logs: /workspace/batch-15-analyze.log, batch-15-full-tests.log, batch-15-*-graphify.log;
Kotlin/Rust logs only where source changed. Exit files batch-15-flutter.exit plus relevant
native checks. See VERIFICATION.md. Docs checkpoint committed/pushed after checks; verify
HEAD against fetched origin. Latest docs SHA: git log -1 --format=%H -- reviews/HANDOFF.md.

Complete batch 16 as one reviewed patch. Re-run Graphify and references before removals. Prepared tools in /tmp are review aids only: mornye_constant_fold.dart (compiled without input), ast_remove.py (dry-run unless --write), batch16-findings.txt and batch16-importers.json. Native/Rust/Flutter checks required after source changes, no APK. Preserve newly live loveAllTracks, ErrorCard, artworkAspectRatio, haptics SAF jobs; keep NativeReplayGainPolicy and MANAGE_EXTERNAL_STORAGE. Regenerate ignored UniFFI Kotlin through scripts/build_rust_backend.sh. Delete unused localization keys last; no schema migration. Then create requested final audit/report aliases with honest selected-item counts and remaining open risks.

SOL-only policy; identity/effort not exposed, no model switching. Continue MEDIUM preference;
escalate reasoning for Rust/FFI/concurrency when needed. Activate
/workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused. Code → graph → docs commits; tests at batch boundaries.
