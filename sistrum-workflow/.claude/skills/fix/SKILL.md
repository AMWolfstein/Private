---
name: fix
description: "Bug fixes and small changes: one behaviour, a few files, no contract, schema or file-format change. Finds the root cause, writes a regression test that fails without the fix, makes the smallest complete change and verifies it."
---

# Fix

No change folder. The record is the regression test, the commit and the report.

## 1. Find the cause

- Start from what the owner sees. Text on a screenshot leads to an `lib/l10n/arb/app_en.arb` key, the key to the
  widget, the widget to its handler and state.
- Follow the flow to the state that is wrong, and read who else writes it. Lifecycle callbacks (resume, dispose,
  route changes), async gaps and early `return`s inside `try` are common culprits.
- Write the root cause in one sentence before editing. If you cannot, observe: add a test or a log line that
  shows the state. Do not guess.
- Look for a second defect on the same path. If it is small and in the same flow, fix it with its own test and
  report it separately. Otherwise report it and leave it.

## 2. Regression test

- Test at the level where the bug lives: widget test for a screen flow, unit test for logic, a Kotlin JVM test
  for Kotlin, a Rust test for Rust. Reuse the existing test file and its fakes for that area.
- Reproduce the real order of events (for example: the picker returns, then the app resumes and rechecks).
- Fix any existing test that encoded the old behaviour, and say so.

## 3. Change

Take the first option that fully works: not needed at all; already in the codebase; provided by Flutter,
Android or Media3; an installed dependency; the least new code. Then make the change complete: every caller,
test, fixture, translation (all arb files), setting and backup key it reaches. Keep validation, data-loss
protection, accessibility and hardware calibration.

## 4. Prove the test

```sh
python3 scripts/work/work.py prove --expect-failure "<specific assertion diagnostic>" -- flutter test test/path/to_test.dart --plain-name "test name"
```

`prove` runs the same command with the fix, with configured non-test code changes reverted to HEAD, and
again after restoring the fix. It requires pass/fail/pass and the literal assertion diagnostic only in the
failing run. `FAIL` means the test also passes without the fix. Missing diagnostics, timeouts or a failing
baseline/restored run are `INCONCLUSIVE`, never success. Inspect `.work/proofs/` logs to confirm the failure
is the regression, not a compiler or environment error; a text match alone cannot establish causality.
Run without concurrent edits or builds; this command temporarily changes the working tree. Forced
termination can prevent restoration. Checks must leave non-ignored inputs unchanged.

## 5. Verify

1. The targeted tests until they pass. At most 5 attempts on the same failure; if the same failure survives two
   different fixes, write down the assumption both shared, test that assumption, and change approach.
2. `python3 scripts/work/work.py check auto` for the full checks of every touched area (Dart analyze and the
   whole suite by folder; Android and Rust checks when those paths changed). Run it in the background and keep
   the owner informed.
3. STALLED, TIMEOUT or BLOCKED is not a pass. Re-run the affected chunk alone; if it still does not finish, tell
   the owner which chunk, what passed, and ask before committing.

## 6. Review (when it matters)

A fix that touches a `high_risk` path in `work/checks.json` gets one fresh-context review: follow the `review`
skill with `--base HEAD`. Otherwise the proof and the checks are enough.

## 7. Finish

Follow the `ship` skill: commit with explicit paths when the checks pass, and report in the owner's language.
Do not push or build an APK unless the owner asked.
