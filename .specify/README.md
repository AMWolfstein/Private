# GitHub Spec Kit for this repository

Generated with the official [github/spec-kit](https://github.com/github/spec-kit)
Specify CLI **v1.4.0**, commit `0019fa14d12f45edabc2cc3176c9168a68bd0f97`,
using the official skill renderer and Bash scripts. See [provenance](upstream.json)
and the [upstream MIT license](LICENSE.spec-kit). This is an adaptation of official
Spec Kit, not a restoration of the previous custom `workflow/` implementation.

## Usage

Read [project policy](project-policy.md) and [constitution](memory/constitution.md).
Agent-neutral entrypoints (read each file and follow its instructions):

1. `.agents/skills/speckit-specify/SKILL.md` — feature requirements.
2. `.agents/skills/speckit-plan/SKILL.md` — technical planning.
3. `.agents/skills/speckit-tasks/SKILL.md` — task generation.
4. `.agents/skills/speckit-implement/SKILL.md` — authorized implementation.

Clarify/analyze/checklist/constitution skills are also installed. Skills are prompts
for the agent, not shell executables or enforcement by themselves. AGENTS.md links
the policy explicitly for agents without automatic skill discovery. Any agent on any machine can follow the same files;
slash/dollar command registration is optional. Rendering metadata in upstream.json
records how the official assets were generated, not a restriction on who can use them.

Planning uses normal Spec Kit artifacts under `specs/<number>-<feature>/`:
`spec.md`, `plan.md`, `tasks.md`, optional research/data-model/contracts, and the
local `task-log.md`. Use `SPECIFY_FEATURE_DIRECTORY=specs/<number>-<feature>` when the
ignored `.specify/feature.json` local feature pointer is absent on another checkout.
The feature path does not require renaming the current branch. Do not create a
feature for this installation or reapply archived plans automatically.

## Map-first planning

Before investigating the repository or drafting a technical plan/tasks, update the
map and inspect its scope/coverage. Query relevant files/symbols, then read related
source, native registrations, configuration and tests. Record a Repository evidence
section in plan.md; the local plan-template override includes the required fields.
Reuse this map across the same planning session while source is unchanged. Refresh
on source changes/new sessions, not every command. If generation fails or coverage
is incomplete, disclose it and manually verify relevant source instead of guessing.
No extra task/commit/approval or fingerprint gate is added. Task-start map refresh
is a separate rule and remains mandatory for every T/TOR/final task.

## Owner's execution rules

- One commit for all completed planning artifacts. Planning-only means stop there.
- Mission tasks are allocated as M###-T### (local T counter starts at 001). The first action of every task, including TOR and [FINAL],
  is map refresh; no dedicated map task or map-only commit exists. A failed refresh
  stops the task with an explicit limitation.
- Sequential task → checks → independent review → fixes/revalidation/review.
  Maximum three review results; stop/report if the third still is not PASS.
- One commit per completed task including its fixes/log/checkbox; no interim commits.
- Owner-requested feature extras use M###-TOR### from the global TOR pool, with the same loop and one commit each.
- The last task reviews the cumulative T/TOR change; all final fixes/evidence are
  one final-task commit, with the same review limit.
- No automatic feature implementation from a planning request, no repeated approval
  ceremonies between authorized tasks, no automatic merge/force push, no APK unless
  requested. Keep unrelated edits safe and report missing validation honestly.

Small isolated low-risk changes use the [direct TOR skill](../.agents/skills/quick-task/SKILL.md):
a short `.specify/quick-tasks/TOR###.md` record, no spec/plan, map-first execution,
checks, independent review/fix with three results maximum, and one commit including
the completion record. No separate final task or planning commit. High-risk/growing
work moves to full planning. Read-only/Git-only operations create no TOR record.
The full feature rules above govern planned work;
CodeGraph, optional Serena and the combined audit remain standalone tools. No
work.py state machine, fingerprint gate or old workflow tasks are restored.

## Official assets and local changes

Official templates and six Bash scripts are retained. All nine generated skill
files identify the local policy precedence. `speckit-implement` is adapted for the
bounded per-task loop. Planning uses [the evidence-aware override](templates/overrides/plan-template.md).
Task generation uses
[the local override](templates/overrides/tasks-template.md), preserving the stock
upstream task template for provenance. The constitution is initialized for this
Android repository. A read-only [task reviewer](../.agents/reviewers/task-reviewer.md)
supports both ordinary and cumulative reviews.

The bundled YAML workflow's two intermediate approval gates are removed; use direct
skills directly here. The optional upstream executable workflow runner has host-specific integration
requirements and is not the portable entrypoint; no support for every host is claimed. `speckit-converge` may inspect the final task; its upstream automatic
append/implement/reconverge cycle is superseded by the local bounded loop.

Generated integration manifests retain hashes of the original upstream assets;
local edits are intentional. These are install provenance, not freshness/approval
gates. Do not run `specify init --force` or a blind update over this repository:
compare against pinned upstream, preserve these adaptations, and review the diff.
No Spec Kit extension, global agent configuration or application dependency was installed.

## Tool availability

Already generated skills/templates/Bash scripts need Git, Bash and Python 3
(or jq for some JSON helpers). Ordinary planning does not need a globally installed
Specify CLI. If maintaining/upgrading Spec Kit, use Python 3.11+ and an isolated
CLI install pinned to `specify-cli==1.4.0`; installation for this change was local
under ignored `.work/specify-cli/` using the pinned upstream source.

## Validation

See [validation evidence](VALIDATION.md) for the actual scaffold smoke tests and
retained analysis-tool regression results. No feature tasks or APK builds are
executed just by installing this setup.


## Preparation, identities and root history

[Workflow helpers](../tools/workflow/README.md) provide status, doctor and setup
for current tools. Use the allocator for every mission/task ID; no handwritten
numbers. Ordinary IDs are M###-T###; M###-TOR### and standalone TOR### share one
global TOR counter. The tracked registry preserves unfinished reservations too.
After actual checks/independent PASS, task complete updates the canonical record,
registry and root [TASK_HISTORY.md](../TASK_HISTORY.md). Include these in the same
planning/task commit as appropriate; pending tasks never appear as completed.
Validate before commit/push. Same-checkout locks do not serialize disconnected
clones: reconcile Git state and pass base-preservation validation. GitHub integrity
checks detect conflicts; external branch protection makes them merge requirements.
