# Ponytail — every modification

For **every modification**, first read and apply the official
[Ponytail skill](.agents/skills/ponytail/SKILL.md) in **full** mode. This includes
small edits, documentation, configuration, scripts, tests and application code,
inside Spec Kit and outside it. Do not wait for the owner to invoke Ponytail.
Current owner instructions override its defaults; answer in the owner's language.

Read the affected source and callers/config/tests; reuse existing code, then
stdlib/platform facilities and installed dependencies before adding new code.
Make the smallest complete change, preserving behavior, validation, error handling,
security, accessibility and audio/hardware requirements. No line-count golf,
speculative abstractions or dependency for a few lines. Check non-trivial logic
with a meaningful targeted test; trivial edits need appropriate lightweight checks.

Before finishing any edit, apply the [Ponytail review](.agents/skills/ponytail-review/SKILL.md)
checklist to the actual diff and connected code. For planned tasks this is part of
the existing review round, not an extra reviewer/commit/gate; the three-round limit
and one-commit rule remain. Small modifications use the direct TOR loop below,
including independent review; self-review cannot substitute for its PASS. Explain actual unchecked areas/material risks
briefly. The same root instructions apply regardless of agent or machine.
Installation details and limitations: [tools/ponytail](tools/ponytail/README.md).

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

GitHub Spec Kit v1.4.0 is installed as repository-local agent skills. Before substantial feature
planning/execution, read [local policy](.specify/project-policy.md) and
[constitution](.specify/memory/constitution.md). Read the applicable skill under
`.agents/skills/speckit-<name>/SKILL.md`: specify → plan → tasks, then implement
only when authorized. Clarify, analyze and checklists are optional. These are
plain instructions for any agent; no particular editor, CLI or slash-command
syntax is required. If skills are not auto-discovered, open their files directly.

Start each planning session by updating/inspecting the map before repository
investigation or technical plan/task drafting. Use its queries and read related
source/configurations; record evidence and limitations in plan.md. Reuse the map
across planning skills while source stays unchanged. If generation/coverage fails,
disclose it and rely only on verified manual tracing for the affected scope.

The policy governs planned work: one planning commit; sequential tasks from T001;
map refresh first in every task, including TOR and final review; implement/check/review/fix,
three review rounds maximum; one commit per completed task; TOR### extras; final
cumulative review/fixes in one final-task commit. Independent task reviews follow
[task-reviewer](.agents/reviewers/task-reviewer.md). For a small low-risk modification,
use [quick-task](.agents/skills/quick-task/SKILL.md): TOR### immediately, no spec/plan,
map refresh first, targeted checks, independent review/fixes (max three rounds),
and one commit containing edits and completion record. Standalone records live in
`.specify/quick-tasks/`; no separate final task. High-risk/growing work uses full
planning. Read-only requests and Git-only pushes do not create TOR records. Planning-only requests never start implementation. Existing audit/navigation
skills stay independent. See [.specify/README.md](.specify/README.md) for provenance,
local adaptations and validation; no old work.py state machine is restored.
