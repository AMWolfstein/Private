# Check auto report: 8902315

- Commit checked: `8902315ba770b9276b85b7f8978b0a9a630ed278` (`mornye-reboot3`).
- Command (run once): `python3 workflow/scripts/work/work.py check auto --base 365dcae`
- Overall status: **PASS**; exit code: **0**.
- Run: `20261110T100130315583Z`, completed `2026-11-10T10:48:57+00:00`.
- Literal final console line: `}`.
- `source_changed_during_run`: **false**.

| Check | Status | Passed | Failed | Skipped |
| --- | --- | ---: | ---: | ---: |
| Flutter analyze | PASS; no issues found | N/A | 0 | N/A |
| Dart tests (543 targets) | PASS | 4499 | 0 | 10 |
| Android unit tests (33 suites) | PASS | 176 | 0 | 2 |
| Rust tests (27 result summaries) | PASS | 556 | 0 | 8 |
| Workflow tests (179 tests) | PASS | 170 | 0 | 9 |

Failing test names: **None**. No failing checks; no first errors to report.

## Evidence and limitations

- `latest.json` is the unmodified runner report. Its aggregate is 4669 passed, 0 failed, 19 skipped; the runner aggregates Dart and workflow test counts only. Android counts above come from JUnit XML; Rust counts come from the Rust log.
- The configured Rust command was `cargo +1.99.1 test --manifest-path rust_backend/Cargo.toml --workspace`. It did **not** include `--locked`; locked-mode verification is not claimed.
- `check-auto.txt` contains the full console output. `run-files.txt` lists the full run directory. Selected check logs and Dart logs without a final “All tests passed” line are in `logs/`; passing Dart logs are omitted.
- Error text inside workflow fixture demonstrations is expected test output; the workflow suite finished successfully.
- No source, test or workflow files were changed. No checks were rerun to create this report. No device testing is claimed.
