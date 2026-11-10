---
name: work
description: Entry point for work in this repository. Read first for any request about the code, a plan, a bug or a build.
---

# Work in this repository

Read `AGENTS.md`, then `workflow/work/constitution.md`.

## Choose the path

| Request | What to do |
|---|---|
| Question or explanation about the code | Answer from the code with `file:line`. No edits. |
| Plan for a change | Write `spec.md`, `plan.md` and `tasks.md` in `workflow/work/changes/<id>/`, then stop and wait for the owner. |
| Planned change with tasks in `tasks.md` | Follow `workflow/work/guides/task-loop.md`. One task at a time, one commit per completed task, a final review task last, then the APK. |
| Small fix: one behaviour, a few files | Write the test, make the fix, run the nearest check, commit with a clear message. |
| Commit, push, APK | Only when the owner asks. |

## Tools

`python3 workflow/scripts/work/work.py` has six commands:
- `setup` and `doctor`: install and check the local tools.
- `check <names>`: run checks from `workflow/work/checks.json`. `check auto` picks the ones for changed paths; pass `--base` to compare against a commit.
- `map build|update|status|coverage`: the code map.
- `context "<task>"`: a bounded context packet from the code map.
- `hook-bash`: the guard for dangerous shell commands.

## Throughout

- Keep secrets out of commits and logs.
- Commit only on the branch the owner names. No force push without the owner's instruction.
- Do not claim a check passed unless its command ran and passed.
