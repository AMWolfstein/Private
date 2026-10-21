# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested first fix batch: FIX_PLAN #1 (DATA-501).
- Next audit unit: none — all 10 subsystems and the final dead-code sweep are done. Next:
  remaining independent fix batches from `FIX_PLAN.md`; completed port/cleanup resolutions are archived in FINDINGS.md.
- Open findings: 139 (0 P0, 1 P1, 54 P2, 84 P3; see FINDINGS.md). Remaining findings are outside completed port/refinement batches.
- Last checkpoint: upstream port batch 16; source ef8ba64d, graph 331ab3d0. See PORT_EXECUTION.md for per-port commits.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Owner decisions (2026-10-20): About credits/links/social and the Search Recent list removed
  (`c29daef`, not yet full-tested); `MANAGE_EXTERNAL_STORAGE` kept; `NativeReplayGainPolicy` kept for Media3.
  Fixes are done by separate modules from `FIX_PLAN.md`; this session only reviews.
- Upstream ports: batches through 16 complete. PASS: analysis clean; Flutter 1513 passed / 3 skipped / zero failures (02:09); Android unit 55 passed / 1 skipped; Rust fmt/Clippy PASS, 165 passed / 1 ignored.
  Graph 331ab3d0, source ef8ba64d: 22,436 unique nodes / 42,940 valid links; synchronized, existing vendor extraction warnings remain.
  Branch ccr-2fb644cd-nmesyt. No APK. Next: none in PORT_PLAN; physical-device verification and separately approved remaining review fixes.
  User authorizes all remaining PORT_PLAN batches autonomously. Model policy SOL only; runtime identity/effort not exposed. Recommended effort MEDIUM. KT-202 remains OPEN.
  Docs checkpoint pushed after checks; fetch/verify on resume. See HANDOFF.md and PORT_EXECUTION.md.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
