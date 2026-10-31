# Sistrum workflow

A repo-local engineering workflow for Claude Code (and, with less enforcement, OpenCode). Nothing to install: the
skills and reviewer agents are Markdown, the tool is one Python 3.10+ standard-library script, and the checks are
the repository's own commands.

The owner talks normally. The `work` skill decides whether a request is a question, a discussion, a small fix, a
feature, an architecture change, a review or a release, and follows the matching path.

## What comes from where

| Idea | Source | Where it lives here |
|---|---|---|
| Constitution checked by every plan; spec (what and why) before plan (how) before tasks; at most 3 clarification markers; one question at a time; requirement-quality check; cross-artifact consistency; "a ticked task is not evidence" | github/spec-kit | `work/constitution.md`, `work/templates/`, `spec`, `plan`, `review` skills, `work.py lint` and `advance` |
| The author holds context and writes a self-contained document; fresh reviewers with no history paraphrase it first; findings are fixed, contested with checkable evidence, escalated or declined; two consecutive clean rounds; drift between design and code | google/elephant-goldfish-model | `plan` and `review` skills, `goldfish-reader`, `design-critic`, `code-reviewer`, `work.py packet` and `round`, the Close section |
| Plans with a check per step, bounded attempts, "same failure twice: question the assumption", evidence in the same message as the claim, append-only log, repeated mistakes become enforced checks | aicodeking/deepseek-stack | `implement`, `fix` and `ship` skills, `log.md`, `work/LESSONS.md` |
| Read callers before editing; the reuse ladder; economical solution, complete change; the never-cut list; `shortcut:` comments; review sweep order with a concrete case per finding | DietrichGebert/ponytail | `fix` and `implement` skills, constitution article III, `code-reviewer` |
| Mechanical evidence kept apart from judgment review; blind review packets without targets; finding statuses with evidence; a finding that disappears is not fixed | peteromallet/desloppify | `work.py check` and `packet`, `findings.md` statuses, `work.py lint` |

Left out on purpose: scores (they can be gamed and do not measure correctness), installed CLIs, swarms of
reviewers, and records for small fixes.

## Paths

| Request | What happens |
|---|---|
| Question | Answer from the code with file:line |
| Discussion or plan | `work.py new`, spec with the owner, then plan; no code until the owner says build |
| Small fix | Cause → regression test → change → `work.py prove` → `work.py check auto` → commit → report |
| Feature | spec → plan → tasks → implement → one fresh code review → ship |
| Architecture, migration batch, contracts, data formats | as feature, plus fresh design review until two consecutive clean rounds |
| Review or audit | read-only findings |

## Tool

```sh
python3 scripts/work/work.py status            # active changes, freshness of the last checks
python3 scripts/work/work.py scope             # domains, high-risk paths and checks for the current diff
python3 scripts/work/work.py check auto        # run the checks for the changed paths, store evidence
python3 scripts/work/work.py fresh             # does the last passing evidence match the tree?
python3 scripts/work/work.py prove -- <cmd>    # the test must fail with every non-test change reverted
python3 scripts/work/work.py new "<title>" --size feature|architecture
python3 scripts/work/work.py lint [NNN]        # spec/plan/tasks/findings consistency
python3 scripts/work/work.py packet --change NNN --out .work/review/NNN-code-r1.md
python3 scripts/work/work.py round NNN design|code clean|dirty --reviewer NAME
python3 scripts/work/work.py advance NNN <phase>
```

Evidence is identified by git's tree id of all non-ignored files except `work/` and `.work/`, so generated output
never makes it stale and committing does not either. `check` runs the configured commands one at a time, splits
`flutter test` by top-level test folder, and reports a chunk that stops printing as STALLED after one retry.

## Install in a repository

1. Copy the contents of this folder to the repository root: `AGENTS.md`, `CLAUDE.md`, `.claude/skills/`,
   `.claude/agents/`, `work/`, `scripts/work/`. Merge with existing files of the same name instead of overwriting
   them.
2. Add `.work/` to `.gitignore`.
3. Product decisions start empty: each accepted spec in `work/changes/` records the decisions it makes.
4. Check `work/checks.json` against the repository's commands.
5. Run `python3 -m unittest discover -s scripts/work -p 'test_*.py'` and `python3 scripts/work/work.py status`.
6. Optional, recommended: the Claude Code hooks below.

### Claude Code hooks (add yourself)

Create `.claude/settings.json` (or merge into it) so the tool runs automatically: the session starts with the
status, each message carries a one-line reminder, and shell commands pass the guard (no `git add -A`, force push,
`--no-verify`, `reset --hard`, `clean -f`, `pkill -f`). Without it, the skills still work, but nothing enforces
the guard and the status is not shown automatically.

```json
{
  "hooks": {
    "SessionStart": [{"hooks": [{"type": "command",
      "command": "python3 \"$CLAUDE_PROJECT_DIR/scripts/work/work.py\" status --brief"}]}],
    "UserPromptSubmit": [{"hooks": [{"type": "command",
      "command": "python3 \"$CLAUDE_PROJECT_DIR/scripts/work/work.py\" remind"}]}],
    "PreToolUse": [{"matcher": "Bash", "hooks": [{"type": "command",
      "command": "python3 \"$CLAUDE_PROJECT_DIR/scripts/work/work.py\" hook-bash"}]}]
  }
}
```

## Limits

- The tool checks structure and evidence; it cannot tell whether a review was honest or a test is meaningful.
  The fresh-context reviewers and the owner do that.
- Host checks never prove device behaviour. Device checks stay pending until the owner runs them.
- OpenCode has no hooks here and its reviewers are not restricted by these agent files; label its reviews as
  self-review unless it runs a fresh read-only reviewer.
