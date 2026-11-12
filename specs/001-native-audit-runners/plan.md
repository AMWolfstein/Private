# Implementation plan: native-language audit runners

## Repository evidence

- Baseline: bd5f45b5, branch new-workflow, clean tree before this request.
- Planning-start map: successful full update, 1,780 indexed source files, 36,646
  symbols, 128,085 relationships; no CodeGraph partial/unindexed source records.
  Scope/exclusions are saved in ignored `.work/codegraph/map.json`. Gradle/CMake
  semantic interpretation remains outside map coverage.
- Inspected audit.py, audit-config.json, test_audit.py and test-quality integration;
  queried audit.py in the current map (18 symbols / 52 relationships).
- Actual Android config: app module, compile SDK 37, JDK/JVM 25, NDK 30.0.16248370,
  arm64-v8a, CMake 4.1.2; no application flavor assumed. Lint task graph is being
  checked before selecting its command. Existing CMake compile databases cover
  Android debug/profile/release and a partial host decoder test target.
- Existing NDK clang-tidy is available. Android Gradle wrapper exists. Shared
  Android runner must not launch twice for Kotlin/Java. C++ must declare partial
  coverage if selected files lack usable commands; no synthetic include flags.

## Design

Add a standalone native diagnostic adapter beside audit.py plus a small Gradle
init script configuring report output in memory. Dispatch shared Kotlin/Java once,
parse fresh Android Lint XML with path containment and issue metadata, filter to
selected files, and keep failures/unsupported detection explicit. Use a configured
or discovered compilation database for clang-tidy; report selected/covered files
and configuration. Invoke without automatic fixes. Keep third-party/generated
inputs protected and avoid shell command interpolation. No app Gradle/CMake edits.

## Validation and baseline

Existing tool suite is the baseline; record its result in task-log.md. New tests
cover XML/path/escaping/stale-output/error handling, shared invocation and native
compile-command gaps. Run live Lint/clang-tidy where possible without APK packaging.
Compilation warnings/findings are evidence, not an instruction to change app code.

## Constitution check

Tooling-only scope; preserve app behavior and native contracts. No app dependency
install. One planning commit, map refresh first per task, independent read-only
review with at most three results and one commit per task. T003 is final cumulative
review. A tool setup limitation remains recorded; no device/all-ABI claims.
