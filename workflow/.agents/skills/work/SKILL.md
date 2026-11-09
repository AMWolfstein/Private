---
name: work
description: "Entry point for every request about this repository: a bug report or screenshot, a feature, a plan or discussion, a review, a question about the code, a build or release. Chooses the path (fix, spec, plan, build, review, ship) so the owner never has to name a skill."
---

# Work

The owner talks normally, often in Arabic, sometimes with a screenshot. You pick the path, do the work, and
report with evidence. Reply in the owner's language; code, records and commit messages stay in English.

## Start of every request

On first use of a Linux checkout, run `work.py doctor`. For missing workflow dependencies run `work.py setup`
(project-local installation is authorized by this workflow); rerun doctor after configuration/tool changes.
Do not install OS packages with sudo or modify agent-provider configuration. If Git/Python/Node/npm
prerequisites are missing, report the prerequisite instead of calling fallback analysis complete. Setup is
reusable/offline after initial provisioning, and normal CLI commands discover its Python/CodeGraph automatically.

1. Run `work.py status`: active change records, freshness of the last checks, uncommitted
   paths. If a change is active and the request belongs to it, continue it from its records.
2. Know the rules: `workflow/work/constitution.md` (always), accepted specs in `workflow/work/changes/` (product decisions).
3. Restate the goal in one line to yourself. Find the code before deciding the size, without reading whole
   files or reports first: `python3 workflow/scripts/work/work.py context "<identifiers or English words>"`
   (add `--file`/`--symbol` once you know a starting point; screenshot text → `rg` the arb key first, then
   `--file` the widget). It refreshes a stale map and returns entry points, both sides of affected channels,
   declared ownership and contracts, linked tests and checks, and what is uncertain. Open only the files it
   points to. A FALLBACK section is text search, not graph evidence; confirm with `rg` and by reading code.
4. Read only the guidance the packet lists under "Guidance to read" plus the skill for the chosen path. The
   packet's facts are leads with provenance; a claim about the code still needs the code itself.

## Choose and execute

- Questions/audits: read-only unless implementation is requested.
- Small bounded behavior: fix skill, `new --size small`, no planning stage. Contracts, data
  formats, architectural choices or multiple independent units require feature/architecture
  planning. File/line counts and high-risk path hints alone do not determine size.
- Larger changes: spec and plan skills unchanged, then ONE planning commit containing the
  complete accepted planning bundle. Owner authorization persists; do not ask again routinely.
- Execution: implement skill. One task at a time: map/context, implement,
  appropriate checks, independent review/fixes, ONE Git commit for code/tests/fixes/records.
  Do not complete a task before clean review or start the next before the actual commit.
- Three reviews maximum per task cycle. Third dirty: stop/report, no fourth automatic round.
  Explicit owner instructions are required for resume; preserve the full history.
- New owner work outside the queue becomes TOR### with the same loop. The last [FINAL] task
  checks/reviews the cumulative result. No separate execution build/review/ship transitions.
- Fingerprints are automatic. Reports/progress do not stale code checks; changed code or
  requirements do. Missing checks/maps are explicit, not invented PASS evidence.
- Never silently fix unrelated failures, restore unrelated edits or publish/build APK unless
  requested. Keep progress concise. Current owner constraints override generic guidance.

## Report format

End every piece of work with, in the owner's language:

1. What was wrong or what was asked, in one or two lines (the cause, for bugs).
2. What changed, as behaviour the owner will notice.
3. Evidence: the checks that ran, with counts (for example "11 setup tests, `flutter analyze` clean, suite 2,281
   passed"), and the proof that a regression test fails without the fix.
4. Not verified: device checks, stalled chunks, anything skipped.
5. Commits and branch, if any, and what you did not do because it needs the owner (push, APK).
