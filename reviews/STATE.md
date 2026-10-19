# Upstream audit state

- Phase: upstream v5.2.0 discovery plus scanner subsystem comparison complete; **no backports implemented**.
- Subsystem: scanner recovery/notification ordering (378c8f37) compared; next B01a implementation. Detailed plan: upstream-v5.2.0-scanner-review.md.
- Branch: `review/upstream-v5.2.0-discovery`; source entry HEAD `2b323612a7e473ef9a4e5d6a48ebb071add25924`. Main/work source not modified.
- Baseline: high-confidence content equivalent `5a8952659b247fd95f1914a56db60825657fe26d`; local parentless root `47298e55b1eef2cfdbef1f7b80570a164bfa2f3b`. No shared Git merge base; ancestry unproven.
- Target: release v5.2.0 peeled `22f3ec52f9bd1e57f661ca0b17e3aaa34b0e8ae8` (pinned, not current upstream main).
- Coverage: 238 commits including one merge, 858 paths indexed; 17 focused source comparisons, one partial source comparison, 220 path-only entries. Behavioral audit incomplete.
- Scoped commit decisions: ADOPT 0; ADAPT 7; ALREADY IMPLEMENTED 2; REJECT 46; DEFER 138; INVESTIGATE 45. Counts are commit scopes, not independent feature totals.
- Approved candidates: B01a failure visibility/notice ordering, B01b recovery reporting, B01c optional exit diagnostics, B02 playlist controller disposal, B03 local Rust credit regexes, B04 local cover recovery, B05 timed lyric geometry, B06 pronunciation regexes, B07 Mornye Logs sheet. All pending, with backlog gates.
- Rejected: online/Material Expressive wholesale import and intentional removed-feature restoration; see inventory for mixed scopes.
- Deferred: legacy engine/DSP/native decoder, generic structural cleanup, unnecessary write-helper centralization and upstream publishing CI.
- Unresolved: output-error completion; SAF ancestry/write reachability; remaining subsystem comparisons; resolved dependency/security review; existing residual Expressive imports/dependencies despite sole Mornye production theme.
- Graphify: CURRENT for unchanged application source `6ac8efd0` through graph commit `81577e50042177e8e9c71a81402efd362df69d6b`; no source changes or graph update required this unit.
- Verification: see VERIFICATION.md. Existing focused scanner/pause/notification suite PASS: 20 tests. New regressions/analysis/full suite/native checks/build NOT RUN this comparison-only unit. No APK built.
- Model: SOL requested; runtime model identity/thinking-effort setting not exposed, so not independently confirmed. No model switching or delegated agents used.
- Recommended next thinking effort: HIGH.
- Exact next unit: implement B01a only (original failure visibility, serialized scan notices and cleanup/pause ordering) per scanner review; targeted faults/races + analysis, code→graph→docs commits and push; no B01b/c or APK.
- Checkpoint SHA/push receipt: maintained in HANDOFF.md; current tip always obtained with `git rev-parse HEAD` (a file cannot embed its own resulting commit SHA).
