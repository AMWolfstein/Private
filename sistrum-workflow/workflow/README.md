# Sistrum workflow

A repo-local engineering workflow for coding agents. Nothing to install: the
skills and reviewer agents are Markdown, the tool is one Python 3.10+ standard-library script, and the checks are
the repository's own commands.

The owner talks normally. The `work` skill decides whether a request is a question, a discussion, a small fix, a
feature, an architecture change, a review or a release, and follows the matching path.

## What comes from where

| Idea | Source | Where it lives here |
|---|---|---|
| Constitution checked by every plan; spec (what and why) before plan (how) before tasks; at most 3 clarification markers; one question at a time; requirement-quality check; cross-artifact consistency; "a ticked task is not evidence" | github/spec-kit | `workflow/work/constitution.md`, `workflow/work/templates/`, `spec`, `plan`, `review` skills, `work.py lint` and `advance` |
| The author holds context and writes a self-contained document; fresh reviewers with no history paraphrase it first; findings are fixed, contested with checkable evidence, escalated or declined; two consecutive clean rounds; drift between design and code | google/elephant-goldfish-model | `plan` and `review` skills, `goldfish-reader`, `design-critic`, `code-reviewer`, `work.py packet` and `round`, the Close section |
| Plans with a check per step, bounded attempts, "same failure twice: question the assumption", evidence in the same message as the claim, append-only log, repeated mistakes become enforced checks | aicodeking/deepseek-stack | `implement`, `fix` and `ship` skills, `log.md`, `workflow/work/LESSONS.md` |
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
python3 workflow/scripts/work/work.py status            # active changes, freshness of the last checks
python3 workflow/scripts/work/work.py scope             # domains, high-risk paths and checks for the current diff
python3 workflow/scripts/work/work.py check auto        # run the checks for the changed paths, store evidence
python3 workflow/scripts/work/work.py fresh             # does the last passing evidence match the tree?
python3 workflow/scripts/work/work.py prove --expect-failure "<assertion diagnostic>" -- <cmd>
python3 workflow/scripts/work/work.py new "<title>" --size feature|architecture
python3 workflow/scripts/work/work.py lint [NNN]        # spec/plan/tasks/findings consistency
python3 workflow/scripts/work/work.py packet --change NNN --out .work/review/NNN-code-r1.md
python3 workflow/scripts/work/work.py round NNN design|code clean|dirty --reviewer NAME
python3 workflow/scripts/work/work.py advance NNN <phase>
```

Evidence is identified by git's tree id of all non-ignored files except `workflow/work/changes/` and `.work/`.
Check configuration, constitution, templates and lessons are included: changing them invalidates previous
evidence. Progress records and ignored generated output do not invalidate it; committing does not either.
Missing or invalid check configuration blocks review gates. `check` runs the configured commands one at a time, splits
`flutter test` by top-level test folder, and reports a chunk that stops printing as STALLED after one retry.

`prove` requires the same command to pass with the fix, fail with the configured non-test code changes
reverted to HEAD, and pass again after restoring the fix. The failing run must contain the literal
`--expect-failure` assertion diagnostic, absent from both passing runs. Missing diagnostics, timeouts or a
failing baseline/restored run are INCONCLUSIVE. A test that passes without the fix is FAIL. Phase logs and
`report.json` remain under `.work/proofs/`. Inspect the failure cause: matching text alone cannot prove
semantic correctness. Use a specific assertion message, not a test name or compiler error.

`prove` snapshots non-ignored inputs into a disposable detached Git worktree. The owner's files and index
are never reverted. Logs are copied to the original `.work/proofs/`; source edits during proof invalidate the
result. Ignored dependencies and caches are not copied: provision dependencies in the isolated checkout through
the test command if needed. Missing dependencies are INCONCLUSIVE, never proof. Use repository-relative test
paths; absolute paths may escape isolation. Forced termination may leave a worktree for manual cleanup.

Project-specific guidance lives in `workflow/work/guides/`: architecture, review lenses, port dispositions, migration
batches and playback/data contracts. Keep it when installing in a new repository. Historical reference revisions
must be verified at import time; accepted owner changes supersede the historical summary.

## Executable port and bridge gates

`new` also creates `assurance.json`. Explicit applicability, pinned reference revisions, per-component
reuse/adapt/restructure/exclude decisions, both bridge endpoints and contract fields, check IDs and completed
prerequisites are required before build. Review requires fresh passing runner evidence for the named checks;
ship blocks pending device cases. See [assurance declaration](workflow/work/guides/assurance.md) for the schema and example.
Existing active changes must add this declaration. Review packets and review fingerprints include it.
Skills remain responsible for analysis, sensible tests and semantic review; Python enforces declarations and
evidence, not the truth of arbitrary prose. No redundant parallel skill system is introduced.

## Copy into a new repository

Copy the contents of the outer `sistrum-workflow/` package into the new repository root, preserving this layout:

```text
new-repository/
├── AGENTS.md
├── .gitignore
└── workflow/
    ├── README.md
    ├── .agents/
    │   ├── skills/
    │   └── reviewers/
    ├── scripts/work/
    │   ├── work.py
    │   └── test_work.py
    └── work/
        ├── checks.json
        ├── constitution.md
        ├── LESSONS.md
        ├── guides/
        └── templates/
```

Keep AGENTS.md at the root: it directs the agent into workflow/. Merge existing AGENTS.md and .gitignore
rather than overwriting project content. Copy hidden directories too. No dependency on the old repository remains.

Requirements: Git and Python 3.10+, an initialized checkout with at least one commit. From the repository root:

```sh
python3 -m unittest discover -s workflow/scripts/work -p 'test_*.py'
python3 workflow/scripts/work/work.py status
```

Make the agent read root AGENTS.md if it does not discover it automatically. All commands run from the repository
root, not inside workflow/. Runtime logs remain in root `.work/`, ignored by the supplied .gitignore.

Product checks require actual Flutter/Android/Rust toolchains for changed domains. Android uses the project's
Gradle wrapper and testDebugUnitTest; Rust uses Cargo directly, without old-repository helper scripts. No Rust
installation is needed for Flutter/Kotlin-only changes. Adjust commands for actual flavors/modules when created.
Missing project files/tools block the relevant check; they do not count as successful validation.

### Optional agent integrations

The shared source is `AGENTS.md`, `workflow/.agents/skills/` and `workflow/.agents/reviewers/`. There is no required
provider-specific directory, import syntax or tool allowlist. Configure your agent to read AGENTS.md if it
uses another entry convention. Do not duplicate the skills into provider-specific copies.

If your agent supports hooks, wire session start to `python3 workflow/scripts/work/work.py status --brief`, new requests
to `python3 workflow/scripts/work/work.py remind`, and shell preflight to `python3 workflow/scripts/work/work.py hook-bash`.
The shell guard accepts JSON on stdin: `{"tool_input": {"command": "git status"}}`; exit 2 blocks, exit 0 allows.
Adapt your agent's event payload and working directory to this interface. Hook names, installation and blocking
behavior depend on the host agent. Without integration these are explicit commands and instructions, not
automatic enforcement of every shell invocation.

Reviewer prompts are ordinary Markdown. Configure read-only tools in the host agent and provide the packet
in a fresh context. If those capabilities are unavailable, report self-review; do not count it as independent.

## Limits

- The tool checks structure and evidence; it cannot tell whether a review was honest or a test is meaningful.
  The fresh-context reviewers and the owner do that.
- Host checks never prove device behaviour. Device checks stay pending until the owner runs them.
- Discovery, hooks and read-only reviewer isolation depend on the host agent. Instructions alone do not
  guarantee enforcement; missing independent-review capability must be reported.
