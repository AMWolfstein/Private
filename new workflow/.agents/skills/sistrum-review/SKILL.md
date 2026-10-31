---
name: sistrum-review
description: "Use automatically for independent review of nontrivial diffs/designs and explicitly requested subsystem audits; findings require evidence."
---

# Review

Read `workflow/quality.md`. The orchestrator supplies goal, non-goals, accepted decisions, exact revision/diff, affected domains, checks and source references. Do not inherit the author's full conversation. Verify actual code; reference documents are not proof.

Reviewer permissions: read-only, no edits/commits/pushes, no further subagents. Read beyond the diff into direct consumers and guards. Expand scope only when evidence requires it. A design review checks responsibilities, contracts, failure handling and feasibility; a code review checks implementation and regressions.

Use every relevant quality lens: cohesion, API consistency, dependency direction, initialization, data integrity, concurrency/lifecycle, error propagation, tests, measured performance and simplicity. Do not demand identical patterns for unrelated domains. No style-only findings, line quotas or cosmetic splits.

For each finding return: ID, priority, confidence, file:line, trigger, inspected guards/callers, consequence, fix and verification. Use `workflow/templates/finding.md` for persisted findings. Label unverified risk; zero findings is legitimate.

Verdict: CHANGES for confirmed material defects; NO_CONFIRMED_FINDINGS with explicit coverage limits otherwise; BLOCKED if evidence cannot be accessed. This is not product approval or device verification.

The orchestrator validates suggestions independently and tracks accepted/rejected/deferred outcomes. At most four scoped rounds; unresolved disagreement remains open. After fixes review changed code and unresolved IDs, not the entire project again.
