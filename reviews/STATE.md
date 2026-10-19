# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `98fe1946` (fresh for all app code). Check with
  `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested fix batch: BUG-001 + BUG-002 + TEST-002 (CUE split).
- Next audit unit: `audio` (playback correctness/leaks/threading only; Media3 migration is
  separate) — then `storage`, `scanner`.
- Open findings: 10 (0 P0/P1, 3 P2, 7 P3; see `FINDINGS.md`).
- Last checkpoint: `/review 2b32361~5..2b32361` (this commit). Previous checkpoint
  `b15a651` pushed and verified.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
