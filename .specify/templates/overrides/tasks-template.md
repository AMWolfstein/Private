# Tasks: [FEATURE NAME]

Input: spec.md, plan.md and necessary supporting design artifacts in this directory.
Follow `.specify/project-policy.md`. Replace all bracketed examples before committing.
This is a planning artifact, not authorization to start implementation.

## Execution rules

Sequential tasks; no parallel markers. One planning commit already contains this
list. T000 refreshes the map; T001 uses it; every later task refreshes before work.
Each task has at most three review rounds and one commit only after checks/review
pass. Add owner extras as TOR### before [FINAL]. The last task reviews all T/TOR work.

## T000 — Map and boundaries

- [ ] T000 Refresh CodeGraph and inspect the feature's architecture/boundaries.
  - Outcome: relevant entry points, affected files and coverage gaps recorded.
  - Paths: `task-log.md`, `tasks.md`; ignored `.work/codegraph/` outputs.
  - Validation: `python3 tools/codegraph/code_tools.py update`; inspect its scope,
    coverage and relevant queries. Review this evidence before marking complete.
  - Dependencies: planning commit.

## Implementation

- [ ] T001 [US1] [Concrete first outcome and exact affected source/test paths]
  - Acceptance: [observable behavior/result].
  - Validation: [actual targeted commands and baseline expectations].
  - Dependencies: T000.

[Add T002 onwards as needed, with the same outcome/paths/checks/dependencies.
Before every task after T001 refresh the map within that task, not a separate commit.]

## Owner extras

[Initially none. Insert TOR001, TOR002, etc. here or in the required dependency
position, always before the final task. Use the same acceptance/paths/checks and
review/commit rules. Do not create fictional extras during planning.]

## Final cumulative review

- [ ] T[NNN] [FINAL] Review all completed T/TOR changes against spec.md and plan.md.
  - Acceptance: cumulative review passes; all relevant actionable findings resolved.
  - Paths: all files changed for this feature plus `task-log.md`, `tasks.md`.
  - Validation: [full feasible feature-appropriate commands]; refreshed map,
    cumulative diff and boundary review; APK/device checks only when authorized.
  - Dependencies: every implementation and TOR task.
  - Review/fix loop: at most three rounds; all fixes/evidence in one final commit.

## Dependencies and evidence

[State actual dependency order, affected configurations and known limitations.]
Log task/review/check outcomes in `task-log.md`. Only mark a task complete after
its required checks/review pass. Stop and notify the owner after a third dirty
review; do not start a fourth round or silently skip findings.
