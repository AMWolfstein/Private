---
name: review
description: "Independent code review in a fresh, read-only context, and owner-requested audits. Mechanical checks first, then a review packet for a reviewer that never sees the conversation; every finding is fixed, contested with evidence, escalated or declined, and the final code must pass a clean round."
---

# Review

Review is part of each task, including TOR### and the last cumulative [FINAL] task.

1. `task check CHANGE TASK` runs the relevant checks and, when they pass, writes the packet:
   it refreshes map context and binds code, requirements and real check evidence. `task packet`
   remains for regenerating one without rerunning checks.
2. Start a fresh read-only code-reviewer with the packet path. For application bridge/data
   changes, add a second focused reviewer. Give no author opinion or expected verdict.
3. Record findings in findings.md with Severity, Status, Evidence and `- Task: T###` where
   scoped. Fix or contest with evidence; only nits may be declined. Never hide a failing test,
   unavailable tool or unresolved native boundary behind a clean verdict.
4. Record the actual verdict using `task review`. Dirty findings stay in this task: fix,
   rerun affected checks and generate a current packet for another independent review.
5. At most THREE reviews per owner-authorized cycle. Third dirty means STOP and tell the
   owner what remains and what was tried; no fourth review, commit or next task. An explicit
   owner instruction may authorize `task resume --owner-instruction "actual instruction"`;
   retain all earlier review history. Never self-authorize a new cycle.
6. Recording a clean verdict prepares completion (READY_TO_COMMIT); then ONE Git commit for
   the entire task, including review fixes and records. Any subsequent source/requirement change needs fresh checks/review.

Final [FINAL] review covers all implemented tasks together, their interactions, original
requirements and cumulative diff. Final fixes use the same loop and one task commit.

Read-only audits requested by the owner produce findings only. Design review in plan/SKILL.md
remains unchanged. Real checks do not prove semantic correctness, reviewer independence or
physical-device behavior; state any limitation. See guides/quality.md and relevant contracts.
