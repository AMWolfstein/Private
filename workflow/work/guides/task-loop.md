# Task loop (owner's simple process)

Use this for a change whose plan is written and split into tasks in `tasks.md`.
It replaces the phase gates for that change. The owner decides when planning is done.

## The loop, one task at a time

1. Take the first open task (`- [ ] T###`) in `tasks.md`, in order.
2. Make the change for that task only. Run the task's `check:` command, and the nearest
   test or analyzer for the code it touched.
3. Review the task in a fresh read-only context: does the diff do what the task says,
   with nothing extra? Record the result in `log.md` under the task ID.
4. Fix every problem the check or review finds inside this same task, before committing.
   Repeat steps 2 and 3 until the task is complete.
5. Only when the task is complete: tick it (`- [x] T###`), add the evidence after it, and make
   one commit. That commit holds the code this task changed and its doc changes (spec, plan,
   tasks, log), with the task ID in the message. Nothing else goes in it.
6. Move to the next task. Repeat until no `- [ ]` task remains.

A task never gets a commit while it is incomplete.

## After the last task

- Full review of the whole change: one fresh read-only review of every commit from the first task
  to HEAD (`git log` from the planning base, and `git diff <base>..HEAD`). It checks that the tasks
  together do what the spec asks, that nothing from one task breaks another, and that no leftovers or
  unplanned changes remain. Record the result and the reviewed commit hash in `log.md`.
- If the full review finds problems: fix all of them in one new commit, with the doc changes it needs.
  If the fixes are too many for one commit, add a mandatory task `Last review` to `tasks.md` and put
  the fixes in its own commit. After any fix, re-check the affected tasks' `check:` commands.
- Build the APK (`scripts/build_android.sh`) from the final commit and audit it
  (`scripts/check_backend_apk.py`). Record the sha256 in `log.md`.
- The owner tests the APK on the device and reports problems. Each reported problem is
  a new task, handled by the same loop.

## Not required by this loop

- No phase advance (`work.py advance`), no design or code review rounds, no map gate.
  `work.py check auto` and `work.py lint` still run when you want them, but they do not block a task.
- The Close section in `log.md` is optional. Write it only when the owner asks for a summary.

## Rules that stay

- Commit only on the branch the owner names. No force push without the owner's instruction.
- Keep secrets out of commits and logs.
- A task is not ticked until its check has actually run and passed.
