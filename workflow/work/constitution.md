# Sistrum engineering constitution

Version 1.0.0 (draft until the owner ratifies it). Every change, plan and review is checked against these
articles. A plan that cannot meet one records the deviation in its Complexity tracking table with the reason and
the simpler option it rejected; it never weakens the article.

Product decisions are not repeated here. They live in the accepted specs under `workflow/work/changes/` and, for engine
work, in `docs/AUDIO_ENGINE_MIGRATION.md` (decisions D1–D7, batch order) when that file is present. Both bind
every change.

## I. The owner decides (NON-NEGOTIABLE)

- The owner decides product behaviour, architecture trade-offs, licences, releases and anything that leaves the
  machine (push, publish, APK). The agent decides routine implementation details and does not ask about them.
- A removed feature does not come back because old code, a reference app or a reviewer suggests it.
- When the owner's request conflicts with a recorded decision, say so with the reference and ask; do not pick.
- A reviewer's preference never reopens an accepted decision.

## II. Evidence before claims (NON-NEGOTIABLE)

- A claim of "fixed", "works" or "passes" comes with the command that was run and its result in the same message.
- A check that did not run, timed out, stalled or was blocked is not a pass. Say which one.
- Host tests, compilation or a mocked channel never prove device behaviour. Device checks are listed as pending
  until the owner runs them on hardware.
- "Looks right" is not a check. Every task names its check before work starts.

## III. Root cause, smallest complete change

- State the root cause in one sentence before editing. If you cannot, observe more (a log line, a test); do not
  guess.
- Choose the first option that fully works: is it needed at all; does the codebase already do it; does Flutter,
  Android or Media3 provide it; does an installed dependency; then the least new code.
- Be economical with the solution and complete with the change: every caller, test, fixture, translation, setting,
  backup key and doc the change reaches is updated in the same change.
- Never cut: validation at trust boundaries, protection against data loss, security, accessibility (including RTL
  and touch targets), hardware calibration, or anything the owner asked for.
- No speculative options, wrappers or layers. A deliberate shortcut carries a comment
  `shortcut: <limit>, <when to upgrade>`.

## IV. Tests that prove something

- A bug fix comes with a regression test that fails without the fix. `work.py prove` shows it.
- Before replacing behaviour (a port, an engine change, a rewrite), characterization tests pin the current
  behaviour; differential tests compare old and new on the same input where both exist.
- Never weaken, skip, delete or loosen a test, assertion, lint or type to make a check pass.
- A test that only repeats the implementation proves nothing.

## V. Failure signalling

- A lookup that may find nothing returns `T?`; null means only "not found".
- An operation the user can see fail returns a typed result or throws a typed exception. No bare `bool` or map
  whose failure is a key to check.
- Best-effort cleanup says so in its name or comment.
- Unsupported, not found, permission failure, cancellation and failure stay distinguishable across Dart, Kotlin
  and Rust.

## VI. Boundaries and ownership

- Every Dart ↔ Kotlin ↔ Rust contract (channel methods, payload fields, units, nullability, errors) is tested on
  both sides; serialization lives in adapters, not in domain code.
- One owner per mutable state or resource, with its lifetime, thread and disposal stated. A stale callback never
  overwrites a newer request.
- Work that must continue with the screen off or the app closed belongs to the Android side.
- `part of` only splits one library's private implementation; a part file adds no imports.

## VII. Data integrity

- The original file survives a failed write. Cancellation cannot retract a committed write.
- Library song IDs, database schemas and migrations, backup archives, cover keys and preference keys stay
  compatible unless the owner accepts a break.

## VIII. Independent review

- A change of feature size or larger, or one touching a high-risk path (`workflow/work/checks.json`), gets a review from
  a fresh, read-only context that receives a packet, not the author's conversation.
- The author answers each finding: fix it, contest it with checkable evidence, escalate it to the owner, or
  decline a nit. A finding that disappears is not fixed until its evidence says why.
- Review the final code. Code changed after the last clean round is reviewed again.

## IX. Simplicity over ceremony

- No scores, line quotas or file splits for their own sake. Small fixes stay small: no records beyond the test,
  the commit and the report.
- Bounded loops: at most 5 attempts on one failing check, at most 4 review rounds. The same failure twice means
  the shared assumption is wrong; name it and change approach.
- A mistake seen twice becomes a check (structure, type, lint, test or hook), proved to fail on the bad case.
  Prose rules are the last resort.

## X. Git and releases

- Stage explicit paths. No force push, no skipped hooks, no history rewrite on shared branches.
- Commit only after the change's checks pass on the final tree. Code and process records go in separate commits:
  code (source, tests, config) first, then records (`workflow/work/`, docs).
- Commit messages say what changed, why, the evidence and what is not verified. No model names.
- Push, build an APK or release only when the owner asks for it in the current conversation. Flutter tests and
  APK builds never run at the same time.

## Governance

Only the owner amends this constitution. Each amendment bumps the version (major: an article removed or
redefined; minor: an article added or materially expanded; patch: wording) and updates the skills and templates
that depend on it in the same change.
