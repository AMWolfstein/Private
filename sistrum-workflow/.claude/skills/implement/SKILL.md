---
name: implement
description: "Turns an accepted plan into tasks.md and implements it one verified task at a time: tests before the code they pin, the smallest complete change per task, bounded fix attempts, and evidence logged for every finished task."
---

# Implement

## Tasks

1. Fill `tasks.md`: phases (foundation, then one per story, by priority), each line
   `- [ ] T001 [P] [US1] what, in which file (FR-00n) — check: <command or observable result>`.
2. Tests that pin behaviour come before the code that changes it. Every FR appears in at least one task.
3. `[P]` only for tasks on different files with no dependency. Checks still run one at a time: Flutter tests and
   Gradle builds never overlap.
4. `python3 scripts/work/work.py advance <NNN> build` refuses tasks without a check, unfilled markers, or a
   requirement with no task.

## Each task

1. Run the task's check before editing, to see the starting state.
2. Choose the change: not needed; already in the codebase; Flutter, Android or Media3 provides it; an installed
   dependency; the least new code. Complete it: callers, tests, fixtures, all arb files, settings, backup keys.
3. Rerun the exact check and read the whole output. Root cause in one sentence for every failure.
4. At most 5 attempts per task. The same failure after two different fixes: write down the assumption they
   shared, test it, and change approach. Still stuck: stop and tell the owner what you tried and what you need.
5. Never weaken, skip or delete a test, assertion or lint to pass. Never mock away the thing under test.
6. Mark `[x]` only after the check passed, and append one line to `log.md`: date, task, command, result.

## Boundaries

- A Dart ↔ Kotlin channel change is tested on both sides with the same cases; a mocked channel test does not
  prove the Kotlin side.
- Kotlin, C++ or Rust changes run their checks (`work.py check auto` selects them by path).
- Behaviour that must survive the app closing is tested on the Android side, and listed for device checks.
- Shortcuts carry `shortcut: <limit>, <when to upgrade>` and are listed in the report.

## Finish

`python3 scripts/work/work.py check auto`, then `python3 scripts/work/work.py advance <NNN> review`, which
requires every task done and passing evidence that matches the current tree.

## Ports

Follow `work/guides/port.md`. Record a disposition per component: reuse, adapt, restructure or exclude, with evidence. Reorganize only for responsibility and dependency boundaries; a tested module may remain intact. Preserve source device-test evidence separately from new integration validation.
