# Local Spec Kit policy

GitHub Spec Kit provides specify → clarify (when needed) → plan → tasks →
implement. This document supplies the owner's local execution and Git rules;
these rules are not upstream Spec Kit defaults. Current owner instructions win.
Read the constitution and the applicable official `speckit-*` skill.

## When to plan

Small, isolated, low-risk edits may use direct implementation, targeted checks and
one commit. Documentation, translations, comments and a local header/button edit
usually qualify when no stored-data/API/runtime boundary is affected. Do not judge
by line count alone. Multi-domain changes, removals of features, architecture,
playback, native bindings, migrations and substantial theme changes use Spec Kit.
Always plan when explicitly requested. If scope grows, stop the quick path and
prepare a coherent plan before continuing implementation.

## One planning commit

Use `$speckit-specify`, `$speckit-plan` and `$speckit-tasks`, optionally clarify or
analyze as needed. Keep spec.md, plan.md, tasks.md, any necessary research,
contracts/data-model and the initial task log in `specs/<number>-<feature>/`.
Do not commit specify, clarification, design and task generation separately.
Commit the completed planning artifacts together once. A command that ends after
specify or plan leaves the draft uncommitted until the requested plan is complete.

For a request explicitly limited to an intermediate artifact, produce that artifact
and report it; do not invent the remaining work or an extra commit requirement.
A planning-only request ends after the planning commit; it never authorizes feature
implementation. No additional confirmation ceremony is required when implementation
has already been explicitly authorized. This installation/configuration request
is a single setup change, not a new feature plan to execute retrospectively.

## Tasks and commits

Generate sequential checkbox tasks with an outcome, exact affected paths,
validation commands and dependencies. Do not use `[P]` parallel markers.

1. **T000** is always map refresh/architecture orientation, not feature edits.
   Run `python3 tools/codegraph/code_tools.py update`, inspect scope/coverage and
   relevant boundaries. Put its concise evidence and completed checkbox into the
   task log/tasks.md and make one T000 commit. The map remains ignored in `.work/`.
2. **T001** reads its requirement and T000 map, implements only that task, runs
   relevant checks, then enters review. Do not re-scan unchanged code repeatedly.
3. Before **every task after T001**, including TOR tasks and the final task,
   refresh the map and use it to select affected paths/boundaries. Record the
   result with that task; this is not a separate map-update commit.
4. For each implementation task: implement → validate → review → fix/revalidate
   if needed → review again. Use an independent read-only reviewer when available,
   following `.agents/reviewers/task-reviewer.md`. If it is unavailable, state that
   limitation and label any self-review accurately; do not claim independent PASS.
   Pause the planned task before marking it complete without the required review.
5. Count review rounds per task, not per finding. At most **three** reviewer
   results are allowed. PASS after rounds 1–3 completes the loop. If round 3 still
   needs fixes or is blocked, stop and tell the owner the remaining issues,
   validation evidence and current uncommitted state. Do not start round 4,
   reset the counter or move to the next task. No automatic approval request is
   needed between successful tasks.
6. Mark the task complete only after its checks and review pass. Commit the task's
   code, tests, log/review outcome and checkbox **together in one commit**. Do not
   make WIP, separate fix, review-only or map-only commits for that task. Do not
   amend unrelated history or use broad staging that includes unrelated changes.
   Preserve unrelated working-tree changes. A failed task is not a completed task.
7. Only after that commit proceed to the next task. No fingerprint, freshness
   certificate, work.py state machine or additional ship gate is used.

## Owner-requested extras

When the owner introduces work outside the planned tasks, add the next unique
**TOR001**, **TOR002**, etc. Describe acceptance/paths/checks in tasks.md and run it
through the same map/implementation/review/three-round/one-commit loop. Include its
new task/log text in the TOR commit; no separate planning commit is needed for the
extra. Place it before the final task. If a task is already in progress, preserve
its edits and settle its status before interleaving unrelated changes.

## Final task

The last task is always a **[FINAL] cumulative review** of all completed T/TOR work
against the plan/spec and the recorded baseline. Refresh the map, run the full
feasible checks appropriate to the change, and review the cumulative diff and
cross-language/runtime boundaries. Do not build an APK unless authorized.
Fix findings within this final task, revalidate and re-review, with the same
three-round limit. All final fixes, check/review evidence and final checkbox are
one final-task commit. If no code fixes are required, commit its completion/evidence
once. Do not silently leave actionable final findings or create an unbounded series
of additional final tasks.

Upstream `$speckit-converge` is optional inspection only in this repository.
Use its observations in the current final-task review loop; do not follow its
upstream auto-append/implement/reconverge cycle or bypass the three-round limit.

## Evidence and publishing

Log each task briefly in `task-log.md`: changed files, checks with outcomes,
review round/reviewer/result, unresolved limitations and completion. Record the
baseline commit once in the plan. Use commits/Git history for actual commit IDs;
do not put a guessed self-referential commit hash into its own task log.
Missing tools, old failures and skipped/device/ABI coverage must be explicit.
A passing compile or a missing graph edge does not prove dead code is unreachable.
Use the standalone audit and navigation skills as needed; no mandatory audit of
unrelated files is added. Push only when authorized; never automatically merge,
force-push or rewrite unrelated commits.
