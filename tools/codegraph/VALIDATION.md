# Validation of standalone navigation tools

Validated on `new-workflow`, based on `261626f3`, using existing local tools.
Application sources, dependencies and GitHub Actions were unchanged.

- `python3 -m unittest discover -s tools/codegraph -p 'test_*.py' -v`:
  **33 passed, 0 failed, 0 skipped**, with CodeGraph 1.6.2 installed and
  `CODEGRAPH_SHELL_PYTHON` selecting the pinned Bash-parser environment.
- Full `code_tools.py update` and subsequent incremental update succeeded.
  Final source extraction: 1,776 indexed sources, 36,573 symbols and 127,937
  relationships; CodeGraph reported no partial/unindexed source files in that scope.
  These counts include tests and tooling, not exclusively live application code.
- Supplementary coverage: 97 structured-resource files and 5 Bash scripts indexed.
  Native inventory retained 18 JNI binding candidates and 25 unresolved generated
  UniFFI surfaces. The 262 channel construction records include test fixtures;
  they are not 262 verified runtime channels.
- File/symbol navigation exercised against `MornyeTheme` and
  `rust_backend/Cargo.toml`, including incoming relationships and resource symbols.
- Real Serena 2.1.0 / MCP 2.2.0 smoke checks succeeded for Dart symbol overview
  (`ThemeSettings`), definition (`MornyeTheme`) and references (`MornyeTheme`).
  Used the existing isolated Serena home with cached Dart 3.13.7. Fresh SDK
  provisioning and semantic support for Rust/Kotlin/Java/C++ were not tested in
  this change. A partial two-file snapshot was used for the first reference smoke;
  definition and overview were also checked on the full source snapshot.
- `git diff --check` and Python compilation passed. No Android APK was built;
  application behavior/device testing was outside this tooling-only change.

The saved map is local and ignored. Updating code does not automatically refresh
it. Structural coverage and inferred links do not prove runtime reachability,
correct ABI linkage or absence of dead code. A self-review was performed; no
independent agent review was run for this change.

## Restored code scans

- Full standalone suite after restoring scans: **40 passed, 0 failed, 0 skipped**.
- Real combined Dart scan of `lib/models/theme_settings.dart`: PASS, no selected
  diagnostics. This was a single-file smoke check, not a repository-wide audit.
- Real analyzer positive-control fixture, isolated under ignored `.work`:
  `unused_local_variable` classified as dead-code, `unnecessary_new` as simplifier,
  and `prefer_const_constructors` as optimization; overall status FINDINGS.
- Tests verify generated/vendor/test exclusions, scope containment, category
  separation, compiler-error handling, unavailable coverage, JSON parsing,
  report-only behavior and Rust's explicit 1.99.1/locked Clippy command.
- Rust runner was tested with mocked process output; no live Cargo audit or
  Kotlin/Java/C++ compiler audit was run in this restoration. Cross-language
  bindings are retained as evidence to investigate, not deletion authorization.
