## Latest task: review workflow maintenance (2026-10-21)

Implemented review-scope fixes, coordinator, specialist coverage and evidence rules in one
combined commit as explicitly requested. This updates the auditing system; it does not
claim the missing application audits were performed. Next: CONTRACT-01 in AUDIT_PLAN.md,
then data-safety/native-lifetime/accessibility units in priority order. Historical coverage
is reopened partial/stale. Verify current branch/status and the latest commit on resume.
Push NOT RUN for this maintenance batch. Existing port/release history follows.

# Upstream port handoff

User authorization: continue all remaining PORT_PLAN batches through completion, without
asking again. This supersedes older one-batch stopping notes. Keep checks/checkpoints per
batch, all feature exclusions and no APK. No worktrees or force-push.

Latest APK: build 167 (`c76237c6`), signed ARM64 Local; download branch `apk-local-arm64-167`. Certificate matches build 166. Build/audit/analysis/full tests pass; physical-device checks remain NOT RUN. [Download](https://github.com/AMWolfstein/Private/raw/refs/heads/apk-local-arm64-167/SpotiFLAC-Local-167-arm64-v8a.apk).

Current phase: batch 16 complete. Next: none in PORT_PLAN; physical-device verification and separately approved remaining review fixes.
Branch/repository: ccr-2fb644cd-nmesyt, /workspace/Private.
Read-only upstream /workspace/mornye-upstream at e0563ffa; divergence v5.1.1 78699a91.
Read AGENTS.md, STATE.md, PORT_PLAN.md and PORT_EXECUTION.md; status/branch/latest commit,
fetch origin and verify before edits. Graphify before editing, update after each logical port.

Retired unreachable Material Expressive UI and direct dependencies, download/provider/re-enrichment and iOS bridge APIs, dead Rust modules and unused settings/widgets/resources. Preserved offline metadata/lyrics editing, Audio Quality Analysis, CUE, local collections, playback and legacy backup/schema compatibility. Removed 70 unused l10n keys last; added native check script and test resource/timeout cleanup. Disabled selection actions retain explicit accessible state and 48px targets.

One reviewed source patch `ef8ba64d`; Graphify checkpoint recorded below. Cleanup follows FIX_PLAN Tier 3, not an upstream merge. Existing source-to-upstream mappings remain in UPSTREAM.md and prior PORT_EXECUTION checkpoints.

PASS: analysis clean; Flutter 1513 passed / 3 skipped / zero failures (02:09); Android unit 55 passed / 1 skipped; Rust fmt/Clippy PASS, 165 passed / 1 ignored.
Graph 331ab3d0, source ef8ba64d: 22,436 unique nodes / 42,940 valid links; synchronized, existing vendor extraction warnings remain.
Native unit checks and Rust fmt/Clippy/tests pass; regenerated host UniFFI bindings. Instrumentation sources compile, but device execution is NOT RUN. Paging regression passes 10/10. Test-only APIs and their obsolete cases were retired; retained Mornye fixtures were adapted, not skipped. DEAD-806 remains partially open for legacy bookmark/path compatibility; DEAD-702 and unrelated DATA-501/KT-202 remain outside this batch. NativeReplayGainPolicy, MANAGE_EXTERNAL_STORAGE, live skeleton/ErrorCard/artist artwork, canonical ISRC helper and haptics SAF jobs retained. Atomic SAF helper retained per plan. No APK or runtime performance claim. material_ui remains an existing transitive dependency of retained go_router 18.0.2; no production material_ui imports/delegate remain. Replacing the router to remove that transitive dependency is outside this cleanup and needs a separate architectural decision.
No APK, no branding/online/Material restoration or replacement engine. Physical-device
verification NOT RUN. KT-202 remains OPEN, unrelated to the planned UI ports.

Logs: /workspace/batch-16-analyze.log, batch-16-full-tests.log, batch-16-graphify.log;
Kotlin/Rust logs only where source changed. Exit files batch-16-flutter.exit plus relevant
native checks. See VERIFICATION.md. Docs checkpoint committed/pushed after checks; verify
HEAD against fetched origin. Latest docs SHA: git log -1 --format=%H -- reviews/HANDOFF.md.

All planned batches complete. See upstream-v5.2.0-final-report.md for scope/counts, checkpoints and limitations. Do not restart cleanup from old orphan lists: some formerly dead components are now live. Next safe unit is physical-device verification of Immersive/lyrics/queue, metadata and SAF editing, EQ and haptics; remaining review fixes require their separate plan.

SOL-only policy; identity/effort not exposed, no model switching. Continue MEDIUM preference;
escalate reasoning for Rust/FFI/concurrency when needed. Activate
/workspace/toolchains/activate.sh; Graphify /workspace/toolchains/graphify/bin/graphify.
Existing cloud setup reused. Code → graph → docs commits; tests at batch boundaries.

Graphify note: existing vendor syntax/preprocessor extraction warnings remain. Community names use retained labels or hub-based fallback; semantic relabeling was not run. The AST dependency graph and endpoints are synchronized.
