# M002 — Workflow lifecycle tasks

All tasks: map refresh first, Ponytail, checks → independent review/fixes (max three
results) → one completion commit. No APK/application code edits.

- [ ] M002-T001 Implement registry, allocator, completion history and integrity tests.
  - Paths: tools/workflow registry/CLI/tests; .specify/task-registry.json;
    TASK_HISTORY.md; normalize existing native task IDs; feature records.
  - Acceptance: global TOR counter across standalone/mission tasks, unique M/T IDs,
    race-safe reservations, canonical records/history and base-preservation checks.
  - Checks: isolated allocator/concurrency/migration/integrity tests; real validate;
    independent review. Depends: planning commit.
- [ ] M002-T002 Restore environment lifecycle and integrate portable instructions/CI.
  - Paths: tools/workflow environment/CLI/tests/README; tool interpreter discovery;
    .agents/.specify instructions/templates; .github integrity workflow; records.
  - Acceptance: honest status/doctor/setup, local pinned installs, allocator-based
    routing and history completion on every task; required capabilities fail clearly.
  - Checks: full tool suites, real doctor/setup/validate/status, local CI-equivalent
    checks and independent review. Depends: M002-T001.
- [ ] M002-T003 [FINAL] Verify all lifecycle, identity and history changes cumulatively.
  - Paths: all changed feature files as necessary; task log/checkbox/history.
  - Acceptance: cumulative review passes, no unreported limitations or app edits.
  - Checks: map refresh, full feasible tool checks, real helper smoke, source/diff
    boundary and independent cumulative review; all final fixes in one commit.
  - Depends: M002-T001 and M002-T002.
