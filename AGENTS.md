# Sistrum engineering workflow

This repository carries its own workflow, in `workflow/`. Start every request by reading
`workflow/.agents/skills/work/SKILL.md`, which chooses the path.

Authority, highest first: the owner's current instructions; `workflow/work/constitution.md`; the change
records in `workflow/work/changes/`; the existing code.

The tool is `python3 workflow/scripts/work/work.py` with six commands: `setup`, `doctor`, `check`, `map`,
`context` and `hook-bash`. On first use run `doctor`; if tools are missing, run `setup`. Do not claim setup
success when `doctor` reports a blocker.

Planned changes follow `workflow/work/guides/task-loop.md`: one task at a time, a check and a review for each,
one commit per completed task, a final review task last, then the APK. Run `map update` before each task so the
code map matches the tree.

Reviewers are read-only prompts in `workflow/.agents/reviewers/`. Run them in a fresh read-only context; if you
cannot, say so and label the review as self-review.
