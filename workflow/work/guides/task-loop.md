# Task loop (owner's simple process)

Use this for a change whose plan is written and split into tasks in `tasks.md`.
It replaces the phase gates for that change. The owner decides when planning is done.

## Before the first task

- Read `workflow/work/constitution.md`. A task that breaks a rule in it stops until the rule is met.
- One fresh read-only design review of the spec and plan, run by a read-only subagent that has not
  seen the planning conversation (for example the reviewer prompts in `workflow/.agents/reviewers/`). Record the result in `log.md`. Fix any
  problem in the spec or plan before the first task starts.

## The loop, one task at a time

1. Run `work.py map update`, so the code map matches the tree before the task starts.
   Take the first open task (`- [ ] T###`) in `tasks.md`, in order.
2. Make the change for that task only. Run the task's `check:` command, and the nearest
   test or analyzer for the code it touched.
3. Review the task in a fresh read-only context (a subagent that has not seen the work, using the reviewer prompts in `workflow/.agents/reviewers/`). In that context, check: does the diff do what the task says, with nothing extra? Record the result in `log.md` under the task ID.
4. Fix every problem the check or review finds inside this same task, before committing.
   Repeat steps 2 and 3 until the task is complete.
5. Only when the task is complete: tick it (`- [x] T###`), add the evidence after it, and make
   one commit. That commit holds the code this task changed and its doc changes (spec, plan,
   tasks, log), with the task ID in the message. Nothing else goes in it. The task's `check:`
   command must have passed before this commit.
6. Move to the next task. Repeat until no `- [ ]` task remains.

A task is never committed while it is incomplete.

## Owner asks for something new

- If the owner asks for a change that is not in the current task, add a new task to `tasks.md`
  at the end, before the Final review task. Give it the next T### number and its `check:` command.
- Run it through the same loop: change, check, review, fix inside the task, then tick it and make
  one commit with the code and docs it changed. That commit holds only this new task.
- The Final review task stays last.

## Escalation

If a review finds a problem that needs the owner's decision (a choice between two designs, a
behaviour the spec does not cover, or a rule that conflicts with the task), stop the task, write the
question in `log.md` under the task ID, and ask the owner. Do not guess.

## Final review task (always last)

- When the planned tasks are done, add one mandatory task at the end of `tasks.md`:
  `- [ ] T### Final review: review every change from the first task to HEAD (spec met, tasks
  work together, no leftovers) — check: the review is recorded in log.md with the hash of the
  commit it reviewed`. That hash is the commit just before the final review's own commit, because
  the review's commit changes HEAD.
- Run `work.py check auto` in full (all five checks), and write the Close section in `log.md`:
  Drift, Not verified, Lessons.
- Run it through the same loop as any task: review in a fresh read-only context, fix every
  problem inside this task before committing, then tick it and make one commit with the code and
  docs it changed. Its check is the recorded review.
- If a fix needs a change to an earlier task's area, make that change inside this final task.
  Do not reopen earlier commits.

## After the final review

- Build the APK (`scripts/build_android.sh`) from that final commit and audit it
  (`scripts/check_backend_apk.py`). Record the sha256 in `log.md`.
- The owner tests the APK on the device and reports problems. Each reported problem is
  a new task, handled by the same loop, and it gets its own final review task.

## Not required by this loop

- No phase advance (`work.py advance`), no review-round counter, and no fingerprint gate.
  The rest of the workflow tools still exist.

## Rules that stay

- Commit only on the branch the owner names. No force push without the owner's instruction.
- Keep secrets out of commits and logs.
- A task is not ticked until its check has actually run and passed.
