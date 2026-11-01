# Sistrum engineering workflow

This repository carries its own workflow. It needs Git and Python 3.10+; the code map uses pinned
CodeGraph 1.6.2 (see workflow/work/guides/map.md for project-local installation). Without it, structural coverage
is explicitly unavailable; fallback navigation never fabricates call relationships. Structured resources and
parse-only Bash use workflow/scripts/work/requirements.txt; missing parsers remain explicit coverage gaps.
Keep this AGENTS.md at the repository root and the workflow/ directory beside it. All paths below are relative to the repository root.

For every request about this repository (a bug report or screenshot, a feature, a plan or discussion, a review,
a question about the code, a commit, push or build), read `workflow/.agents/skills/work/SKILL.md` and follow it. It
chooses the path; the owner never needs to name a skill or a command.

Authority, highest first: the owner's current instructions; `workflow/work/constitution.md`; accepted change records in
`workflow/work/changes/`; `docs/AUDIO_ENGINE_MIGRATION.md` when present; the existing code.

The tool is `python3 workflow/scripts/work/work.py` (status, context, map, scope, check, prove, packet, round, lint,
new, advance). Run `work.py status` when you start and `work.py check auto` before claiming completion.

Before reading code broadly, run `work.py context "<task>"` (with `--file`/`--symbol` once known) and open only the
files and guides the packet names. It refreshes the code map when stale and labels every fact as extracted,
declared or inferred; a FALLBACK section is text search, not graph evidence. After each batch of edits run
`work.py map update`; review and ship gates require a map that matches the final code. See
`workflow/work/guides/map.md`. Skills live in
`workflow/.agents/skills/`; read the selected SKILL.md and follow its linked guidance explicitly if your agent does not
automatically discover that directory. This entry file is the portable bootstrap; an agent that does not load
AGENTS.md automatically must be pointed to it once.

Reviewer prompts live in `workflow/.agents/reviewers/`. Load them into fresh read-only contexts using your agent's
capabilities. If it cannot start a fresh read-only reviewer, label the review as self-review and leave the
independent-review gate open. Markdown prompts do not themselves restrict tools or create independent contexts.

Optional hook integration is agent-specific (see workflow/README.md); the workflow requires no provider configuration.
Do not run commands rejected by `work.py hook-bash`. Hooks only enforce this if explicitly integrated.
