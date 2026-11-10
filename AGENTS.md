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

The tool is `python3 workflow/scripts/work/work.py`. Read status at the start. Planning is unchanged,
with one planning commit. New execution follows the implement skill: T000 map, then map/context →
implementation/checks → independent review/fixes → one task commit. Three reviews maximum; stop after
a third dirty result. Owner extras become TOR###. The last task reviews the cumulative change.
Fingerprints/check freshness are internal; no manual fresh or project-wide build/review/ship steps.

On first use in a Linux cloud/Fedora checkout, run `python3 workflow/scripts/work/work.py doctor`. If tools are
missing, run `python3 workflow/scripts/work/work.py setup`; project-local dependency provisioning is part of the
workflow. No sudo/system-package changes or provider configuration edits. Node/npm must already be available
for initial CodeGraph provisioning. Setup writes only ignored `.work/`, and ordinary CLI commands then discover
the managed environment automatically. Do not claim setup success when doctor is BLOCKED.

Before reading code broadly, run `work.py context "<task>"` (with `--file`/`--symbol` once known) and open only the
files and guides the packet names. It refreshes the code map when stale and labels every fact as extracted,
declared or inferred; a FALLBACK section is text search, not graph evidence. Task start refreshes the map before context; task packets refresh it for review when needed. Do not rebuild it after every individual file edit. See
`workflow/work/guides/map.md`. Skills live in
`workflow/.agents/skills/`; read the selected SKILL.md and follow its linked guidance explicitly if your agent does not
automatically discover that directory. This entry file is the portable bootstrap; an agent that does not load
AGENTS.md automatically must be pointed to it once.

Reviewer prompts live in `workflow/.agents/reviewers/`. Load them into fresh read-only contexts using your agent's
capabilities. If it cannot start a fresh read-only reviewer, label the review as self-review and leave the
independent-review gate open. Markdown prompts do not themselves restrict tools or create independent contexts.

Optional hook integration is agent-specific (see workflow/README.md); the workflow requires no provider configuration.
Do not run commands rejected by `work.py hook-bash`. Hooks only enforce this if explicitly integrated.
