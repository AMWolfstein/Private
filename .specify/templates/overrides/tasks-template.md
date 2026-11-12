# Tasks: [FEATURE NAME]

Input: spec.md, plan.md and necessary supporting design artifacts in this directory.
Follow `.specify/project-policy.md`. Replace all bracketed examples before committing.
This is a planning artifact, not authorization to start implementation.

## Execution rules

Sequential tasks, starting at T001; no parallel markers. One planning commit
contains this list. The **first action in every task**, including T001, TOR### and
[FINAL], is `python3 tools/codegraph/code_tools.py update`. Inspect its scope and
coverage before task analysis or edits; stop/report if refresh fails. There is no
dedicated map task or map-only commit. Keep `.work/` ignored and record concise
refresh evidence in `task-log.md` within the task's single commit.

Each task has at most three review rounds and one commit only after checks/review
pass. Add owner extras as TOR### before [FINAL]. The last task reviews all T/TOR work.

## Implementation

- [ ] T001 [US1] [Concrete first outcome and exact affected source/test paths]
  - Start: refresh the map first, inspect coverage and relevant boundaries.
  - Acceptance: [observable behavior/result].
  - Validation: [actual targeted commands and baseline expectations].
  - Dependencies: planning commit.

[Add T002 onwards as needed, with the same start/outcome/paths/checks/dependencies.
Every task begins with its own map refresh, within that task's single commit.]

## Owner extras

[Initially none. Insert TOR001, TOR002, etc. here or in the required dependency
position, always before the final task. Use the same first-action map refresh,
acceptance/paths/checks and review/commit rules. Do not invent extras during planning.]

## Final cumulative review

- [ ] T[NNN] [FINAL] Review all completed T/TOR changes against spec.md and plan.md.
  - Start: refresh the map first and inspect its coverage/boundaries.
  - Acceptance: cumulative review passes; all relevant actionable findings resolved.
  - Paths: all files changed for this feature plus `task-log.md`, `tasks.md`.
  - Validation: [full feasible feature-appropriate commands]; cumulative diff and
    boundary review; APK/device checks only when authorized.
  - Dependencies: every implementation and TOR task.
  - Review/fix loop: at most three rounds; all fixes/evidence in one final commit.

## Dependencies and evidence

[State actual dependency order, affected configurations and known limitations.]
Log task/map/review/check outcomes in `task-log.md`. Only mark a task complete after
its required checks/review pass. Stop and notify the owner after a third dirty
review; do not start a fourth round or silently skip findings.
