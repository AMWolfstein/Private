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
