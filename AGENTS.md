# Repository tools

Standalone code-navigation tools live in [tools/codegraph/README.md](tools/codegraph/README.md).
Use `python3 tools/codegraph/code_tools.py update` to refresh the source map, then
`query --file PATH` or `query --symbol NAME` to navigate it. Serena can optionally
verify definitions/references. Coverage gaps and inferred relationships are not
proof of dead code. These tools impose no tasks, planning or review gates.

Application build and test commands are documented in CONTRIBUTING.md.
