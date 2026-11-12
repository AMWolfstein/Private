---
name: "speckit-implement"
description: "Execute the implementation plan by processing and executing all tasks defined in tasks.md"
compatibility: "Requires spec-kit project structure with .specify/ directory"
metadata:
  author: "github-spec-kit"
  source: "templates/commands/implement.md"
---

## Repository execution policy (local adaptation)

Before using this skill, read `.specify/project-policy.md` and
`.specify/memory/constitution.md`. The owner's current instructions take priority.
The local policy overrides conflicting upstream defaults: one planning commit,
T000 map refresh, sequential task/review/fix loops, at most three review rounds,
one commit per completed task, TOR### extras and one final cumulative-review task.
Do not add approval gates, automatic commits at intermediate planning stages,
parallel task execution, or unbounded implement/converge cycles. A planning-only
request must not start implementation. The retained audit/navigation skills stay
standalone. These additions are local adaptations, not upstream GitHub requirements.



## User input and prerequisites

Consider the user's current instructions, especially planning-only requests.
Run `.specify/scripts/bash/check-prerequisites.sh --json --require-tasks --include-tasks`
from the repository root; read the feature spec.md, plan.md, tasks.md and relevant
supporting artifacts. Use `SPECIFY_FEATURE_DIRECTORY` to select an existing feature
if the ignored local pointer is missing. Do not infer feature ownership from the
current Git branch name. Preserve unrelated changes.

## Sequential execution

1. Confirm completed planning artifacts are committed together once. If only a
   plan was requested, stop there. Otherwise identify the first unfinished task;
   do not restart completed tasks or rebuild the plan for each task.
2. T000 refreshes CodeGraph and records architecture/coverage evidence in the
   task log. Review that result; its completion/log/checkbox are one T000 commit.
3. T001 uses the T000 map. Refresh the map at the start of every later task,
   including TOR and [FINAL], and inspect relevant symbols/boundaries. Keep cache
   outputs ignored. Do not create a separate map-update commit.
4. Read acceptance criteria and exact paths. Implement only the current task.
   Format/check/test affected code using actual project commands. Compare failures
   with the baseline and report unavailable coverage. No APK without authorization.
5. Obtain a read-only independent review using `.agents/reviewers/task-reviewer.md`.
   Fix/revalidate and review again when needed. Record the reviewer, round and
   result in `task-log.md`. Three review results maximum per task; after a third
   NEEDS_FIXES/BLOCKED result stop and notify the owner with remaining issues.
   Never hide an unavailable independent reviewer behind a self-review PASS.
6. After checks/review pass, mark the task complete and commit code, tests,
   task-log and checkbox together exactly once. No intermediate WIP/fix/review
   commits. Continue sequentially to the next task; no parallel `[P]` execution.
7. Owner extras outside the plan become unique TOR### tasks, executed through
   the same loop and committed once each before [FINAL]. Do not reset existing
   review counters or silently expand the current task.
8. Execute the final cumulative-review task last. Review all T/TOR changes against
   spec/plan with full feasible checks. Fix/revalidate/re-review inside the same
   bounded loop; put every final fix and its completion evidence in one commit.
   Do not add an unbounded sequence of convergence tasks.

## Outcome

Report completed tasks and commit IDs, actual checks/review outcomes, remaining
findings and limitations. Publish only when authorized. No automatic merging,
force-pushing, fingerprints, legacy work.py gates or additional approvals.
