# Sistrum workflow

A repo-local engineering workflow for coding agents. The skills and reviewer agents are Markdown, the tool is
a standard-library Python 3.10+ core plus pinned parse-only Bash dependencies, and the checks are the repository's own commands. The code map can use the pinned
CodeGraph 1.6.2 (local CLI); without it the map keeps imports, channels, tests and
declarations and says that structure is unavailable.

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
| Small, current, scoped context from a code graph instead of whole files or reports | colbymchenry/codegraph (AST and resolver adapter) | `work.py map` and `context`, `workflow/work/map.json`, `workflow/work/architecture.json`, [map guide](work/guides/map.md) |

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
python3 workflow/scripts/work/work.py status            # active changes, freshness of the last checks and of the map
python3 workflow/scripts/work/work.py context "<task>" [--file P] [--symbol S] [--budget N] [--expand HANDLE]
python3 workflow/scripts/work/work.py map status|update|build   # code map freshness, incremental update, full rebuild
python3 workflow/scripts/work/work.py scope             # domains, high-risk paths and checks for the current diff
python3 workflow/scripts/work/work.py check auto        # run the checks for the changed paths, store evidence
python3 workflow/scripts/work/work.py fresh             # do the last passing checks and the code map match the tree?
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

## Code map and context

`work.py context` answers "what do I need to read for this task?" with a bounded packet: entry points, both sides
of affected Dart ↔ Kotlin channels, declared ownership, contracts and port records, linked tests and checks,
short excerpts, truncation and expansion commands, and what is uncertain. Every fact is labelled extracted,
declared or inferred. The map refreshes itself before `context` and `packet`, after `check`, and before review,
ship and done gates; a clean code round records the map it was reviewed against. Edits made outside the workflow
are detected at the next workflow command. Details, schemas, freshness rules and limits:
[map guide](work/guides/map.md).

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
    │   ├── work.py              # CLI, gates, evidence
    │   ├── workmap.py           # code map and context
    │   ├── worklib.py           # shared helpers
    │   ├── codegraph_adapter.py # private CLI/SQLite boundary to CodeGraph
    │   ├── test_work.py
    │   ├── test_workmap.py
    │   └── fixtures/            # mock extractor for tests
    └── work/
        ├── checks.json
        ├── map.json             # map configuration
        ├── architecture.json    # reviewed module and constraint declarations (starts empty)
        ├── constitution.md
        ├── LESSONS.md
        ├── guides/              # includes map.md
        └── templates/
```

Keep AGENTS.md at the root: it directs the agent into workflow/. Merge existing AGENTS.md and .gitignore
rather than overwriting project content. Copy hidden directories too. No dependency on the old repository remains.

Requirements: Git and Python 3.10+, an initialized checkout with at least one commit. Install CodeGraph
1.6.2 for AST/resolver analysis (see [map guide](work/guides/map.md)); Graphify is not required. For a project-local
npm install, use `npm install --prefix .work/tools @colbymchenry/codegraph@1.6.2` and configure
`extractor.command` for that executable or put it on PATH. No automatic downloads or agent configuration edits.

From the repository root:

```sh
python3 -m unittest discover -s workflow/scripts/work -p 'test_*.py'
python3 workflow/scripts/work/work.py map update
python3 workflow/scripts/work/work.py map coverage
python3 workflow/scripts/work/work.py status
```

Make the agent read root AGENTS.md if it does not discover it automatically. All commands run from the repository
root, not inside workflow/. Logs, graph and private engine mirror remain in ignored root `.work/`.
Missing CodeGraph permits explicitly limited fallback navigation, with no guessed call graph. Parser failures,
unsupported inputs and unresolved references are visible in coverage. Structured-resource parsers and the pinned Tree-sitter Bash supplement cover JSON/ARB, XML, TOML and shell.
Install `workflow/scripts/work/requirements.txt` in the workflow Python environment (no Graphify). Bash analysis
is parse-only and reports dynamic/unresolved commands; it does not execute scripts or prove runtime effects. Product checks still require the actual Flutter/Android/Rust toolchains when
those domains change. No old graphify-out/ directory or machine-specific paths should be copied.

### Optional agent integrations

The shared source is `AGENTS.md`, `workflow/.agents/skills/` and `workflow/.agents/reviewers/`. There is no required
provider-specific directory, import syntax or tool allowlist. Configure your agent to read AGENTS.md if it
uses another entry convention. Do not duplicate the skills into provider-specific copies.

If your agent supports hooks, wire session start to `python3 workflow/scripts/work/work.py status --brief`, new requests
to `python3 workflow/scripts/work/work.py remind`, and shell preflight to `python3 workflow/scripts/work/work.py hook-bash`.
A post-edit hook may run `python3 workflow/scripts/work/work.py map update`; it only saves the refresh that the next
`context`, `check`, `round` or gate would otherwise do.
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
- Map ranking is lexical; structural relationships are resolver candidates, not compiler or runtime proof.
  Review per-file coverage and native-boundary gaps; no complete-call-graph claim is made.
