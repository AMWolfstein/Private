# Task <id>: <goal>

Status: PLANNED | IN_PROGRESS | IMPLEMENTED_PENDING_VERIFICATION | COMPLETE | BLOCKED

## Scope
Goal and acceptance behavior:
Out of scope:
Mode: small | fix | feature | architecture | migration | audit
Spec reference (substantial features/ports only):
Technical design reference (if needed):
Affected callers/domains and discovery evidence:
Source revision / working-tree fingerprint:
Migration batch and prerequisites (if any):

## Plan
Each step: change → meaningful check → completion evidence. For a clear small fix,
a short plan is enough; use the table for spec-driven work. Keep one task list.

| Task ID | Requirement IDs or necessary enabling purpose | Change and real/proposed paths | Depends on | Check | State |
|---|---|---|---|---|---|
| T1 | <R1 or enabling purpose> | <bounded work> | <IDs or none> | <meaningful validation> | PLANNED |

States: PLANNED / IN_PROGRESS / IMPLEMENTED_PENDING_CHECK / VERIFIED / BLOCKED.
Do not mark a task VERIFIED merely because its implementation is present.
Parallel eligibility (if useful): explain independent files/resources and dependencies;
this does not itself authorize spawning agents.

## Consistency and delivery (spec-driven work)

Before execution: contradictions, unmapped requirements, dependency order and resolution:

| Requirement | Task IDs / existing implementation | Acceptance check and evidence | Current outcome / gap |
|---|---|---|---|
| <R1> | <T1 or source reference> | <planned check, then actual result/revision> | <pending/verified/missing> |

Final convergence reviewer/revision:
Missing in-scope work: append new stable task IDs to the Plan; preserve old IDs.
Unresolved verification/device gates:
Do not rewrite the spec to match accidental behavior or call deferred scope complete.

## Decisions and findings
Decision references:
Finding IDs, status and counter-evidence:
Independent reviewer/context, reviewed revision and limitations:

## Verification
Exact commands, exit/results, evidence paths and fingerprint:
Unrun checks/device requirements:
No claim of device success from compilation or mocks.

## Handoff
Completed:
Next executable action:
Blockers/risks:
Update this record instead of writing another overlapping progress file.
