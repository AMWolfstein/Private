---
name: ship
description: "Finishing work: final checks on the final tree, drift between spec, plan and code, lessons turned into checks, commits with explicit paths, and the report. Push, APK builds and releases only when the owner asks in the current conversation."
---

# Ship

## 1. Final evidence

- `python3 scripts/work/work.py check auto` on the final tree, then `python3 scripts/work/work.py fresh`.
- Quote the counts from the report (`tests.passed`, `failed`, `skipped`) and any STALLED, TIMEOUT or BLOCKED
  chunk. Those are not passes: rerun that chunk alone; if it still does not finish, tell the owner and ask before
  committing.

## 2. Drift (change records only)

Compare the final code with spec.md and plan.md. Report only differences: missing behaviour, partial models,
shortcuts, a different architecture, and code no document mentions. For each, update the document or raise it
with the owner. Fill the `## Close` lines in `log.md`: Drift, Not verified, Lessons.

## 3. Lessons

If this work repeated a mistake already seen once (check `work/LESSONS.md`, `git log`, the change logs), turn it
into the strongest check that works: structure, type, lint or test, hook, then prose. Prove the check fails on
the old mistake and passes on the fix, and add a row to `work/LESSONS.md`. A single incident needs no new rule.

## 4. Commits

- Stage explicit paths; never `git add -A` or `git add .` (the hook blocks them).
- Commit 1, code: source, tests and configuration. Commit 2, records: `work/changes/…`, `work/LESSONS.md`, docs.
  Never mix them. A fix without a change record is one code commit.
- Message: what changed and why, the evidence (checks and counts), and what is not verified. No model names.
- Commit to the branch the owner works on. If the remote moved, rebase your unpushed commits; never force push.
- Change records: `python3 scripts/work/work.py advance <NNN> ship` before committing and `advance <NNN> done`
  after the Close lines are filled.

## 5. Push, APK, release

Only when the owner asks in this conversation. An APK build never runs while Flutter tests run. After a build,
say exactly which commit it came from and that it has not been tested on a device unless the owner did so.

## 6. Report

Use the report format in the `work` skill, in the owner's language.
