# Code navigation tools

Standalone **CodeGraph 1.6.2**, resource/Bash/native adapters, and optional
**Serena 2.1.0** verification. No tasks, planning, review gates, fingerprints,
hooks or application dependencies. Run commands from the repository root.

## Installation

Node/npm and Python 3.10+ are required for the graph adapter. Python 3.11+
is recommended; Serena 2.1.0 requires Python 3.11+.

```sh
npm ci --prefix tools/codegraph --ignore-scripts --no-audit --no-fund
python3 -m venv .work/code-tools-python
.work/code-tools-python/bin/python -m pip install -r tools/codegraph/requirements.txt
python3 tools/codegraph/codegraph_adapter.py version
```

Optional semantic verifier, in a separate environment:

```sh
python3 -m venv .work/serena-python
.work/serena-python/bin/python -m pip install -r tools/codegraph/requirements-serena.txt
export SERENA_PYTHON="$PWD/.work/serena-python/bin/python"
python3 tools/codegraph/code_tools.py serena version
```

Dependencies never download during an ordinary graph update. Serena language
servers can download SDKs/server dependencies on first use; they require compatible
toolchains and network access. Language support is reported by Serena, not presumed.
No global agent/MCP configuration is installed. On this Android project use the
configured Flutter/Dart SDK, JDK 25 and Rust 1.99.1; avoid Serena's older default
Dart SDK. A new isolated home defaults to Dart 3.13.7 (override with
`SERENA_DART_SDK_VERSION` before its first use) and disables Rust Cargo build scripts
and proc macros. Existing home settings are preserved; verify these settings in
`SERENA_HOME/serena_config.yml` if reusing a home. Semantic references are separate from a complete
call graph and do not replace compiler checks.

## Update the map

```sh
export CODEGRAPH_SHELL_PYTHON="$PWD/.work/code-tools-python/bin/python"
python3 tools/codegraph/code_tools.py update
```

One command collects CodeGraph symbols/relationships, structured resource links,
parse-only Bash evidence, JNI/UniFFI boundary candidates and literal Flutter
platform channels. Outputs live in ignored `.work/codegraph/`; the source checkout
is never executed by these graph/resource/shell collectors. CodeGraph runs on a
private source mirror. Missing Bash dependencies stay explicit coverage gaps.

Default inventory: existing tracked and unignored untracked source files reported
by Git, filtered to the supported extensions. Excludes `.git`, `.work`,
`.dart_tool`, `node_modules`, `build`, `target`, `vendor`, `third_party`, and
`__pycache__` directories. The saved `scope` lists inputs and exclusions. Tests and
tracked generated sources are included. A deleted tracked file is ignored.

For a limited region (replaces, rather than merges with, the saved map):

```sh
python3 tools/codegraph/code_tools.py update --paths \
  lib/models/theme_settings.dart lib/theme/mornye_theme.dart rust_backend/Cargo.toml
```

Resources currently cover JSON, ARB, XML and TOML. YAML and Gradle/CMake semantics
are unsupported. Native matching uses only simple enclosing JVM owners and literal
JNI names/macros; nested/overloaded/dynamic cases remain unresolved. Channel records
are literal construction candidates, not proven connected handlers or runtime calls.
No generic Dart-to-Rust call is invented from matching names.

## Ask about a file or symbol

```sh
python3 tools/codegraph/code_tools.py query --file lib/theme/mornye_theme.dart
python3 tools/codegraph/code_tools.py query --symbol MornyeTheme --limit 30
```

Returns symbols, incoming/outgoing relationships, resource/native/channel evidence,
coverage and totals before truncation. Matching symbol names are exact (simple or
qualified); ambiguous matches remain separate. Definitions carry file/line locations.
The saved map is a snapshot: **run update after edits**. No fingerprint or hidden
freshness gate exists. Low coverage or absent references never proves dead code.

Optional language-server verification of the same indexed snapshot:

```sh
python3 tools/codegraph/code_tools.py serena symbols --file lib/theme/mornye_theme.dart
python3 tools/codegraph/code_tools.py serena definition --file lib/theme/mornye_theme.dart --symbol MornyeTheme
python3 tools/codegraph/code_tools.py serena references --file lib/theme/mornye_theme.dart --symbol MornyeTheme
```

Only those read operations are exposed. Serena uses a read-only project on the
private mirror, with dashboard/GUI disabled and an overall timeout (default 120s).
Its configuration/caches/logs default to `.work/serena/home`; `SERENA_HOME` can point
to another isolated home containing language-server settings. Do not run a graph
update and a Serena query concurrently on the same mirror. Partial snapshots can
miss dependencies; snapshot paths in Serena results must be mapped to the source
checkout. Files/toolchains absent from the snapshot produce limited semantic evidence.

## Low-level adapter and tests

The original `codegraph_adapter.py version` and `extract --request FILE --out FILE`
remain available. Requests contain `root` (absolute), `files` (relative source paths)
and optional `auxiliary` files. Default cache: `.work/codegraph/`; `CODEGRAPH_CACHE`
can override it with an absolute path. CLI discovery checks local `node_modules`,
then `.work/tools/node_modules`, then PATH; `CODEGRAPH_COMMAND` overrides with a
JSON argv list. CLI telemetry is disabled. Relationships retain extracted/inferred
labels; ABI signatures and runtime behavior are never claimed verified.

```sh
CODEGRAPH_SHELL_PYTHON="$PWD/.work/code-tools-python/bin/python" \
  python3 -m unittest discover -s tools/codegraph -p 'test_*.py' -v
```

Tests include real CodeGraph parsing/incremental synchronization, resource/Bash
regressions, JNI false positives, input containment, navigation and the Serena read
allowlist. Missing real tools produce explicit skips. Real Serena/LSP smoke checks
are separate because SDK/server availability varies by machine.
