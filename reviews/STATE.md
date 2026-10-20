# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `98fe1946` (fresh for all app code). Check with
  `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested fix batch: BUG-001 + BUG-002 + TEST-002 (CUE split).
- Next audit unit: `ui`, then build, tests (full audit in progress; audio, storage, scanner,
  metadata, kotlin, rust, state done). Dead-code sweep at the end (iOS helpers,
  download/re-enrich l10n keys, `recent_access_provider` callers, `music_services.dart`).
- Open findings: 115 (0 P0, 1 P1, 44 P2, 70 P3; see `FINDINGS.md`).
- Last checkpoint: `/audit state` (this commit). Previous `f0f07be` pushed and verified.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- UI audit: round 1 (player, Library lists/selection, detail/Home) done, findings drafted but
  not yet recorded; round 2 (settings/shell U4, shared widgets/theme U5) interrupted by usage
  limit, to be re-run.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
