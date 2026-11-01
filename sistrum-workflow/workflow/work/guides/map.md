# Project code map and bounded context

The workflow uses **CodeGraph 1.6.2** (`@colbymchenry/codegraph`, MIT), not Graphify.
The public commands, assurance gates, reviewed declarations, bridge enrichment and bounded context renderer
remain in this workflow. CodeGraph supplies AST symbols and resolver relationships; Python merges evidence.
No `explore` response is injected wholesale into agent context.

## Install once per environment

Python 3.10+ and Git run the workflow. For real structural analysis install the pinned CodeGraph CLI. A
standalone distribution bundles its runtime; the npm distribution also ships a platform bundle. Follow the
upstream platform requirements. There is no requirement to build Rust or install Graphify for this integration.

A project-local npm installation (requires npm for installation):

```sh
npm install --prefix .work/tools --no-audit --no-fund @colbymchenry/codegraph@1.6.2
```

Set `extractor.command` in `workflow/work/map.json` to the argv for your platform, for example
`[".work/tools/node_modules/.bin/codegraph"]` on Linux/macOS, or put the CLI on PATH and retain `["codegraph"]`.
A command containing a relative path resolves from the repository root, including version probing. Arguments
are an argv list, never shell code. Use the appropriate executable on Windows; this platform has not been tested.
The workflow never runs an agent installer, adds MCP settings or downloads tools automatically.
CodeGraph telemetry is disabled in the adapter environment.

`extractor.enabled` is true by default. Missing tools, disabled extraction and unverified versions produce a
clearly labelled limited companion map with low-confidence declaration candidates and bridge/import metadata;
they never fabricate call edges. Version mismatch is not silently accepted. Change the pin only after the
real-engine tests pass. A current limited map is current input state, **not** complete semantic analysis.

## Commands, from the repository root

```sh
python3 workflow/scripts/work/work.py map build
python3 workflow/scripts/work/work.py map update
python3 workflow/scripts/work/work.py map status
python3 workflow/scripts/work/work.py map coverage
python3 workflow/scripts/work/work.py context "task words" --file lib/path.dart
python3 workflow/scripts/work/work.py context "task words" --symbol seek --budget 2500
python3 workflow/scripts/work/work.py context --expand bridge:channel/name
```

`build` resets the private engine cache. `update` synchronizes additions, edits, renames and deletions using a
persistent private source mirror and CodeGraph's incremental sync. Unchanged source mtimes are preserved.
`status` is read-only. `coverage` refreshes the map and returns per-file diagnostics, per-language coverage,
unresolved-reference counts, excluded candidate paths and native-binding evidence. These commands use the
configured corpus, not an assurance that every file in the repository has been parsed.

`context` refreshes by default; `--no-refresh` explicitly labels stale data. Select files/symbols for ambiguous
queries. Entry ranking is lexical. Optional sections obey a character-based token estimate, not an exact
model tokenizer. Critical contracts, bridge endpoints and first linked tests can exceed the budget; the packet
reports this and provides expansion hints. This preserves the existing workflow behavior.

## Corpus and coverage

`corpus.include`, `exclude`, `exceptions` use fnmatch globs (`*` crosses `/`). Git-ignored untracked files are
not scanned. Default exclusions include generated, build, vendored, hidden/tool and reference directories.
Use explicit exceptions when their code is relevant. The default includes the actual code families of this
repository: Dart, Kotlin, Rust, C/C++, Java, Python, JavaScript/TypeScript and shell, plus structured resources
and manifests. Go/Swift scanners were removed by the owner; no claim about them is introduced here.

Each requested file has one status:

- `indexed`: the engine recorded it without parser diagnostics; this is not proof that all calls resolved.
- `partial`: parser diagnostics exist; some extracted symbols may remain useful.
- `not-indexed`: the configured file was not recorded by the engine (unsupported/filtered inputs included).
- `unavailable`: structural extraction was not run.

CodeGraph 1.6.2 does not index shell in our real fixture. Shell files remain discoverable by text search with
an explicit gap rather than an invented shell call graph. Unsupported formats such as a particular TOML/ARB
input may likewise be unindexed. JSON/YAML/XML are resources/configuration, not ordinary call graphs. Gradle
DSL, macros, dynamic calls and generated code have language-specific limits. `indexed` never means compiler
or runtime completeness. Review parse diagnostics and unresolved references before removal or impact decisions.

## Relationship provenance

AST symbol declarations carry `codegraph:ast`, extracted/high. Resolver calls/imports carry
`codegraph:resolver` / `codegraph:resolver-import`, inferred, with the numeric engine score retained in evidence.
Scores <= 0.5 render low confidence; others remain medium, never compiler proofs. The blast-radius display
retains these labels and describes candidate reachability. Common names and strings are not searched to
manufacture additional call edges. The retired regex call resolver was removed.

Cross-language calls from the generic resolver are rejected except the C/C++ source family. Language
interoperation requires explicit boundary evidence, not a shared function name. Dart/Kotlin channels still use
the existing literal/declared wrapper scans with confidence and unresolved-endpoint reporting. They are
navigation evidence; read and test both sides.

Native evidence adds literal JNI names and simple explicit token-paste JNI macros, matched against extracted
Kotlin/Java native declarations. Overloaded signatures, JVM name changes, nested classes, dynamic registration
and runtime library loading require verification. JNI matches are binding candidates, not ordinary call edges.
`RegisterNatives` and UniFFI export surfaces remain explicitly unresolved where binding generation/registration
cannot be proved. No generated-binding or FFI link is guessed by function name. General JNA/dlsym/FFI lookup
resolution is not implemented. These limits are visible in `map coverage` and related context packets.

Reviewed module responsibilities, allowed dependencies, state/resource ownership and port contracts remain
in `workflow/work/architecture.json` and change `assurance.json` files. The map reads them without writing them.
This avoids making AST shape the authority for architectural decisions.

## Isolation, publication and freshness

Generated data remains under root `.work/map/`. `codegraph/source/` is a private copy of configured inputs and
necessary manifests. CodeGraph writes its SQLite/WAL data inside that mirror, never into the application's
source tree. The adapter rejects traversal and symlink inputs. The adapter controls scanner configuration so
an unrelated root `codegraph.json` cannot silently replace the workflow's corpus policy.

Updates hold the existing map lock and publish matching graph/state hashes atomically. Failed extraction
keeps the last published map marked stale. A forcibly interrupted process may leave a cache requiring rebuild.
The digest includes source hashes, auxiliary manifests, map/check configuration, adapter/normalizer/native
inventory code, reviewed declarations and engine availability/version. Configuration changes invalidate evidence.
The source tree is checked again after extraction before publication.

After every completed edit batch, run `map update` before using more graph context. Checks, packets and clean
code-review recording also refresh; review/ship/done gates demand a current map. Edits made outside the
workflow are noticed at the next command; Markdown instructions cannot observe every external keystroke.
Current freshness is separate from coverage and test results. Unresolved high-risk behavior still needs review.

## Verification

```sh
python3 -m unittest discover -s workflow/scripts/work -p 'test_*.py'
```

Most lifecycle/publication/gate tests use the explicitly mocked adapter; they do not establish parsing quality.
`RealCodeGraphSmokeTests` and `RealCodeGraphRegressions` exercise the pinned installed CLI, including Dart,
Kotlin, Rust, C, C++, Java, Python and JavaScript, and negative string/cross-language/wrong-class cases.
Real tests skip if the engine is unavailable; report those skips as unverified. The optional no-network
namespace test also skips when the host cannot create namespaces. No device behavior is verified by map tests.
