# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `98fe1946` (fresh for all app code). Check with
  `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested fix batch: BUG-001 + BUG-002 + TEST-002 (CUE split).
- Next audit unit: `rust`, then state, ui, build, tests (full audit in progress; audio,
  storage, scanner, metadata, kotlin done). Dead-code sweep at the end (iOS helpers,
  `trackReEnrich*`/download l10n keys, Rust ops only reachable from dead wrappers).
- Open findings: 67 (0 P0, 1 P1, 24 P2, 42 P3; see `FINDINGS.md`).
- Last checkpoint: `/audit kotlin` (this commit). Previous `cd88dab` pushed and verified.
- Tooling note: `scripts/review_scope.sh` maps `android/app/src/{test,androidTest}` to
  `audio`/`kotlin`; should map to `tests` (fix with next code commit).

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
