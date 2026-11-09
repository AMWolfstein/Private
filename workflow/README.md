# Repository workflow

The owner requests work normally. The agent follows the work skill; the commands below are
internal tools, not a checklist the owner must drive. Application behavior and technical
contracts remain in the constitution, accepted plans and guides.

## Planning

Small bounded changes skip planning (`new "title" --size small`). Decide by behavioral impact,
contracts/data formats and architectural decisions, not file or line counts. Escalate if scope
grows. Larger changes keep spec/plan/design review. Commit the complete accepted planning
bundle ONE time before execution. `planning-commit` prepares records; it does not run Git commit.

## Execution

1. `task start` refreshes the map and emits the task's context. There is no separate map task.
2. Implement one complete task, then run appropriate checks and independent review.
3. Dirty review: fix and recheck/review inside the same task. At most THREE reviews per cycle.
   Third dirty: stop/report. Only a new explicit owner instruction permits a recorded resume.
4. Clean review: recording it prepares the completion records. Make ONE ordinary Git commit
   containing implementation, tests, review fixes and task records. The next `task start`
   verifies the committed contents.
5. Extra owner requests become TOR001, TOR002, etc. They use the same loop.
6. Last pending task has [FINAL]: check/review the cumulative result and completed tasks. Its
   fixes/records get one reviewed commit. Never make an empty Git commit.

No separate execution build/review/ship progression and no code-then-records commits.

## Agent commands

```sh
python3 workflow/scripts/work/work.py status
python3 workflow/scripts/work/work.py new "Title" --size feature
# Existing spec/plan/design-review procedure, unchanged:
python3 workflow/scripts/work/work.py advance NNN plan
python3 workflow/scripts/work/work.py advance NNN tasks
python3 workflow/scripts/work/work.py planning-commit NNN
# Stage the complete planning folder explicitly; make its one Git commit.

python3 workflow/scripts/work/work.py task start NNN T001    # verifies the previous commit, map, context
python3 workflow/scripts/work/work.py task check NNN T001    # checks; on PASS also writes the review packet
# Independent reviewer reads packet/source; record its actual verdict:
python3 workflow/scripts/work/work.py task review NNN T001 --result clean --reviewer NAME
# A clean verdict prepares the records (READY_TO_COMMIT).
# Stage explicit task paths plus this change's records; one ordinary Git commit.
# Repeat for the next task, TOR### and the last [FINAL] task.
```

Four steps per task. `task packet`, `task complete` and `task status` still exist for
recovery: a packet after an interrupted check, re-preparing records edited after the clean
review (run `task complete` again BEFORE committing), and inspecting the queue. Untracked
files that existed before a task are remembered under ignored `.work/`, never in the
committed records, so another clone can verify the same commits.

`READY_TO_COMMIT` is not completion. Failed/interrupted Git leaves `waiting_commit`; source/index
edits are preserved. Partial planning/task commits, omitted evidence, changed reviewed code and
unrelated staged records are rejected. No automatic staging, commit, rollback, push or APK.

## Checks and reports

```sh
python3 workflow/scripts/work/work.py check
python3 workflow/scripts/work/work.py check --full
python3 workflow/scripts/work/work.py check auto --base COMMIT
```

Default check selects affected configured domains, using the active task baseline. Final task
checks use the original change base. Explicit `--full` runs all configured checks. No selected
checks returns NO_CHANGES, never a fabricated PASS or overwritten evidence. Map-only/zero-check
tasks record NOT_REQUIRED while independent review remains required.

Runner timeouts, logs and real test counts remain. Evidence is tied automatically to code and
task requirements. `reports/`, `.work/` and `workflow/work/changes/` are progress/output folders
excluded from code fingerprints; policy and check configuration still count. Plan/task changes
can invalidate task review even without a source change. Do not put runtime inputs under reports/.

## Map, setup and limits

Task start uses the current CodeGraph map and emits context. A task packet refreshes stale
map state before review. See [map guide](work/guides/map.md) for pinned installation, provenance,
coverage and unresolved links. A map is not runtime proof; excluded/unindexed source requires
explicit direct inspection and compiler/test evidence.

On a new Linux checkout, use `work.py doctor`, then `work.py setup` only for missing project-local
tools. No sudo/system package changes. `--offline` validates/reuses existing setup. Graph/parser
integration checks remain in the workflow suite; skipped/unavailable verification is reported.

## Optional command guard

`work.py hook-bash` reads a tool call as JSON on stdin (`{"tool_input": {"command": "..."}}`)
and exits 2 with a reason for commands the workflow forbids: `git add -A` / `git add .`,
force push, `--no-verify`, tree-discarding resets and `pkill -f`. It does nothing unless your
agent is configured to call it before shell commands; for Claude Code that is a `PreToolUse`
hook on `Bash` in `.claude/settings.json`. Nothing in this repository wires it.

The tool cannot prove reviewer independence or semantic correctness. Read-only reviewers inspect
the actual source. Ports/bridges retain parity, provenance and both-side checks in assurance.json;
required device cases remain honest prerequisites, not claims from host mocks.
