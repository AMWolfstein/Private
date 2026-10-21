# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested first fix batch: FIX_PLAN #1 (DATA-501).
- Next audit unit: none — all 10 subsystems and the final dead-code sweep are done. Next:
  user-approved fix batches from `FIX_PLAN.md` (nothing fixed yet).
- Open findings: 201 (0 P0, 1 P1, 57 P2, 143 P3; see FINDINGS.md). Remaining findings are outside completed port/refinement batches.
- Last checkpoint: upstream port batch 13; source c4e9e536, graph 8ad07efd. See PORT_EXECUTION.md for per-port commits.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Owner decisions (2026-10-20): About credits/links/social and the Search Recent list removed
  (`c29daef`, not yet full-tested); `MANAGE_EXTERNAL_STORAGE` kept; `NativeReplayGainPolicy` kept for Media3.
  Fixes are done by separate modules from `FIX_PLAN.md`; this session only reviews.
- Upstream ports: batches through 13 complete. PASS: analysis clean; Flutter 1771 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
  Graph 8ad07efd, source c4e9e536: 23,983 unique nodes / 46,028 valid links; synchronized, existing vendor extraction warnings remain.
  Branch ccr-2fb644cd-nmesyt. No APK. Next: batch 14 (PLAY-001..004 and U-311).
  User authorizes all remaining PORT_PLAN batches autonomously. Model policy SOL only; runtime identity/effort not exposed. Recommended effort MEDIUM. KT-202 remains OPEN.
  Docs checkpoint pushed after checks; fetch/verify on resume. See HANDOFF.md and PORT_EXECUTION.md.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
