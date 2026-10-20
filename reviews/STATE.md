# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `81869c48`, refreshed for U-103b and U-201 lint (`11456f4f` manifest checkpoint; same dependency topology). 23,003 nodes / 44,612 links validated. Check with `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested first fix batch: FIX_PLAN #1 (DATA-501).
- Next audit unit: none — all 10 subsystems and the final dead-code sweep are done. Next:
  user-approved fix batches from `FIX_PLAN.md` (nothing fixed yet).
- Open findings: 226 (0 P0, 1 P1, 63 P2, 162 P3; see `FINDINGS.md`). MORN-001..017, HOME-001..008 and PLAY-001..004: Mornye parity with upstream artist/album/playlist, Home and Now Playing.
- Last checkpoint: port batch 1b (code `f10f45f6`/`81869c48`, lint `f34ead84`, graph manifest `11456f4f`); this docs commit records the batch. Last review checkpoint remains the second dead-code pass.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Owner decisions (2026-10-20): About credits/links/social and the Search Recent list removed
  (`c29daef`, not yet full-tested); `MANAGE_EXTERNAL_STORAGE` kept; `NativeReplayGainPolicy` kept for Media3.
  Fixes are done by separate modules from `FIX_PLAN.md`; this session only reviews.
- Upstream ports: upstream is now `mornyeapp/Mornye`, checked to `e0563ffa`. Codex implements
  `PORT_PLAN.md`; batches 1 and 1b done. U-103b `f10f45f6`/`81869c48`; U-308 timed-vocal prerequisites partial, sharing/glow still pending. U-104/U-201 tested, subtitle lint `f34ead84`. Next: batch 2 (U-201b/U-202); WIP stays in `reviews/wip/`. Full Flutter 1,629 pass / 3 skip; analysis clean; Kotlin 59 pass / 1 skip. No APK. Branch: `ccr-2fb644cd-nmesyt`; fetch and verify remote HEAD when resuming.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
