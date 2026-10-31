---
name: work
description: "Entry point for every request about this repository: a bug report or screenshot, a feature, a plan or discussion, a review, a question about the code, a build or release. Chooses the path (fix, spec, plan, build, review, ship) so the owner never has to name a skill."
---

# Work

The owner talks normally, often in Arabic, sometimes with a screenshot. You pick the path, do the work, and
report with evidence. Reply in the owner's language; code, records and commit messages stay in English.

## Start of every request

1. Read the hook output (`work.py status`): active change records, freshness of the last checks, uncommitted
   paths. If a change is active and the request belongs to it, continue it from its records.
2. Know the rules: `workflow/work/constitution.md` (always), accepted specs in `workflow/work/changes/` (product decisions), and for engine work
   `docs/AUDIO_ENGINE_MIGRATION.md`.
3. Restate the goal in one line to yourself. Find the code before deciding the size, without reading whole
   files or reports first: `python3 workflow/scripts/work/work.py context "<identifiers or English words>"`
   (add `--file`/`--symbol` once you know a starting point; screenshot text → `rg` the arb key first, then
   `--file` the widget). It refreshes a stale map and returns entry points, both sides of affected channels,
   declared ownership and contracts, linked tests and checks, and what is uncertain. Open only the files it
   points to. A FALLBACK section is text search, not graph evidence; confirm with `rg` and by reading code.
4. Read only the guidance the packet lists under "Guidance to read" plus the skill for the chosen path. The
   packet's facts are leads with provenance; a claim about the code still needs the code itself.

## Choose the path

| Request | Path | Records |
|---|---|---|
| Question, explanation, "what do you think" about code | Answer from the code with `file:line`. No edits. | none |
| Discussion or planning ("let's plan", "عاوز نعمل خطة", a design question) | `spec` skill, then `plan`. Documents only; no code until the owner says to build. | change folder |
| Bug or small change: one behaviour, a few files, no contract, schema or format change | `fix` skill | none: test + commit + report |
| Feature: new behaviour or several files | `work.py new "<title>" --size feature`, then the skills `spec` → `plan` → `implement` (tasks and code; the record's phases are tasks and build) → `review` → `ship` | change folder |
| Architecture: a migration batch, a Dart ↔ Kotlin ↔ Rust contract, playback engine, database, backup or file format | `work.py new "<title>" --size architecture`: as feature, plus fresh-context design review | change folder |
| Review or audit ("راجع", "افحص") | `review` skill, read-only. Findings only unless the owner asks for fixes. | findings |
| Commit, push, APK, release | `ship` skill. Push and APK only when asked now. | none |

Size by consequence, not by effort. After the first edits run `python3 workflow/scripts/work/work.py scope`: if it lists
`high_risk` paths or a domain you did not expect, move up a size and say so. Never move down to skip a gate.

## Throughout

- Ask only when the answer changes what you build and no reasonable default exists. Routine choices: decide, and
  mention the choice in the report. Product or architecture trade-offs: give up to three options with mechanism,
  trade-offs and failure conditions, without ranking them, and wait.
- Keep the owner posted at milestones in one or two lines (found the cause; tests pass; waiting on the suite).
- Long-running checks run in the background; report honestly while they run. A stalled or timed-out check is
  reported as that, with what you did about it.
- Never start work the owner did not ask for (no push, APK, refactor or cleanup on your own initiative). Note it
  as a suggestion instead.
- After compaction or in a new session: `work.py status`, the change's `log.md` and `git log -5` tell you where
  you are. Re-run the last recorded check before trusting it.
- After each completed batch of edits, before the next graph-dependent step: `work.py map update` (or a
  `work.py check` run, which refreshes it). Renames, deletions and channel or contract changes count. Edits made
  outside the workflow are detected at the next workflow command, not when they happen.

## Report format

End every piece of work with, in the owner's language:

1. What was wrong or what was asked, in one or two lines (the cause, for bugs).
2. What changed, as behaviour the owner will notice.
3. Evidence: the checks that ran, with counts (for example "11 setup tests, `flutter analyze` clean, suite 2,281
   passed"), and the proof that a regression test fails without the fix.
4. Not verified: device checks, stalled chunks, anything skipped.
5. Commits and branch, if any, and what you did not do because it needs the owner (push, APK).
