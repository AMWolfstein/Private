# Spec-driven work inside the Sistrum workflow

GitHub Spec Kit contributes behavioral specifications, material clarification, traceable tasks, consistency analysis and convergence. This package adapts those concepts into its existing skills. It does not install `specify-cli`, expose `/speckit-*` commands or claim compatibility with Spec Kit extensions/hooks.

## One system of authority and records

| Spec Kit concept | Sistrum implementation |
|---|---|
| Constitution | Existing `AGENTS.md`, `architecture.md`, `quality.md`, accepted migration decisions and contracts; no duplicate rulebook |
| Specify / clarify | `sistrum-spec`, a behavior spec and a short decisions/unknowns section |
| Plan | Existing `sistrum-design` and optional linked design document; technical approach lives here |
| Tasks | Existing task record, with stable requirement/task IDs, dependencies and verification mapping |
| Checklist | Review of requirements clarity/completeness, kept in the spec; not a test result |
| Analyze | Read-only consistency review before substantial implementation |
| Implement | Existing implement/port skills and risk-based checks |
| Converge | Final comparison of actual code/evidence against intent; append only missing in-scope work to the same task record |

Current user instructions and accepted owner decisions retain precedence. Rules cannot be weakened silently to match a proposed implementation. An intentional rule change is recorded as a decision and propagated to affected contracts/tasks. The owner-approved Media3 sequence remains binding.

## Right-sized artifacts

- **Small clear fix or edit:** acceptance statement plus relevant checks. No separate spec/design required. A bug with a clear expected behavior stays in the bug-fix path.
- **Nontrivial feature:** `workflow/specs/<id>.md` + `workflow/tasks/<id>.md`. A short technical plan can live in the task itself.
- **Architecture or migration batch:** the same two records, plus `workflow/designs/<id>.md` only when needed for the architectural design. Reference existing batch decisions instead of reproducing the migration plan.
- **Read-only audit:** inspect applicable existing specs and code. Do not manufacture a feature spec or start implementation just because analysis found a gap.

No folders are required until a real task needs them. Existing task records can add requirement IDs in place; do not regenerate completed work or renumber existing IDs. Do not introduce upstream's automatic branch naming, duplicate `specs/` trees, separate tracking databases or new dependencies.

## Readiness and completion

Before a substantial implementation, verify that the applicable requirements have a planned implementation or documented existing satisfaction, that checks cover the acceptance cases, and that task prerequisites are acyclic and match migration order. Domain/transport types, resource ownership and failure semantics belong in the linked technical design/contracts. Any new module must justify its present responsibility.

Before completion, verify the outcome, not the number of checked boxes. Map requirements to current code, review findings and current verification evidence. Unknown device behavior remains pending. Deferrals require a reason and authority; deferring a requirement does not make the original requested scope complete. Findings are recorded with the existing evidence/confidence rules.

These semantic checks are performed by the agent/reviewer. `scripts/workflow.py validate` checks package structure only, and `route` provides suggested skills only; neither tool parses prose to prove requirements are fulfilled. CI command success is separate from requirements readiness or feature acceptance.

## Porting already-tested DSP/codecs

The owner reports that SistrumKotlin's tests work on their phone. Preserve that as owner-reported source validation, with revision/device details where available; do not relabel the source as untested or pretend those results were rerun here. Destination integration still needs its own evidence.

A port spec states the source revision, preserved behaviors, intentional differences, chosen module disposition (reuse / adapt / restructure / exclude) with evidence, and applicable oracle/host/device checks. "Reuse as is" is a valid outcome. Do not require file splitting or alter DSP arithmetic to satisfy the process. Transport/Gradle/fixture adaptation and algorithm changes should remain distinguishable in the plan and evidence.

## Deliberate adaptations from upstream

- Sistrum tests are selected by risk and contracts; upstream task-template wording that tests are optional does not waive data-integrity, audio or lifecycle verification.
- User authorization already given for implementation is not re-requested for every artifact or section. Unresolved consequential decisions remain the owner's.
- Independent review stays read-only. The orchestrator updates the existing task record after validating findings.
- Convergence is bounded by the existing review loop. Lack of a device is a verification gap, not a reason to continually rewrite working code.
- No unreviewed extension hooks, marketplace downloads, automatic pushes or workflow daemons are introduced.
