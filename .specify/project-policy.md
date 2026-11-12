# Local Spec Kit policy

GitHub Spec Kit provides specify → clarify (when needed) → plan → tasks →
implement. This document supplies the owner's local execution and Git rules;
these rules are not upstream Spec Kit defaults. Current owner instructions win.
Read the constitution and the applicable official `speckit-*` skill. Skill names refer to the files in
`.agents/skills/<name>/SKILL.md`; any agent can read and follow them directly.
Host-specific slash/dollar commands are optional aliases, never prerequisites.

Ponytail full mode applies before every modification on both the planned and direct
paths, including planning documents and small config/text edits. Read
`.agents/skills/ponytail/SKILL.md`; incorporate
`.agents/skills/ponytail-review/SKILL.md` into the same existing review round.
It does not replace map-first planning/task starts, required checks or the bounded
one-commit task loop, and creates no extra task, review round or commit.

## When to plan

Small, isolated, low-risk edits may use direct implementation, targeted checks and
one commit. Documentation, translations, comments and a local header/button edit
usually qualify when no stored-data/API/runtime boundary is affected. Do not judge
by line count alone. Multi-domain changes, removals of features, architecture,
playback, native bindings, migrations and substantial theme changes use Spec Kit.
Always plan when explicitly requested. If scope grows, stop the quick path and
prepare a coherent plan before continuing implementation.

## Map-first planning

At the start of a planning session, after reading the owner's request and these
instructions but **before repository investigation or drafting the technical
plan/tasks**, run `python3 tools/codegraph/code_tools.py update`. Inspect the
recorded input scope, exclusions and source/resource/native coverage. Do not use a
limited `update --paths` snapshot as evidence of complete project coverage.

Use `query --file PATH` and `query --symbol NAME` to identify relevant existing
components, dependencies, callers, resources and native/runtime boundary candidates.
Then read the referenced source, registrations/build configurations and tests before
choosing architecture, exact affected paths or validation commands. The map guides
investigation; it does not replace requirements, source reading or runtime evidence.
Do not generate a generic plan while ignoring the current repository evidence.

Reuse the same map through specify/clarify/plan/tasks/analyze in that session while
the source is unchanged. Do not refresh just because another planning skill was
invoked or a read was performed. Refresh after source changes or when starting a
new planning session. No fingerprint/freshness gate is introduced.

Record a concise **Repository evidence** section in plan.md: baseline commit, map
update outcome, actual scope/coverage/exclusions, relevant queries/files/boundaries
read, and unresolved limitations. Include the implications for task paths and checks.
Keep graph/cache files ignored; the evidence is part of the single planning commit,
not a separate map task, task number, map-only commit or approval step.

If update fails or coverage is incomplete, state the failure/gaps and trace the
relevant source/build/runtime paths manually where possible. Base the plan only on
verified facts; mark unresolved assumptions/open questions and their validation
needs explicitly. Never silently rely on an old map or treat missing edges as proof
of dead code. Planning can continue on independently verified areas; it must not
claim unseen areas are understood. This planning fallback does not change the
existing task-start rule: each implementation/TOR/final task still refreshes first
and reports a failed task-start refresh before proceeding with that task.

## One planning commit

Use `speckit-specify`, `speckit-plan` and `speckit-tasks`, optionally clarify or
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

1. Number implementation tasks from **T001**. There is no dedicated map task.
   At the start of **every task**, including T001, TOR### and [FINAL], the first
   action is `python3 tools/codegraph/code_tools.py update`, before task analysis,
   implementation edits, validation or review.
2. Inspect refresh scope/coverage and the relevant entry points, affected files
   and native/runtime boundaries. Use the refreshed map to guide that task.
   If refresh fails, stop the task and report the limitation; never silently
   substitute a stale map or claim complete coverage.
3. Record concise refresh evidence with the task in `task-log.md`. Keep map/cache
   outputs ignored under `.work/`. The refresh belongs to the task's single
   commit; it creates neither a separate task nor a map-only commit. Reuse the
   map while inspecting unchanged files within that task; refresh again if source
   edits make later map-based conclusions stale.
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

Upstream `speckit-converge` is optional inspection only in this repository.
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
