# Code map and task context

`work.py map` keeps a map of the code; `work.py context "<task>"` returns a small, bounded packet from it:
entry points, both sides of affected Dart ↔ Kotlin channels, declared ownership and contracts, linked tests
and checks, short excerpts, and what is uncertain. Read the packet first and open only the files it points to.
The map never proves that tests pass, that the architecture is right or that a review was independent.

## Install

Graphify is off by default (`extractor.enabled: false` in `workflow/work/map.json`, status `disabled`). Nothing
needs installing: without it the map still holds imports, channels, tests and declarations, and every packet says
structure is disabled. Dart and Kotlin are covered by pattern scans either way.

To add symbols, calls and references for the other languages, install the pinned version and enable it:

```sh
python3 -m pip install graphifyy==0.9.97   # PyPI name has two y's; the module is `graphify`
# then set "enabled": true under "extractor" in workflow/work/map.json
python3 workflow/scripts/work/work.py map update
```

- Verified version: graphifyy 0.9.97 (Apache-2.0, `graphifyy-0.9.97.dist-info/licenses/`). It pulls in
  networkx, numpy, rapidfuzz, pyyaml, tree-sitter 0.25 and about 25 tree-sitter grammar packages; it is not
  dependency-free. Installing needs network access; extraction does not (tested inside `unshare -n`).
- Used: only `graphify.extract()` (local AST extraction, exported by the package), in a separate process
  through `workflow/scripts/work/graphify_adapter.py`, with `PYTHONHASHSEED=0` and its cache in
  `.work/map/graphify/`. Not used: the `graphify` CLI (it also checks and refreshes installed agent skills),
  LLM/semantic extraction, clustering, reports, hooks, MCP, watch.
- Interpreter: `WORK_GRAPHIFY_PYTHON` (a command, split like a shell), else the current Python if it can import
  `graphify`, else the interpreter in the `graphify` script's first line. Nothing machine-specific is stored.
- Another installed version is reported `unverified` and not used. To move the pin: install the new version,
  run `python3 -m unittest workflow.scripts.work.test_workmap` (the `RealGraphify` smoke tests must run, not
  skip), check the Dart/Kotlin notes below, then change `extractor.version` in `workflow/work/map.json`.
- `extractor.enabled` defaults to `false`. `WORK_MAP_STRUCTURE=off` also forces it off for one run (status `disabled`).

## Commands

```sh
python3 workflow/scripts/work/work.py map status      # current | stale | missing | invalid, with reasons
python3 workflow/scripts/work/work.py map update      # rebuild only if the inputs changed
python3 workflow/scripts/work/work.py map build       # rebuild and clear Graphify's cache
python3 workflow/scripts/work/work.py context "<task words or identifiers>" [--file P] [--symbol S]
        [--budget TOKENS] [--depth 2] [--expand file:P|symbol:S|bridge:CHANNEL|module:ID] [--json] [--no-refresh]
```

The packet is printed and also saved as `.work/map/context/latest.md` and `latest.json`.

## What runs automatically

Instructions cannot see edits made outside the workflow. The workflow checks freshness at its next operation:

| Operation | Map behaviour |
|---|---|
| `context`, `packet` | refresh a stale map first; on failure use the last map, labelled STALE, with the failure |
| `check` | refresh after the run; the check verdict is unchanged, the report's `map` says whether it worked |
| `round <NNN> code clean` | refuses unless the map is current; stores its digest in the round |
| `advance` to review, ship, done | refreshes, then the gate fails if the map is not current |
| `lint` (review and later), `fresh` | read-only: a stale or missing map is a problem / not fresh |
| ship gate | the last clean code round must carry the current corpus digest |
| `status` | one line: state, file count, structure, last failure |

Optional host hooks may call `work.py map update` after edits; they are a convenience, not a requirement.
There is no watcher.

## Freshness

`.work/map/state.json` stores a digest of four components; any difference makes the map stale:

- corpus: path and git blob id of every corpus file, plus `pubspec.yaml` files, `.graphifyrc` and non-code files
  under test directories (fixtures). Blob ids come from a temporary git index: content, not timestamps.
- config: `workflow/work/map.json`, `workflow/work/checks.json`, `workmap.py` and the adapter.
- declarations: `workflow/work/architecture.json` and every change record's `assurance.json`. A change's phase
  is read when a packet is rendered, so `advance` does not make the map stale.
- tool: extractor status, package, pinned and installed version, Python and grammar versions.

`update` rebuilds a complete new snapshot over the current corpus; Graphify's per-file cache (keyed by content
hash, version, schema and grammars) keeps unchanged files cheap. Deleted and renamed files therefore leave no
stale nodes or edges. The update runs under `.work/map/update.lock` (POSIX `flock`), refuses to publish if the
inputs changed while it ran, and publishes `map.json` and then `state.json` by atomic rename. If extraction fails,
times out or returns malformed output, the last valid map stays and `state.json` records `last_failure`; the map
is then stale and gates fail. `.work/` is ignored by git and excluded from evidence fingerprints, so map
updates never invalidate check evidence or review rounds, and real source or configuration changes always do.

## Corpus

`workflow/work/map.json` → `corpus`: `include` globs, `exclude` globs, `exceptions` (re-include an excluded path).
Globs use fnmatch, `*` crosses `/`. Files ignored by git are never read.

The default `include` covers the source code of every language Graphify extracts in this repository: Dart,
Kotlin, Rust, C/C++, Java, Python, Swift, shell, Gradle, and a few more. Configuration and data formats (JSON,
YAML, XML, project and lock files, Markdown, images) are not code and are not indexed.

Default exclusions: the workflow itself, hidden top-level and hidden folders (`.*`), `.work/`, an old
`graphify-out/`, build output, `.dart_tool`, `.gradle`, `node_modules`, generated code (`*.g.dart`,
`*.freezed.dart`, `*.gr.dart`, `*.mocks.dart`, protobuf, `app_localizations*`, `*/generated/*`, `*/bindings/*`),
vendored and reference code (`third_party/`, `*/vendor/*`, `reference/`), review reports (`reviews/`), the
`new workflow/` folder and `docs/`. Adjust these in `map.json` when the repository layout changes.

What is measured for a language decides what the packet can say: Dart and Kotlin get imports, channels and
handlers; the other languages get Graphify's symbols, calls and references, but not import resolution or channel
scans.

## Facts and provenance

Every relationship carries `fact` (extracted, declared or inferred), `via` (who produced it) and `confidence`.

| Layer | Produced by | Fact, confidence |
|---|---|---|
| Kotlin symbols, members, calls, type references | Graphify tree-sitter (`graphify:kotlin-ast`) | extracted, high; Graphify INFERRED cross-file calls: inferred, medium |
| Dart classes, functions, fields, inheritance, Riverpod/Bloc lookups | Graphify regex extractor (`graphify:dart-regex`); without Graphify, the pattern scan (`workflow:dart-declaration`) | extracted, medium; pattern scan `declared`, medium |
| Kotlin classes and functions without Graphify | pattern scan (`workflow:kotlin-declaration`) | declared, medium |
| Dart import/export/part and Kotlin imports, resolved to files | this adapter (`adapter:dart-directive`, `adapter:kotlin-import`) | extracted; ambiguous Kotlin targets inferred, low |
| Channel declarations, commands, listeners, stream handlers | this adapter's pattern scan | literal names extracted, high; command attribution medium; single-channel guess inferred, low |
| Tests per source file | imports from tests, Graphify edges from tests, Dart part→library | extracted or as the edge; name convention inferred, low |
| Modules, ownership, allowed dependencies, constraints | `workflow/work/architecture.json` | declared (status reviewed or proposed, with source) |
| Bridge contracts, port components, prerequisites | change records' `assurance.json` | declared; accepted plan high, draft medium |
| Rule violations | declared rule × extracted import | inferred, medium: "possible violation" |

Graphify 0.9.97 facts verified on the Sistrum code base: Dart gets declarations only, with no call edges, and
its import edges are left unresolved (the adapter resolves them); Kotlin calls inside lambdas and across files
are partly missing (for example `engine.start()` inside a `setMethodCallHandler` lambda).

To fill the Dart call gap the map infers calls by name (`adapter:dart-name-call`, always `inferred`): an
unqualified call `f(` or `this.f(` in a Dart file is attributed to a declaration named `f` in this scope order:
the same file (`via` says `(same file)`), then a file it imports (`(imported file)`), then anywhere in the corpus
only when at most three files declare that name (`(corpus)`, `low` for several). Same-file and imported matches
are `medium`. The caller is the nearest declaration above the call. Qualified calls such as `Type.f(` or `value.f(`
are not attributed, because matching them by name produced false edges (for example framework methods that
share a name with repository code). Common names (`build`, `dispose`, `add`, ...) are never attributed. Expect
missed calls through qualified receivers, tear-offs and dynamic dispatch.

### Channel conventions recognised

- Dart: `MethodChannel`/`EventChannel`/`BasicMessageChannel`/`OptionalMethodChannel` with a literal or a constant
  name; the variable it is bound to (`x = ...`, `x = y ?? const ...`, `_x = x`); `receiver.invokeMethod('cmd')`
  and `invokeMapMethod`/`invokeListMethod`; `receiveBroadcastStream()`; top-level channel constants used from
  other files; wrapper functions listed in `bridges.dart_wrappers` (`{"function": "...", "channel": "..."}`).
- Kotlin: the same channel types with a literal or `val` constant name; `setMethodCallHandler { }`, `(this)` with
  `onMethodCall`, chained or `.also { channel -> }`; `when (call.method) { "a", "b" -> }`, `call.method == "x"`
  and `!=`; `setStreamHandler`.
- Reported, never guessed: names that are not literals or unique constants, interpolated names (`$id`, low
  confidence), `invokeMethod(variable)`, delegated dispatch (`f(call, result)`, `call.method in set`), handlers
  in files without a channel, commands that could belong to several channels. Channels with only a Dart side are
  usually plugins whose native code is a dependency.

## Schemas

`workflow/work/map.json` (human-maintained configuration): `version` 1; `extractor` {name, package, version,
enabled, allow_unverified, timeout}; `corpus` {include, exclude, exceptions}; `bridges` {dart_channel_types,
dart_invoke_methods, dart_wrappers, kotlin_channel_types}; `context` {budget_tokens, entry_files, per_section,
excerpt_lines, max_excerpts, fallback_hits}. Unknown keys are rejected.

`workflow/work/architecture.json` (human-maintained declarations; never written by the tool):

```json
{
  "version": 1,
  "modules": [{
    "id": "playback-service",
    "paths": ["android/app/src/main/kotlin/*/playback/*"],
    "responsibility": "MediaLibraryService, session, notification and queue decisions",
    "owns": ["queue", "playback session"],
    "may_depend_on": ["engine"],
    "status": "reviewed",
    "source": "change 004 design review, 2026-11-20"
  }],
  "constraints": [{
    "id": "C1",
    "rule": "Pure Kotlin DSP does not import Android or Media3",
    "applies_to": ["dsp"],
    "forbid_imports": ["android.*", "androidx.media3.*"],
    "status": "reviewed",
    "source": "workflow/work/guides/architecture.md"
  }]
}
```

Omit `may_depend_on` to skip direction checks for a module; `[]` means it may depend on no other module.
`forbid_imports` matches import URIs (Dart) or fully qualified names (Kotlin) with fnmatch. Invalid
declarations block `map update`. A module whose paths match nothing is kept and reported.

`.work/map/` (generated, disposable): `state.json` {schema, digest, components, files: path → blob, structure,
tool, built_at, map_sha256, counts, last_failure}; `map.json` {meta, files, symbols, edges, deps, kotlin_index,
bridges {channels, unresolved}, tests, declarations, problems}; `graphify/` (Graphify cache), `logs/` (last five
extraction logs), `context/` (last packet). Delete the directory at any time; `map update` rebuilds it.

## Context packets

- Entry points come from named `--file`/`--symbol`, or from the task's words: path words and symbol-name words
  weighted by rarity, exact matches for code-shaped tokens (camelCase, snake_case), channel and command names.
  This is lexical, not semantic: the packet says so, lists ties and weak matches, and asks for `--file` when the
  words are common. Arabic or other non-identifier text finds nothing; restate it with code identifiers.
- Never truncated: freshness, entry points, both production sides of every touched channel with the commands
  the entry files use (other commands counted), unresolved endpoints, declared ownership, constraints, possible
  violations, contracts and port assurance. If these alone exceed the budget, they are kept and the packet says so.
- Truncated in order with "N more" and an `--expand` command: symbols, dependencies, tests and checks,
  excerpts. The budget is an estimate (characters / 4), not a model token count.
- No usable map, or no entry point: a labelled FALLBACK text search over the corpus files, never presented as
  graph relationships.

## Limits

- Lexical entry points can miss the right file or include an unrelated one; read the reasons.
- Pattern scans miss unusual code shapes (reflection, generated channel code, maps of handlers) and can mis-
  attribute a command in a file with several channels; such cases appear as unresolved or low confidence.
- A Dart `package:` import of a package outside the repository is external; a `pubspec.yaml` inside the
  repository maps `package:<name>/` to its `lib/`.
- Outside Dart and Kotlin, Graphify's symbols, calls and references are shown with their own provenance
  (`graphify:<language>-ast`). Imports and channels are not resolved for them.
- Locking uses `fcntl` on POSIX and `msvcrt` on Windows. The Windows path is written but not run in this
  environment; verify it on Windows before relying on it.
- Map facts are a starting point for reading code, not evidence for a review finding or a completion claim.
