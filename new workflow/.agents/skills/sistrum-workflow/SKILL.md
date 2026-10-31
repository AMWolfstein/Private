---
name: sistrum-workflow
description: "Automatic entry for every Sistrum coding, debugging, porting or review task; choose focused skills without requiring named invocation."
---

# Orchestrator

1. Read `workflow/STATE.md`, `workflow/architecture.md` and the relevant accepted decisions. Inspect the actual working tree; preserve unrelated work. On bootstrap, inventory tools, app modules, tests and reference checkouts; do not assume they exist. Configure `workflow/verification.json` from actual commands and update STATE. Do not mark app initialization complete while only this starter exists.
2. Restate the goal briefly. Trace callers, data flow and boundary endpoints before changing behavior. Use a fresh available code graph first if the destination provides one; otherwise targeted symbol/import searches. No graph tool is required. Do not invent edges.
3. Select scope by risk: trivial/clear fix → implementation + check (independent code review for nontrivial fixes); nontrivial feature → spec + plan + consistency review + implementation + checks/review + convergence; architecture/migration → spec + design + independent consistency/design review + implementation/port + checks/review + convergence; audit → review only unless edits requested. `scripts/workflow.py route` is advisory. Override routing from the real scope; a request explicitly limited to review remains read-only even when it mentions a future port.
4. Load `.agents/skills/sistrum-{spec,design,implement,port,review,verify}/SKILL.md` only as needed. A skill is guidance, not another autonomous process. One orchestrator owns task state; reviewers are read-only and never spawn more reviewers.
5. For substantial work, copy `workflow/templates/task.md` into `workflow/tasks/<id>.md`. Keep one task record; spec/design artifacts link to it rather than creating additional task lists. Follow `workflow/spec-driven.md` for requirement-to-task/check mapping and selective clarification. Scope, prerequisites, verification and open decisions must be explicit. For migrations, check `workflow/migration.md` and record the selected transition mode.
6. Execute within authorization, with updates at meaningful milestones. Do not ask the user to choose skills. Ask only when missing information materially blocks a consequential decision. Already accepted decisions are not reopened by a reviewer preference.
7. Keep design and code reviews separate. Usually one isolated reviewer; up to two specialists for crossing risk domains, never a blanket fan-out. A review requires source reading, not agreement with the author. If independence is unavailable, label self-review and leave the required independent gate pending.
8. After verification, compare current implementation against the linked requirements (convergence), then update task and STATE with evidence and the next action. Add only confirmed missing in-scope work, using the existing bounded review loop. Report result, checks, unresolved risks and unrun device work. COMPLETE requires relevant acceptance gates; tools cannot assign it from exit codes alone. Push only under current user authorization.

Fresh sessions resume from records, then validate code/evidence freshness. Do not treat elapsed time, missing results or a failed review runner as approval.
