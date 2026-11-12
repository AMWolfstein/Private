# Native-language audit runners

## Goal

The owner requests Kotlin, Java and C++ code diagnostics in the existing standalone
audit. The default combined audit must invoke real compatible tools, retain scoped
findings and report missing/failed/incomplete coverage honestly. This request
authorizes implementation; it is not planning-only.

## Acceptance

- Kotlin/Java use the project's Android Lint/Gradle configuration and JDK 25.
  One Android Lint invocation is shared when both languages are selected.
- C++ uses clang-tidy with an existing compilation database and real compiler flags;
  missing commands, headers or toolchains are coverage gaps, not clean results.
- Selected diagnostic categories remain dead-code, optimization and simplifier;
  findings are review candidates, never automatic deletion or measured speedups.
- Keep default combined test-quality/coverage checks and existing Dart/Rust behavior.
- Logs/reports remain ignored. Fresh runs cannot consume stale Lint reports.
- Report actual Android variant/compilation configuration and limitations; no claim
  of all-ABI or all-feature dead-code detection.
- No APK builds, application/native source edits, runtime dependencies, global
  agent settings or fixes to discovered application findings.

## Validation

Use isolated parser/process fixtures, the existing full tool suite, real Android
Lint and real clang-tidy where feasible. A missing environment prerequisite may
limit a live smoke check, but must be surfaced rather than faked.
