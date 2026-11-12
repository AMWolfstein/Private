# Standalone CodeGraph

CodeGraph **1.6.2** (`@colbymchenry/codegraph`, MIT) remains available independently
of the removed task/workflow system. No application dependency or agent installer
is involved. The existing local installation under `.work/tools/` is also retained.

## Install and check

From the repository root, with Node/npm and Python 3.10+ available:

```sh
npm ci --prefix tools/codegraph --ignore-scripts --no-audit --no-fund
python3 tools/codegraph/codegraph_adapter.py version
python3 -m unittest discover -s tools/codegraph -p 'test_*.py' -v
```

The manifest and lock pin the CLI and its platform package. The adapter looks for
the installation in this directory, then the existing `.work/tools/` cache, then
`codegraph` on PATH. It never downloads tools or modifies client configuration.
Optional `CODEGRAPH_COMMAND` is a JSON argv list for an explicit CLI executable.

## Structured graph extraction

Create an ignored request containing the repository root and selected relative
source paths; for example:

```sh
mkdir -p .work
python3 - <<'PY'
import json
from pathlib import Path
request = {
    'root': str(Path.cwd()),
    'files': ['lib/models/theme_settings.dart', 'lib/theme/mornye_theme.dart'],
}
Path('.work/codegraph-request.json').write_text(json.dumps(request))
PY
python3 tools/codegraph/codegraph_adapter.py extract \
  --request .work/codegraph-request.json --out .work/codegraph-result.json
```

The request can contain Dart, Rust, Kotlin, Java, C/C++, Python and other sources
supported by CodeGraph. The adapter stages a private source mirror, runs CLI
init/sync, then opens the resulting SQLite graph read-only. Unchanged mtimes are
preserved; renames/deletions are synchronized. The default cache is `.work/codegraph/`;
optional `CODEGRAPH_CACHE` must be an absolute directory.

Results include `nodes`, `edges`, per-file `coverage` and extraction statistics.
CLI telemetry is disabled in this adapter. Resolver relationships remain inferred;
missing or partial coverage is not proof that code is dead. Generic cross-language
call guesses are rejected except within C/C++; FFI/JNI/UniFFI and platform-channel
links need separate verified evidence. Resources and shell files retain explicit
coverage gaps; the removed system's supplementary parsers are not silently retained.

## Retained tests

The standalone tests cover safe staging, incremental snapshot changes, real CLI
symbols/calls across languages, wrong-class/string false positives, Python import
edges and stale-symbol removal. Retired task/context-renderer/normalizer/native-
inventory tests leave with their corresponding implementations. This directory
contains no task scheduler, fingerprints, approval gates, hooks or agent skills.
