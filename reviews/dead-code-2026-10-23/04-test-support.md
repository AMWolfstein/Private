# Test-support entrypoints and orphan helpers (R3)

## Scope

Role dead-code-hunter, source d5d5a02 unchanged. All254 tracked Flutter/integration *_test.dart paths recognized as runner entrypoints rather than dead imports. All12 other Dart test/integration helper paths screened by path/basename references across tracked application,tests,native,scripts/config/docs, excluding generated review/graph outputs. Whole reads: integration_test/performance_driver.dart,test/support/network_scan_output.dart,test/support/lyrics_usability_benchmark.dart. Graph benchmark/driver query completed truncated, navigation only.

## Findings

### DEAD-006 [P3] [confidence: high] [VALIDATED — static]

- Location: test/support/network_scan_output.dart:7, InstrumentedScanOutput; test/support/lyrics_usability_benchmark.dart:9, legacyCleanLyricsForDisplay and associated functions.
- Scenario: two support libraries remain after their scanner/lyrics benchmark consumers vanished; no test imports or invokes them and neither has main/test registration.
- Root cause: orphan benchmark/fault-injection helpers.
- Impact:137 lines of nonexecuted support code imply regression/performance evidence that current test discovery never exercises.
- Fix: delete both orphan libraries or reconnect them to a deliberately retained test; low runtime risk. Do not claim removing them improves test results.
- Evidence: filename/path search yields no consumers. InstrumentedScanOutput appears only at declaration/constructor. legacyCleanLyricsForDisplay appears only declaration and fullDisplayLyricsUsability in same orphan file; fullDisplayLyricsUsability/measureLyricsUsability have no external refs. Public visibility alone creates no runner entrypoint.
- Cross-refs: entire tracked Dart test/import corpus and source/config/doc references.
- Guards checked: test-only code is not automatically dead; these have zero actual test consumer or injection use. performance_driver.dart has no importer too, but defines a manual flutter drive main and is explicitly retained. Remaining11 helper paths have importing test consumers (driver retained as separate root); standalone test roots retained.

## Verification / limits

No tests/builds executed; static helper reference screen only. Other helper bodies and test-local private declarations not exhaustively audited. Kotlin/Rust test roots reviewed in native chunks. No deletion/security checks. Result FINDINGS.
