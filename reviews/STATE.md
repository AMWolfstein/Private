# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `a54269a9` (fresh for all app code). Check with
  `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested first fix batch: FIX_PLAN #1 (DATA-501).
- Next audit unit: none — all 10 subsystems and the final dead-code sweep are done. Next:
  user-approved fix batches from `FIX_PLAN.md` (nothing fixed yet).
- Open findings: 214 (0 P0, 1 P1, 60 P2, 153 P3; see `FINDINGS.md`). MORN-001..017: Mornye parity with upstream artist/album/playlist screens.
- Last checkpoint: second dead-code pass (this commit). Previous `2db6547` pushed and verified.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Owner decisions (2026-10-20): About credits/links/social and the Search Recent list removed
  (`c29daef`, not yet full-tested); `MANAGE_EXTERNAL_STORAGE` kept; `NativeReplayGainPolicy` kept for Media3.
  Fixes are done by separate modules from `FIX_PLAN.md`; this session only reviews.
- Upstream ports: `UPSTREAM.md` (fork base v5.1.1, checked to `21ee30c4`; U-001 tag separators requested).

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
