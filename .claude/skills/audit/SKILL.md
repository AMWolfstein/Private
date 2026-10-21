---
name: audit
description: "Explicit full-audit mode - review ONE bounded subsystem (ui, state, scanner, metadata, rust, kotlin, audio, storage, tests, build) with at most 2-3 reviewer agents and track coverage. Use for \"/audit <subsystem>\", \"audit the scanner\", \"full review\". Never audits the whole repo at once."
---

Follow `reviews/PROTOCOL.md`. Argument: a subsystem id (`scripts/review_scope.sh
--list-subsystems`). No argument → take `Next audit unit` from `reviews/STATE.md`, else the
next ready `partial`, `stale` or `not reviewed` unit in `reviews/AUDIT_PLAN.md`.
For a whole-project request, use the `audit-project` coordinator; this skill remains one chunk.

1. **Scope.** `scripts/review_scope.sh --subsystem <id>`: current/historical paths, changed/deleted paths, reviewers,
   graph status, last reviewed SHA (JSON output). Nonzero exit → BLOCKED, never PASS.
   A zero diff does not close partial gaps. Include changed/deleted/renamed/untracked paths
   and their direct dependents; contract changes invalidate both endpoints. Only skip a
   completed chunk when its path ledger and risk checks are current.
2. **Chunk.** Above ~25 files or ~6k lines, split into chunks by directory or feature (one
   chunk per invocation) and record the chunk in `coverage.md` as `partial`.
3. **Map.** If the graph is fresh, `graphify query "<subsystem concern>"` and `graphify
   explain "<largest class>"` to find hot spots and cross-subsystem edges; prioritise the
   largest and most-connected files. Read `graphify-out/GRAPH_REPORT.md` only if that is
   not enough.
4. **Run.** The subsystem's primary reviewer, plus its secondary and at most one path-
   triggered reviewer (security-auditor for SAF/manifest/file access, api-compat-auditor for
   contracts, dead-code-hunter for cleanup passes). Disjoint file sets when parallel.
5. **Validate, record, checkpoint** as in the `review` skill, plus update the subsystem row
   in `reviews/coverage.md` (status, reviewed SHA, chunk, finding IDs) and `Next audit unit`.
   Record exact planned/read paths and excluded checks in AUDIT_PLAN; retain partial status
   until all chunks and checks are complete. Stop after one subsystem/chunk. Do not fix.
