# Review state

Entry point for any agent (Claude Code, Codex, OpenCode) resuming review work. Rules:
`reviews/PROTOCOL.md`. Keep this file short; history lives in git.

- Last reviewed commit: `2b32361`
- Graph: `graphify-out/` built from `0f51f5d0`, refreshed in `6361145f` for U-202. 23,056 nodes / 44,447 links validated. Existing vendor/preprocessor extraction warnings remain. Check with `scripts/review_scope.sh`.
- Next review unit: `/review` (commits after `2b32361`; review-system commits are
  docs/config only). Suggested first fix batch: FIX_PLAN #1 (DATA-501).
- Next audit unit: none — all 10 subsystems and the final dead-code sweep are done. Next:
  user-approved fix batches from `FIX_PLAN.md` (nothing fixed yet).
- Open findings: 226 (0 P0, 1 P1, 63 P2, 162 P3; see `FINDINGS.md`). MORN-001..017, HOME-001..008 and PLAY-001..004: Mornye parity with upstream artist/album/playlist, Home and Now Playing.
- Last checkpoint: port batch 2 (code `0f51f5d0`, graph `6361145f`); this docs commit records the batch. Last review checkpoint remains the second dead-code pass.
- Review system: adopted checks from external agent/skill repos (gate questions, skeptic
  validation, auto-reject list, `CALIBRATION.md`, per-agent "Also check" lines, fixer
  baseline/rollback, scope hints `NO_TEST_CHANGES`/`SPLIT_SUGGESTED`; android test dirs now
  map to `tests`).
- Owner decisions (2026-10-20): About credits/links/social and the Search Recent list removed
  (`c29daef`, not yet full-tested); `MANAGE_EXTERNAL_STORAGE` kept; `NativeReplayGainPolicy` kept for Media3.
  Fixes are done by separate modules from `FIX_PLAN.md`; this session only reviews.
- Upstream ports: upstream is now `mornyeapp/Mornye`, checked to `e0563ffa`. Codex implements
  `PORT_PLAN.md`; batches 1, 1b and 2 done. U-202 `0f51f5d0`; U-201b has no applicable local hunks, optional exit diagnostics unnecessary. U-201 does not fix KT-202 (still OPEN). WIP removed after upstream comparison. Batch 2 verification: analysis clean; full Flutter 1,629 pass / 3 skip, Kotlin 59 pass / 1 skip, native host 1/1 and ARM64 native compile pass. No APK. Branch: `ccr-2fb644cd-nmesyt`; source/graph pushed and fetched at `6361145f`; docs checkpoint is published after creation, verify remote HEAD on resume. Next: batch 3 (U-203/U-212/U-213/U-204), recommended HIGH for metadata/FFI safety. See `HANDOFF.md`.

## Handoff

1. Read this file, then `PROTOCOL.md`.
2. `scripts/review_scope.sh` (incremental) or `scripts/review_scope.sh --subsystem <id>`.
3. Claude Code: `/review` or `/audit <id>` skills; agents in `.claude/agents/`.
   Codex/OpenCode: no agent runtime is configured; act as the named reviewer by reading
   `.claude/agents/<name>.md` and following it, one reviewer per pass.
4. Record results here, in `FINDINGS.md`, `coverage.md`, `VERIFICATION.md`; commit `reviews/`.
