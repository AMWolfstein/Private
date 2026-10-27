---
name: audit-project
description: "Coordinate an explicitly requested whole-project audit through bounded, resumable units, including cross-language contracts, data safety, native lifetimes and accessibility. Never launch all reviewers together."
---

Follow `reviews/PROTOCOL.md`, `AGENTS.md`, `reviews/STATE.md`, `reviews/AUDIT_PLAN.md` and
`reviews/coverage.md`. This coordinates the existing specialists, not a parallel UI or
architecture. Review-only; implementation needs separate authorization.

1. Inspect branch/status and latest checkpoint. Run `scripts/review_scope.sh
   --coverage-status` and inspect its exit code. Preserve existing findings and user edits.
   Reconcile fresh/stale results with explicit partial gaps and changed contract dependents.
2. Choose the highest-priority ready `not reviewed`, `partial` or `stale` unit in AUDIT_PLAN.
   Never choose only the first `not reviewed` subsystem or treat old summary rows as complete.
3. Record its baseline, exact planned paths (expand globs with rg/Git), reviewer owner,
   endpoints/dependents, risk checks and exclusions BEFORE review. A single unit is at most
   ~25 files/~6k lines; split larger ones into named chunks. A contract unit may cross
   subsystem boundaries. Historical/deleted paths require baseline blob and caller reads.
4. Use `/audit <subsystem>` discovery plus direct endpoint reads. Assign at most 2–3
   specialists per unit. Security/contract flags precede churn suggestions. Queue overflow
   reviewers explicitly, not silently. Never duplicate a file assignment without a different
   named concern. Reviewers return temporary IDs; coordinator deduplicates/assigns durable IDs.
5. Apply skeptic validation and recurrence checks. Record exact paths actually read,
   checks done and NOT RUN/BLOCKED evidence, new finding IDs and remaining gaps in AUDIT_PLAN.
   No finding is a valid PASS; unreviewed risk checks make the unit partial, not passed.
6. Update coverage/STATE/VERIFICATION. Checkpoint according to user authorization; no
   automatic app builds. With authorization for one unit, stop here. With explicit authority
   to finish the project audit, continue the next bounded unit with a checkpoint between
   units; stop only for a blocker, user stop, or completion. Do not expand a routine `/review`
   into a project audit.
7. After all path chunks, run the FINAL unit: reconcile exclusions and unresolved findings,
   verify both sides of changed contracts, inspect deletion dependents and recheck offline/
   Sistrum/retained-feature rules. Required evidence failures prevent completion. Publish the
   scope/revision, coverage totals, remaining investigations, device limitations and next
   actions; never claim the application regression-free from static review alone.
