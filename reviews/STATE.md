# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `2c4ce3ff`, refreshed in `11d8f750` for batch 5. 23,147 unique nodes / 44,693 valid links. Existing vendor/preprocessor extraction warnings remain. Check with `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested first fix batch: FIX_PLAN #1 (DATA-501).
- Next audit unit: none — all 10 subsystems and the final dead-code sweep are done. Next:
  user-approved fix batches from `FIX_PLAN.md` (nothing fixed yet).
- Open findings: 226 (0 P0, 1 P1, 63 P2, 162 P3; see `FINDINGS.md`). MORN-001..017, HOME-001..008 and PLAY-001..004: Mornye parity with upstream artist/album/playlist, Home and Now Playing.
- Last checkpoint: port batch 5 (U-214 `10c04f7a`, U-215 `fa838caa`, U-208 evaluated/rejected, U-209 `ba751b35` / `2c4ce3ff`; final graph `11d8f750`); this docs commit records the batch. Last review checkpoint remains the second dead-code pass.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Owner decisions (2026-10-20): About credits/links/social and the Search Recent list removed
  (`c29daef`, not yet full-tested); `MANAGE_EXTERNAL_STORAGE` kept; `NativeReplayGainPolicy` kept for Media3.
  Fixes are done by separate modules from `FIX_PLAN.md`; this session only reviews.
- Upstream ports: upstream `mornyeapp/Mornye`, checked to `e0563ffa`. Codex implements
  PORT_PLAN; batches 1, 1b, 2, 3, 4 and 5 done. Batch 5 gates startup channels on Activity
  attachment, configures renderer compatibility before shared engine creation and reuses
  local lyric patterns. U-208 Material-only patch rejected; U-209 removed history/download
  hunks rejected and future module formatter hunks deferred to batches 6/8. No dependency,
  schema, branding or engine changes. KT-202 OPEN. PASS: analysis clean; full Flutter 1,659 passed / 3 skipped / zero failures (4m02s); Rust fmt/Clippy clean, 231 passed / 1 ignored; Android unit 61 passed / 1 skipped (1m06s). No APK; device startup/GPU
  checks NOT RUN. Continued MEDIUM preference (runtime effort not exposed).
  Branch `ccr-2fb644cd-nmesyt`; docs checkpoint pushed after validation, fetch/verify on resume.
  Next: batch 6 (U-210/U-303/U-217/U-218), including U-209 number regex with U-303.
  See HANDOFF.md.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
