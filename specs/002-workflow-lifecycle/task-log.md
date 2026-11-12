# M002 task log

Owner authorizes implementation and push. Baseline 97758f89, branch new-workflow.
Map-first planning evidence and bootstrap identity declaration in plan.md. Legacy
M001 native tasks and TOR001 have completion evidence in their existing records.
No additional past tasks are invented. Tasks remain pending until actual validation
and independent review PASS. Planning artifacts form one commit.

## M002-T001 — identity/history implementation (review pending)

First action: full map refresh passed (.work/M002-T001-map.log), 1,782 indexed
sources with no partial/unindexed graph records. Built stdlib registry helpers and
CLI for mission/task reservations, completion, history and validation. Local atomic
locks serialize thread/process reservations; immutable tokens/base counters detect
reassignments after divergent Git work. Disconnected allocation is not claimed safe
without reconciliation/validation.

Real migration imported 4 completed tasks (M001-T001/T002/T003 and TOR001), reserved
this plan's 3 M002 tasks, and normalized existing feature checkbox IDs without
changing prior task evidence/application code. TASK_HISTORY.md contains ID/title
lines only. Real validate PASS: 2 missions, 3 reserved, 4 completed.
Checks: 15 tests PASS, including 18-thread/6-process allocations, global nested/
standalone TOR counters, immutable base ranges, duplicate JSON/records/history,
failed migration containment and completed final-task dependency rules. All source
changes remain tooling/records only. Completion evidence is recorded declarations,
not automated proof that a reviewer actually ran.

M002-T001 review round 1: lifecycle_registry_review NEEDS_FIXES. Malformed task
checkboxes outside the numeric ROW grammar could be ignored. Added candidate-first
checkbox parsing for registered/unregistered feature files and migration, plus
regressions proving malformed IDs fail before migration writes. Suite: 16 PASS;
real registry validation PASS. Round 2 requested; no task commit before review PASS.

M002-T001 independent review round 2: lifecycle_registry_review PASS. Registry,
source records/history, malformed-ID rejection and 16 test results reviewed.
Completion below uses the helper; all allocator/history/migration/record changes
are committed once together, with no separate history-only completion commit.

## M002-T002 — environment/integration (review pending)

First action: full map refresh passed (.work/M002-T002-map.log): 1,785 indexed
sources, 36,763 symbols and 128,385 relationships, no partial/unindexed source
records. Implemented status/doctor/setup for current pinned core tools, explicit
optional Serena, full app-tool availability checks and automatic managed-parser/
semantic-interpreter discovery. Installs are confined to ignored local environments;
venv prefix is verified before pip to prevent global installs through a false venv.

Real setup PASS (installed managed parser venv); second setup PASS/reused=true.
Real doctor --full PASS for required core and available Dart/Rust-Clippy/JDK25/
Android/clang/database prerequisites; optional Serena provisioning not requested,
and no language-server SDK/device/build success is claimed. Real status and
validate against both pre-registry and T001 bases PASS. Tests: 25 helper tests PASS,
64 existing analysis tests PASS with automatic parser discovery (no override).
An initial offline-setup test mock intercepted its own Git preflight; corrected
that fixture isolation, then the full suite passed.

Updated portable policies/skills/templates for allocator use, helper completion,
root history and full mission-prefixed IDs. Added dependency-free GitHub integrity
CI with base preservation. Local CI-equivalent validation, JSON/links/diff/app-source
boundary checks PASS. No application/native files or existing build CI changed.
The new CI has not yet executed remotely; branch-protection settings remain external.

M002-T002 independent review round 1: lifecycle_environment_review PASS. Reviewed
local setup safety/idempotence, required-vs-optional probes, interpreter routing,
canonical IDs/history instructions and CI base protection. Unverified: remote CI,
branch protection, Windows provisioning, optional Serena actual installation and
application/device/ABI builds. Helper completion follows this PASS in the same commit.
