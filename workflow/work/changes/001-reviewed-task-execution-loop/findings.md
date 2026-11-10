# Review findings

### F-001 [design r1, both reviewers] Protect unrelated tracked changes
- Severity: major
- Status: fixed
- Evidence: plan enforcement details reject tracked staged/unstaged changes at start and protect unmapped baseline untracked files.

### F-002 [design r1, goldfish-reader] Define zero-check task evidence
- Severity: major
- Status: fixed
- Evidence: explicit NOT_REQUIRED identity-bound task evidence; NO_CHANGES never creates runner PASS; T000 map and final cumulative review remain required.

### F-003 [design r1, goldfish-reader] Define blocked-task recovery
- Severity: major
- Status: fixed
- Evidence: explicit owner-instruction resume creates a new cycle, preserves old rounds, and cannot run automatically.

### F-004 [design r1, design-critic] Bind evidence to task requirements
- Severity: major
- Status: fixed
- Evidence: before/after requirement identity stored with exact check selection; packet/review/commit revalidate it even without source changes.

### F-005 [design r1, design-critic] Reconcile interrupted commits
- Severity: major
- Status: fixed
- Evidence: advisory operation lock and committed Git tree/nonce verification prove completion before next-task admission; interrupted ordinary Git leaves waiting_commit and preserves all source/index data. Commit automation/journaling was removed to keep scope small.

### F-006 [code T001 r1, loop_t001_code_review] Verify full planning checkpoint
- Task: T001
- Severity: major
- Status: fixed
- Evidence: committed planning state/transaction and all artifact hashes are verified; partial-plan and complete-plan Git integration tests pass.

### F-007 [code T001 r1, loop_t001_code_review] Verify task records in the same commit
- Task: T001
- Severity: major
- Status: fixed
- Evidence: completion captures artifact hashes and verifies them in the immediate child commit; partial-task-commit test rejects omitted records.

### F-008 [code T001 r2, loop_t001_code_review] Reject unrelated staged records
- Task: T001
- Severity: major
- Status: fixed
- Evidence: completion preparation and committed-tree verification reject records outside this change; regression test covers staging after task start and after completion preparation.

### F-009 [code T002 r1, loop_t002_review] Small-record governance conflict
- Task: T002
- Severity: major
- Status: fixed
- Evidence: constitution IX now requires minimal task/state/log records for small changes while exempting planning.

### F-010 [code T002 r1, loop_t002_review] Old four-round guidance
- Task: T002
- Severity: major
- Status: fixed
- Evidence: quality guide now caps task reviews at three per explicit owner-authorized cycle; design-review policy remains separate.
