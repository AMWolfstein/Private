# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `d0818d7a`, refreshed in `a85b4965` for batch 4. 23,112 nodes / 44,630 links validated. Existing vendor/preprocessor extraction warnings remain. Check with `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested first fix batch: FIX_PLAN #1 (DATA-501).
- Next audit unit: none — all 10 subsystems and the final dead-code sweep are done. Next:
  user-approved fix batches from `FIX_PLAN.md` (nothing fixed yet).
- Open findings: 226 (0 P0, 1 P1, 63 P2, 162 P3; see `FINDINGS.md`). MORN-001..017, HOME-001..008 and PLAY-001..004: Mornye parity with upstream artist/album/playlist, Home and Now Playing.
- Last checkpoint: port batch 4 (U-205 `6e44c6be`, U-216 `95e2b158`, U-206 evaluated/no source port, U-207 `d0818d7a`; final graph `a85b4965`); this docs commit records the batch. Last review checkpoint remains the second dead-code pass.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Owner decisions (2026-10-20): About credits/links/social and the Search Recent list removed
  (`c29daef`, not yet full-tested); `MANAGE_EXTERNAL_STORAGE` kept; `NativeReplayGainPolicy` kept for Media3.
  Fixes are done by separate modules from `FIX_PLAN.md`; this session only reviews.
- Upstream ports: upstream is now `mornyeapp/Mornye`, checked to `e0563ffa`. Codex implements
  `PORT_PLAN.md`; batches 1, 1b, 2, 3 and 4 done. Batch 4 output errors, late media snapshots and local SAF lyrics fixes retain UI/engine; U-206 legacy Material fallback patch rejected, equivalent Mornye production behavior retained. No dependencies/schema/Rust source changes. KT-202 still OPEN. Batch 4 verification: analysis clean, full Flutter 1,657 pass / 3 skip, Android unit 59 pass / 1 skip and plugin/instrumentation Kotlin/Java compiled. No APK. Requested effort MEDIUM (runtime effort not exposed). Branch: `ccr-2fb644cd-nmesyt`; source/graph `a85b4965` pushed/fetched; docs checkpoint published afterward, verify remote HEAD on resume. Next: batch 5 (U-214/U-215/U-208/U-209). See `HANDOFF.md`.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
