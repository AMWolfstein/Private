# Tasks: native-language audit runners

All tasks begin with CodeGraph refresh and scope/coverage inspection. Every task
uses checks → independent review/fix (three results maximum) → one commit. No APK.

- [x] T001 Implement native diagnostic adapters and focused tests.
  - Paths: tools/codegraph/native_audit.py, android-audit.init.gradle,
    test_native_audit.py; task log and this checkbox.
  - Acceptance: fresh contained Android Lint parsing and safe shared runner;
    clang-tidy with real compile commands and explicit uncovered-file/errors.
  - Checks: focused adapter tests, syntax checks, tool CLI compatibility/live
    smoke commands where feasible; independent task review.
  - Depends: planning commit.
- [x] T002 Connect runners/categories/reporting and document usage/limits.
  - Paths: tools/codegraph/audit.py, audit-config.json, test_audit.py, README.md,
    VALIDATION.md, .agents/skills/audit/SKILL.md, task log and this checkbox.
  - Acceptance: Kotlin/Java execute once together; C++ reaches adapter; scoped
    categories and status retain limitations; existing combined audit preserved.
  - Checks: full tool tests; live selected native-language audit; scope/diff checks;
    independent task review. Depends: T001.
- [x] T003 [FINAL] Review the cumulative native-audit change and resolve findings.
  - Paths: all T001/T002 files and feature records as required by final findings.
  - Acceptance: cumulative spec/plan review passes; actual validation/limitations
    recorded, source tree clean and application sources unchanged.
  - Checks: map refresh, full feasible tool checks and targeted reruns only if
    fixes require them; independent cumulative review; one final commit.
  - Depends: T001 and T002.

Owner extras: none. Publish only if requested; never merge or force-push.
