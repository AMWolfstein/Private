# Repository tools

Standalone code-navigation tools live in [tools/codegraph/README.md](tools/codegraph/README.md).
Use `python3 tools/codegraph/code_tools.py update` to refresh the source map, then
`query --file PATH` or `query --symbol NAME` to navigate it. Serena can optionally
verify definitions/references. `audit` combines code diagnostics, test-quality inspection and coverage-gap
hints in one report; `--kind` can narrow it. It does not fix sources or run tests. Coverage gaps and inferred relationships are not
proof of dead code. These tools impose no tasks, planning or review gates.

Application build and test commands are documented in CONTRIBUTING.md.

For code navigation, use the [code-navigation skill](.agents/skills/code-navigation/SKILL.md).
For code, optimization, simplification, test-quality or coverage-gap audits, use the
[audit skill](.agents/skills/audit/SKILL.md). Review guidance is in
[code-auditor](.agents/reviewers/code-auditor.md); it does not automatically run an
independent reviewer. These are standalone instructions, not a task workflow.

# Spec Kit planning and task execution

GitHub Spec Kit v1.4.0 is installed with Codex skills. Before substantial feature
planning/execution, read [local policy](.specify/project-policy.md) and
[constitution](.specify/memory/constitution.md). Use `$speckit-specify`,
`$speckit-plan`, `$speckit-tasks`, then `$speckit-implement` only when implementation
is authorized. `$speckit-clarify`, `$speckit-analyze` and checklists are optional.

Start each planning session by updating/inspecting the map before repository
investigation or technical plan/task drafting. Use its queries and read related
source/configurations; record evidence and limitations in plan.md. Reuse the map
across planning skills while source stays unchanged. If generation/coverage fails,
disclose it and rely only on verified manual tracing for the affected scope.

The policy governs planned work: one planning commit; sequential tasks from T001;
map refresh first in every task, including TOR and final review; implement/check/review/fix,
three review rounds maximum; one commit per completed task; TOR### extras; final
cumulative review/fixes in one final-task commit. Independent task reviews follow
[task-reviewer](.agents/reviewers/task-reviewer.md). Small low-risk edits may remain
direct. Planning-only requests never start implementation. Existing audit/navigation
skills stay independent. See [.specify/README.md](.specify/README.md) for provenance,
local adaptations and validation; no old work.py state machine is restored.
