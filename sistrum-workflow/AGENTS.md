# Sistrum engineering workflow

This repository carries its own workflow; nothing needs installing.

For every request about this repository (a bug report or screenshot, a feature, a plan or discussion, a review,
a question about the code, a commit, push or build), read `.claude/skills/work/SKILL.md` and follow it. It
chooses the path; the owner never needs to name a skill or a command.

Authority, highest first: the owner's current instructions; `work/constitution.md`; `docs/PRODUCT_DECISIONS.md`
and `docs/AUDIO_ENGINE_MIGRATION.md`; accepted change records in `work/changes/`; the existing code.

The tool is `python3 scripts/work/work.py` (status, scope, check, prove, packet, round, lint, new, advance).
When the Claude Code hooks are installed (see README), it runs on session start, on each message and before
shell commands. Otherwise, and in other agents such as OpenCode, run `work.py status` when you start and
`work.py check auto` before claiming completion, and do not run the commands its guard rejects
(`work.py hook-bash`). Reviewer prompts live in `.claude/agents/`; if your agent cannot start a fresh read-only
reviewer with one of them, label the review as self-review and leave the independent-review gate open.
