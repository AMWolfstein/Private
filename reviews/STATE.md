# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `a54269a9` (fresh for all app code). Check with
  `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested fix batch: BUG-001 + BUG-002 + TEST-002 (CUE split).
- Next audit unit: none — all 10 subsystems reviewed. Final dead-code sweep (l10n, prefs,
  assets, channel methods, unimported files) running; then fix-batch planning. Dead-code sweep at the end (iOS helpers,
  download/re-enrich l10n keys, `recent_access_provider` callers, `music_services.dart`;
  Mornye-only collapse DEAD-601/622/633, UX-104, DEAD-631/632).
- Open findings: 165 (0 P0, 1 P1, 52 P2, 112 P3; see `FINDINGS.md`).
- Last checkpoint: `/audit tests` (this commit). Previous `3494027` pushed and verified.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Product question: UX-205 (About page loads GitHub avatars over the network).

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
