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
- Evidence: advisory operation lock, durable journal and expected Git tree/nonce prove completion before next-task admission; unknown external changes block recovery.
