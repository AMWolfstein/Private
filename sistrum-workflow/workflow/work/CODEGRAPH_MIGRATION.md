# CodeGraph engine migration

Base revision: `434dd03d`, fetched and applied before implementation. Only the workflow distribution changes.
The owner authorized replacement of the extraction engine; no push or APK build is included.

## Design and implementation

Public map/context commands, bounded rendering, assurance gates, reviewed declarations, contracts and channel
enrichment remain. CodeGraph 1.6.2 replaces Graphify behind `codegraph_adapter.py`: a pinned CLI/SQLite boundary
with telemetry disabled, private persistent source mirror, incremental sync and per-input diagnostics.
No Graphify dependency, second production extractor or raw `explore` response remains in the runtime.

The regex call resolver was removed instead of expanded to more languages. Fallback declarations are
low-confidence navigation candidates only; they cannot generate call edges. Old tests asserting heuristic
call attribution were replaced with real-parser negative regressions and fallback-no-calls checks. Corpus,
freshness, publication, channels, contracts, installation and phase-gate tests remain.

`workmap.py` retains import relationships for every engine language, scores/provenance and native evidence.
`map coverage` reports languages, diagnostics, unresolved references, excluded candidate paths and boundaries.
`native_bindings.py` recognizes literal JNI names and simple token-paste macros as candidates; generated
UniFFI exports and dynamic registration remain explicit unresolved records. No ordinary cross-language call
is fabricated from a common name. Owner removal of Go/Swift from the corpus is preserved.

## Verification

The pinned CLI was installed in a temporary local tools directory for validation, not globally or into an
agent. The real regression fixtures verify calls in Kotlin, Rust, C, C++, Java, Python and JavaScript, plus
Dart same-class resolution and negative string/declaration/cross-language cases. Existing real Dart/Kotlin
smoke tests run too. Snapshot tests cover unchanged mtimes, traversal/symlink rejection, directory-to-file
replacement and removal. A copied installation exercises Python import evidence through the real context
renderer and coverage command.

Full copied-installation suite: 144 total, 143 passed, zero failed, one skipped (host cannot create the optional
network namespace). `check workflow` and `fresh` pass with the real CLI on PATH. Final checks are repeated
on the final source before commit. These are workflow tests, not application or device validation.

A copied first-party source snapshot exercised actual repository extraction and Rust/Kotlin context. The
configured corpus contains 1189 files: 1121 recorded by the engine, 68 not indexed (31 XML resources,
24 JSON/ARB inputs, 7 TOML manifests, 6 shell scripts). The initial run was about 11 seconds, a single run,
not a controlled benchmark. The temporary copy initially included two distribution-test inputs accidentally
via the auxiliary-file copy; those were removed before final corpus verification. No token-saving claim is made.

The native inventory contains 18 JNI candidates and 12 unresolved UniFFI export surfaces on this snapshot.
These do not verify runtime library loading, overloads, registrations or generated bindings.

## Independent review

A fresh read-only reviewer found lost non-Dart/Kotlin imports, confidence upgrades, obsolete directory shape
in the mirror and missing rendered import confidence. Fixes preserve engine dependencies, low scores,
prune obsolete parent directories and label import provenance. Tests cover non-Dart context rendering,
normalization/confidence boundaries and directory-to-file staging. Review did not prove upstream semantic
completeness or device behavior.

## Limits and resumption

See `guides/map.md` for installation, schema and commands. Installation uses an explicit pinned CLI and an
argv configuration; no automatic downloads or stored machine paths. A missing tool produces limited fallback
navigation with explicit gaps, not a successful structural-analysis claim.

Shell is not AST-indexed by the pinned engine in the fixture. Many structured resources are not indexed or
are not ordinary call graphs. Indexed status means the engine recorded the file without diagnostics; it is
not compiler completeness. Dynamic dispatch, macros, JNI overload/name changes, JNA/dlsym/general FFI and
generated UniFFI runtime links remain limitations. The next work, if authorized, is focused on these reported
gaps rather than a second heuristic call graph. Windows and namespace-based isolation are not verified here.
No application code, production audio engine or device behavior was changed; no APK or push was performed.
