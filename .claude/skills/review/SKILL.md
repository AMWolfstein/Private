---
name: review
description: "Incremental code review of a commit or range (default - everything since the last reviewed commit) using the minimum number of specialized reviewer agents. Use for \"review this commit\", \"review my changes\", \"/review <range>\". Read-only; fixes need a separate approval."
---

Follow `reviews/PROTOCOL.md`. Arguments: optional git range, or `--worktree`.

1. **Scope.** Run `scripts/review_scope.sh <args>`. It prints commits, files by subsystem,
   graph freshness and up to 3 suggested reviewers. Nothing to review → update nothing, stop.
   `NO_TEST_CHANGES` → add test-auditor focus to the brief if the change is risky;
   `SPLIT_SUGGESTED` → review per commit or per subsystem instead of one brief.
2. **Context.** Read `reviews/STATE.md` and only the open entries in `reviews/FINDINGS.md`
   that touch the scoped files (`grep -n '<path>' reviews/FINDINGS.md`).
3. **Pick reviewers.** Start from the suggestion; drop any whose specialty is not actually
   touched by the hunks (`git diff <range> --stat`, then skim hunks if needed).
   Default 1, 2 when the diff crosses risk domains, 3 only for unusually complex changes.
   Add code-optimization-auditor only for perf-motivated changes, dead-code-hunter only when
   the change removes a feature. Tiny change (<30 lines, one concern) → review it yourself.
4. **Graph.** If fresh: `graphify explain "<ChangedSymbol>"` / `graphify query "<question>"`
   for direct dependents of changed symbols, at most a few calls. If stale: say so in the brief.
5. **Brief and run.** Spawn each reviewer with the PROTOCOL brief only (range, files/symbols,
   dependents, graph status, focus, open IDs). Run 2–3 reviewers in parallel only when
   their file sets differ.
6. **Validate.** Apply the PROTOCOL auto-reject list, then the skeptic check to every P0/P1
   and NEEDS VERIFICATION finding with one targeted read. Re-run escalated findings with the
   same agent and `model: opus`, scoped to that finding only.
7. **Record.** Append validated/unverified findings to `reviews/FINDINGS.md` (next free
   IDs), set `Last reviewed commit` and `Next review unit` in `reviews/STATE.md`, log any
   checks run in `reviews/VERIFICATION.md`.
8. **Checkpoint.** Commit only `reviews/` as `docs(review): <range>`; push; record the push
   result. Report a short table of findings (ID, severity, one line) and stop. Do not fix.
