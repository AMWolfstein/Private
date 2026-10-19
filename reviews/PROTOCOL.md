# Review protocol

Shared by every reviewer (Claude Code agents in `.claude/agents/`, Codex, OpenCode). Agents
read this once per invocation; it is the only place these rules live.

## Workflow

`DISCOVER → REVIEW → VALIDATE → PRIORITIZE → FIX → TEST → CHECKPOINT`

Reviewers only REVIEW. They never edit files. Fixes go through `review-fixer` (or the
orchestrator) with one validated batch of 1–3 related findings.

## Modes

| Mode | Entry | Unit | Reviewers |
|---|---|---|---|
| Incremental (default) | `/review [range]` | a commit or range | 1 by default, 2 when the diff crosses risk domains, 3 max |
| Full audit (explicit) | `/audit <subsystem>` | one subsystem from `reviews/coverage.md` | 2–3 max |

Never launch every reviewer. Never review the whole repo for a small commit.

## Scope discovery (orchestrator, before spawning)

1. `scripts/review_scope.sh [range]` — changed files, risk domains, suggested reviewers,
   graph freshness. `--subsystem <id>` lists a full-audit unit. No model needed.
2. If the graph is fresh for the scope: `graphify query "<symbol or question>"`,
   `graphify explain "<Symbol>"`, `graphify path "<A>" "<B>"` to find direct dependents.
   Use `--budget` only when output is truncated and the missing nodes matter.
3. If the graph is stale for the scope: say so in the brief and use targeted `grep`/reads.
   Never invent edges. Do not run `graphify update .` during a review; it belongs to the
   code-change commit flow in `AGENTS.md`.
4. If the unit is small (a few lines, one file, one obvious concern) the orchestrator reviews
   it directly instead of spawning an agent.

## Reviewer brief (what an agent receives)

- Mode, commit range or subsystem id.
- Files and symbols in scope (from step 1–2), plus graph freshness.
- Risk concern to focus on, and open finding IDs touching the scope (from `FINDINGS.md`).
- Nothing else: no transcripts, no previous reports.

## Reviewer rules

- Stay inside the assigned scope and your specialization. Read changed hunks first
  (`git diff <range> -- <file>`), then only the symbols they touch, then direct dependents.
- Prefer `grep -n` / ranged reads over whole files. Do not reread unchanged code without a
  reason. Do not repeat architectural discovery; the brief already holds it.
- Expand scope only when evidence requires it, and say so under Limitations.
- Report actionable findings only. Stop when the scope is covered.
- Escalate (state it in Result) instead of guessing when a finding needs deeper reasoning:
  complex concurrency, critical security, data corruption, hard Rust `unsafe`/FFI, or an
  architectural conflict. The orchestrator re-runs that finding on Opus.

## Project rules (do not report these as defects)

Read `AGENTS.md` for the full list. In short:

- Offline-only Android music player; local files only. Do not suggest restoring providers,
  downloads, online lyrics, remote artwork, extension credentials, Wishlist, format
  conversion, external-player modes, the metadata/details route or any network feature.
- Material Expressive UI was removed on purpose; Mornye is the only production theme.
- Preserve the Rust metadata backend and the existing Kotlin decoders.
- Media3 migration is planned separately: do not propose broad optimization or replacement
  of legacy playback code. Report correctness, leaks, thread safety, buffers, FFI safety,
  lifecycle and Android-compatibility defects in it.
- Never recommend replacing the audio engine.
- Removed features and documented UI decisions are not bugs.

## Finding format

```
### <ID> [P0|P1|P2|P3] [confidence: high|medium|low] [VALIDATED|NEEDS VERIFICATION]
- Location: path/to/file.dart:123 (`Symbol`)
- Scenario: concrete input/state → wrong result
- Root cause: one line
- Impact: what the user or data experiences
- Fix: minimal change, rough size
- Evidence: callers/lines/graph edge proving the path
```

- ID: `<AREA>-<NNN>` (areas: BUG, UI, UX, CONC, DATA, SEC, RUST, KT, DEP, API, PERF, TEST,
  DEAD, DOC). Take the next free number from `FINDINGS.md`; never reuse an ID.
- P0 crash/data loss/security hole on a common path · P1 user-visible defect or leak ·
  P2 edge-case defect or measurable inefficiency · P3 minor, low-risk cleanup.
- Do not report: speculation without a traced path, cosmetic preferences, duplicates of an
  open ID, already-fixed issues, intentional decisions, generic best practice without impact.
- Uncertain but plausible → `NEEDS VERIFICATION`, never a higher severity to compensate.

## Reviewer output

```
## Scope
files/symbols actually reviewed
## Findings
(entries above, or "None")
## Verification
checks done / not done
## Limitations
unreviewed areas, uncertainty, stale graph
## Result
PASS | FINDINGS | INCOMPLETE  (+ ESCALATE: <ID> when needed)
```

No narrative summaries, no code dumps beyond a few lines of evidence. PASS covers only the
reviewed scope.

## Validation (orchestrator)

Before recording, re-check every P0/P1 and every NEEDS VERIFICATION item against the source
(one targeted read). Drop false positives; mark the rest VALIDATED or keep NEEDS VERIFICATION.

## Fix batches

`review-fixer` gets only: finding entries, source paths, expected behavior, acceptance
criteria, required tests. 1–3 related findings per batch. Then follow `AGENTS.md`: `flutter
analyze` clean, full `flutter test` (only the known flaky paging test may fail; the
root-only `file_stat_boundary_test` permission case fails in root containers),
`scripts/check_rust_backend.sh` for Rust, then the code → graphify → docs commits.

## Persistent state (`reviews/`)

| File | Holds |
|---|---|
| `STATE.md` | last reviewed commit, graph status, next unit, last checkpoint SHA/push, handoff |
| `FINDINGS.md` | every finding with status: open (by priority), resolved, rejected |
| `coverage.md` | full-audit subsystems, reviewed commit per subsystem |
| `VERIFICATION.md` | analyze/test/clippy runs tied to commits |

Update only the files the unit changed. A completed subsystem is not re-reviewed unless
`git diff <reviewed-sha>..HEAD -- <paths>` is non-empty.

## Checkpoint

Update state → check that IDs in `STATE.md`/`coverage.md` exist in `FINDINGS.md` → commit
only `reviews/` (`docs(review): <unit>`) → `git push -u origin <branch>` → record the SHA and
the verified push result in `STATE.md` (amend nothing; the record lands in the next
checkpoint commit). Never force-push or touch uncommitted user work. Stop.
