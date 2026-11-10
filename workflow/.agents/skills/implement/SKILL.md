---
name: implement
description: "Turns an accepted plan into tasks.md and implements it one verified task at a time: tests before the code they pin, the smallest complete change per task, bounded fix attempts, and evidence logged for every finished task."
---

# Implement

Planning is unchanged. Commit the complete accepted planning bundle once before execution.
Small requests use `new "title" --size small`: minimal task records, no spec/plan stage.
Classify by behavior, contracts/data impact and independent work units, not line/file counts.

## One task loop

1. `task start CHANGE T###` verifies the previous task's actual commit, refreshes
   map/context and captures a clean task baseline. There is no separate map task. Read the emitted
   context and relevant source; map inference/coverage limitations remain explicit.
2. Execute the task as one complete behavior. Preserve unrelated work. Tests should establish
   behavior and failure handling; cosmetic reversible edits do not need artificial tests.
3. `task check CHANGE T###` runs the configured relevant checks. Check identity includes
   code and requirements; changed source/requirements needs fresh evidence. Manual observations
   and device results must be identified honestly. NO_CHANGES is never a test PASS.
4. A passing `task check` also writes the review packet for the exact current code (its
   path is in the result). Use the review skill for an independent reviewer. Record its result with `task review CHANGE T### --result
   clean|dirty --reviewer NAME --note "findings/evidence"`.
5. Dirty: record findings, correct them, rerun affected checks and review again inside this
   same task. Maximum THREE reviews per cycle. Third dirty: stop, report remaining findings
   and attempts, and do not commit or start the next task. Never invoke `task resume` on your
   own; only an explicit new owner instruction authorizes another preserved cycle.
6. Clean: recording the clean review prepares completion records and returns READY_TO_COMMIT.
   Do not edit records after that; if you must, run `task complete` again before committing.
   Stage explicit task paths plus this change's records and make ONE ordinary Git commit
   containing implementation, tests, all review fixes and records. The tool never stages or
   creates commits. The next `task start` verifies the committed source/artifacts before the
   task may begin. A failed/interrupted commit remains waiting_commit; preserve edits.

## Owner requests and final review

An extra owner request outside the queue becomes `task add CHANGE --request "owner request"`.
It receives TOR### and the same loop, queued before pending planned work/final review. Never
silently expand another task or rewrite completed tasks.

The last task has [FINAL]. It checks/reviews the cumulative change from the original base,
all task outcomes and declared assurance/device requirements. Fix all final findings inside
that task, review until clean (same three-round stop), then one final task commit.
No separate project-wide build/review/ship transitions or post-commit records commit.

## Compatibility and ports

Legacy records keep their legacy protocol; new records use schema 2. Source/target bridge
checks and provenance/parity requirements remain in guides/port.md and guides/assurance.md.
Do not delete working implementations without verified replacements. Push/APK only on request.
