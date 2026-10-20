# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested first fix batch: FIX_PLAN #1 (DATA-501).
- Next audit unit: none — all 10 subsystems and the final dead-code sweep are done. Next:
  user-approved fix batches from `FIX_PLAN.md` (nothing fixed yet).
- Open findings: 226 (0 P0, 1 P1, 63 P2, 162 P3; see `FINDINGS.md`). MORN-001..017, HOME-001..008 and PLAY-001..004: Mornye parity with upstream artist/album/playlist, Home and Now Playing.
- Last checkpoint: upstream port batch 9; source 892eb173, graph fd1a520b. See PORT_EXECUTION.md for per-port commits.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Owner decisions (2026-10-20): About credits/links/social and the Search Recent list removed
  (`c29daef`, not yet full-tested); `MANAGE_EXTERNAL_STORAGE` kept; `NativeReplayGainPolicy` kept for Media3.
  Fixes are done by separate modules from `FIX_PLAN.md`; this session only reviews.
- Upstream ports: batches through 9 complete. PASS: analysis clean; Flutter 1753 passed / 3 skipped / zero failures (04:16); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
  Graph fd1a520b, source 892eb173: 23,940 unique nodes / 45,919 valid links; synchronized, existing vendor extraction warnings remain.
  Branch ccr-2fb644cd-nmesyt. No APK. Next: batch 10 (MORN-001..005 and MORN-017; FIX_PLAN M1+M2).
  User authorizes all remaining PORT_PLAN batches autonomously. Model policy SOL only; runtime identity/effort not exposed. Recommended effort MEDIUM. KT-202 remains OPEN.
  Docs checkpoint pushed after checks; fetch/verify on resume. See HANDOFF.md and PORT_EXECUTION.md.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
