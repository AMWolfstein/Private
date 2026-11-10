# Reviewed task execution loop

Status: Accepted
Input: Owner approved retaining planning, one planning commit, then map-driven implementation/review/fix loops with one commit per task, TOR### requests, cumulative final review, and a hard stop after three unsuccessful reviews. Fingerprints remain internal; reports/progress do not invalidate checks.
Binding decisions: current conversation supersedes old execution/commit separation rules. No APK or push requested. Preserve unrelated extensions work/stash.

## User scenarios
### Story 1: Complete one task at a time (P1)
Acceptance: Given an approved committed plan, When execution begins, Then T000 refreshes the map and subsequent tasks use current map context, pass relevant checks and independent review before completion and one commit.
### Story 2: Fix review findings (P1)
Acceptance: Given a dirty review, When changes are corrected, Then affected checks and review repeat within the same task and commit; a third dirty review stops execution and reports unresolved findings.
### Story 3: Add owner requests (P1)
Acceptance: Given a request outside the written queue, When it is recorded as TOR###, Then it runs through the same loop before the pending final review.
### Story 4: Verify the entire result (P1)
Acceptance: Given all implementation tasks committed, When the final task runs, Then it reviews the cumulative change and all completed tasks; final fixes receive one reviewed commit.

## Requirements
- FR-001: Preserve planning documents/design review; commit all planning artifacts together once.
- FR-002: Require T000 and a final [FINAL] task; refresh the map before each task and generate task context.
- FR-003: Require fresh relevant checks and a clean independent review before marking a task complete; commit implementation, tests, fixes and records together once.
- FR-004: Stop and report after three dirty reviews; reject a fourth review and prohibit later tasks/commit until the owner resolves the block.
- FR-005: Create ordered TOR001, TOR002 requests from explicit owner instructions without rewriting completed tasks.
- FR-006: Final review/check selection must cover the cumulative change, not just the last task's diff.
- FR-007: Retain automatic code/evidence fingerprints; exclude reports/progress, but detect source/check-policy/plan changes affecting review validity.
- FR-008: Small changes skip planning and retain map/check/review/task commit requirements. Classify by behavior, boundaries and data impact, not line counts.
- FR-009: Preserve readable legacy records; new execution must not require project-wide build/review/ship transitions, repeated fresh commands or separate record commits.
- FR-010: Preserve existing check commands; offer check default/--full and truthful no-changes output without fabricating PASS evidence.

## Edge cases
Map unavailable, source changed during checks/review, pre-existing untracked files, unrelated staged files, failed commits, duplicate IDs, edited completed tasks, TOR after final completion, stale plan/check policy, third review clean vs dirty, no mapped tests, and no source fixes in final review.

## Success criteria
- SC-001: Throwaway-repository tests enforce review caps, stale-evidence rejection, ordering and actual Git commit boundaries.
- SC-002: Existing workflow/parser/graph regression tests pass; app code is unchanged.

## Out of scope
Application behavior, APK generation, remote publishing and restoring the extensions stash.

## Assumptions
Map-only/review-only tasks may commit genuine completion/evidence records; never create empty Git commits. Review labels are recorded human/agent judgments, not machine proof of reviewer independence. Small records may be minimal, with no spec/plan files.
