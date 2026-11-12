# GitHub Spec Kit for this repository

Generated with the official [github/spec-kit](https://github.com/github/spec-kit)
Specify CLI **v1.4.0**, commit `0019fa14d12f45edabc2cc3176c9168a68bd0f97`,
using the Codex skills integration and Bash scripts. See [provenance](upstream.json)
and the [upstream MIT license](LICENSE.spec-kit). This is an adaptation of official
Spec Kit, not a restoration of the previous custom `workflow/` implementation.

## Usage

Read [project policy](project-policy.md) and [constitution](memory/constitution.md).
Codex skill invocation:

```text
$speckit-specify <feature requirements>
$speckit-plan <technical constraints>
$speckit-tasks
$speckit-implement
```

Clarify/analyze/checklist/constitution skills are also installed. Skills are prompts
for the agent, not shell executables or enforcement by themselves. AGENTS.md links
the policy explicitly for agents without automatic skill discovery.

Planning uses normal Spec Kit artifacts under `specs/<number>-<feature>/`:
`spec.md`, `plan.md`, `tasks.md`, optional research/data-model/contracts, and the
local `task-log.md`. Use `SPECIFY_FEATURE_DIRECTORY=specs/<number>-<feature>` when the
ignored `.specify/feature.json` local feature pointer is absent on another checkout.
The feature path does not require renaming the current branch. Do not create a
feature for this installation or reapply archived plans automatically.

## Owner's execution rules

- One commit for all completed planning artifacts. Planning-only means stop there.
- T000 updates the CodeGraph map and commits its completion/evidence once.
- T001 implements/checks/reviews; every later task starts with a map refresh.
- Sequential task → checks → independent review → fixes/revalidation/review.
  Maximum three review results; stop/report if the third still is not PASS.
- One commit per completed task including its fixes/log/checkbox; no interim commits.
- Owner-requested extras become TOR### with the same loop and one commit each.
- The last task reviews the cumulative T/TOR change; all final fixes/evidence are
  one final-task commit, with the same review limit.
- No automatic feature implementation from a planning request, no repeated approval
  ceremonies between authorized tasks, no automatic merge/force push, no APK unless
  requested. Keep unrelated edits safe and report missing validation honestly.

Small isolated low-risk changes can stay direct. These rules govern planned work;
CodeGraph, optional Serena and the combined audit remain standalone tools. No
work.py state machine, fingerprint gate or old workflow tasks are restored.

## Official assets and local changes

Official templates and six Bash scripts are retained. All nine generated skill
files identify the local policy precedence. `speckit-implement` is adapted for the
bounded per-task loop. Task generation uses
[the local override](templates/overrides/tasks-template.md), preserving the stock
upstream task template for provenance. The constitution is initialized for this
Android repository. A read-only [task reviewer](../.agents/reviewers/task-reviewer.md)
supports both ordinary and cumulative reviews.

The bundled YAML workflow's two intermediate approval gates are removed; use direct
Codex skills here. The upstream generic workflow runner's declared integration
support does not include Codex, so running that optional runner is not claimed
supported. `$speckit-converge` may inspect the final task; its upstream automatic
append/implement/reconverge cycle is superseded by the local bounded loop.

Generated integration manifests retain hashes of the original upstream assets;
local edits are intentional. These are install provenance, not freshness/approval
gates. Do not run `specify init --force` or a blind update over this repository:
compare against pinned upstream, preserve these adaptations, and review the diff.
No Spec Kit extension, global Codex config or application dependency was installed.

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
