# Workflow

A small engineering workflow for coding agents in this repository.

- **Process:** `work/guides/task-loop.md`. A planned change is split into tasks in `tasks.md`. Each
  task is changed, checked and reviewed, then committed on its own. A final review task comes last,
  then the APK.
- **Entry point for agents:** `.agents/skills/work/SKILL.md`, and `AGENTS.md` at the repository root.
- **Constitution:** `work/constitution.md`.
- **Reviewers (read-only prompts):** `.agents/reviewers/`.
- **Tool:** `scripts/work/work.py`, six commands:

| Command | Purpose |
|---|---|
| `setup`, `doctor` | install and check the local tools (Linux) |
| `check <names>` | run the checks in `work/checks.json`; `check auto --base <commit>` picks the ones for the changed paths |
| `map build\|update\|status\|coverage` | the code map, built from CodeGraph (or the fallback scan) |
| `context "<task>"` | a bounded context packet from the code map |
| `hook-bash` | a guard that blocks dangerous shell commands |

Checks, the map and the guard run from the repository root. The map lives in `.work/`, which Git ignores.
Test the workflow with `python3 workflow/scripts/work/run_tests.py`.
