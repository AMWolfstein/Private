# Code-map migration record

Current resource/Bash extension and validation: `RESOURCE_INDEX_RECORD.md`.

Current engine: CodeGraph 1.6.2. See `guides/map.md` for the active installation, schemas and limitations.
Graphify and regex call inference were retired; historical measurements below do not describe the current engine.
Current validation and review results are recorded in `CODEGRAPH_MIGRATION.md`.

---

## Archived Graphify implementation history (not current instructions)

# Code map implementation record

Resume point for the Graphify integration. Not a change record; no spec or gate depends on it.

## Done
- Graphify 0.9.97 inspected: Dart gets declarations (regex), no call edges; Kotlin gets tree-sitter symbols,
  calls and references; output is deterministic (same input, same output); network not needed (tested with `unshare -n`).
- `graphify_adapter.py` (process boundary, `graphify.extract()` only), `workmap.py` (map, freshness, locking,
  atomic publish, Dart/Kotlin channel scan, declarations, tests, context packets, packet section), `worklib.py`
  (shared helpers, snapshot fingerprint).
- `work.py`: `map status|update|build`, `context`; freshness wired into `check`, `packet`, `status`, `fresh`,
  `round code clean`, `advance` to review/ship/done, and `lint`.
- `workflow/work/map.json`, `architecture.json` (empty), `guides/map.md`; skills, AGENTS.md, README, reviewer updated.
- Tests: 126 pass (73 existing, 53 new in `test_workmap.py`: 3 real-Graphify smoke tests, 50 mocked with `fixtures/fake_graphify_adapter.py`).
- Install check: AGENTS.md + workflow/ copied into a temp git repo; `map update`, `context`, `fresh` run; `git status` clean except ignored `.work/`.

## Measured (`bench_context.py`, real app snapshot, 1010 files, Graphify 0.9.97)
Tokens are estimates (characters / 4). Baseline = whole-word search for the task words plus the five most-matching files read in full.

| Task | Map packet (est. tokens) | Baseline (est. tokens) | Expected items in map | in baseline |
|---|---|---|---|---|
| UI change (setup skip) | 2,381 | 69,154 | 3/3 | 3/3 |
| Playback bug (retry keeps song) | 2,636 | 81,284 | **0/2** | 1/2 |
| Bridge contract (usb_pcm prepare) | 2,786 | 29,087 | 2/3 | 2/3 |
| DSP port (equalizer) | 2,577 | 12,635 | 3/3 | 2/3 |

Map full update on the snapshot: about 5 s cold. Context query: about 0.2 s. Expected lists were written by hand
before running; they are small (2–3 items) and are not a statistically meaningful sample.

## Scope update (full repository)
- Corpus widened from Dart/Kotlin to every language Graphify extracts (1125 files on the snapshot: Dart 943,
  Kotlin 71, Rust 80, Python 18, C++/C/Java/shell and others). Config, data, vendored, generated, review and
  hidden folders stay excluded. Map build: about 9 s cold on the snapshot.
- Non-Dart/Kotlin languages: symbols, calls and references only; no import resolution, no channel scan.
- Bench on the full map: packets 2.4–2.8k estimated tokens, unchanged coverage results.

## Gap pass (after the scope update)
- Tests linked to entry files and their checks are critical (first three per file), no longer cut by the budget.
- Direct users of each entry file are critical (eight per file, the rest by `--expand`).
- Entry-file limit raised from 5 to 8; word matching uses synonyms (failure/error, plurals, -ing) and IDF weights.
- Dart calls inferred by name for unqualified calls and `this.` (`adapter:dart-name-call`, always inferred, low/medium).
  13,376 edges on the snapshot. Qualified calls are not attributed (false edges otherwise).
- Windows lock path via msvcrt added, not run here.
- Tests: 130 pass, 4 new.

Benchmark after these changes (same four tasks; the expected lists were written before the changes, and the
changes were made after seeing the misses, so this is not an independent sample):
ui-change 3/3, playback-bug 2/2, bridge-contract 3/3, dsp-port 3/3; packets 2.7–3.1k estimated tokens.

## Known gaps (open)
- Bridge case: `usb_pcm_bridge_test.dart` not in the packet's tests section for this task; tests are only linked
  when an entry file is a test or imports/names the channel.
- Dart has no call edges in Graphify 0.9.97; callers are approximated by importers.
- Kotlin calls inside lambdas are partly missing in Graphify.
- Tokens are estimates only; no model usage was measured.
- Independent review of the implementation (fresh-context `code-reviewer`) has NOT been run.
- Device checks: none (no app behaviour changed).

## Commands
    python3 -m unittest discover -s workflow/scripts/work -p 'test_*.py'     # 126 tests
    python3 workflow/scripts/work/work.py map update
    python3 workflow/scripts/work/bench_context.py --tasks TASKS.json --root .

## Next
1. Run the review skill on this change (fresh-context reviewer, packet with --base of the pre-change commit).
2. Address the playback-bug ranking gap or record it as a known limit in the guide.
3. Decide with the owner whether to pin Graphify in CI; the RealGraphify tests skip without it.
