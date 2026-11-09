# Linux environment setup and CI

Target: Linux cloud and Fedora 44, x86_64/aarch64 provisioning. Windows is outside the owner's scope.
No application code or audio behavior changes.

## Runtime behavior

- `work.py setup` checks Git root/HEAD and ignored, untracked `.work/`, then provisions `.work/python` and
  `.work/tools` with pinned parser requirements and CodeGraph. It does not use sudo or global installs,
  edit map.json, or configure an agent provider. Node/npm and Python venv/pip are initial prerequisites.
- `work.py doctor` diagnoses platform, confinement, Git/ignore rules, actual virtualenv prefix, real Bash
  parsing, TOML import, CodeGraph version and current dependency specification, without provisioning.
- Normal work.py CLI commands re-execute in the managed Python and prefer managed CodeGraph automatically;
  imported Python APIs do not replace the caller process. Explicit engine commands remain respected.
- Setup is lock-protected, healthy installations are reused, offline mode never downloads, and failures do
  not publish a new ready marker. Package-manager caches/logs stay under `.work/`.

## Test policy

`run_tests.py` preserves unittest summaries but strict mode rejects every skip except the exact optional
network-namespace test. It also requires all real CodeGraph/Bash integration classes to have run, so missing
engines/parsers cannot masquerade as a passing suite.

## Validation

The full final suite contains 180 tests: 179 passed, zero failed, one namespace-isolation skip on the local
cloud host. The actual copied-installation CI path is run on the cloud Linux/Python 3.12 environment and in
Fedora 44/Python 3.14.8. Those paths exercise online first setup, read-only doctor, offline reuse, automatic
tool/interpreter discovery, strict real parsing and clean Git status. Final runs are repeated before commit.
ARM64 is handled by runtime architecture detection and upstream bundles; not locally executed here.

Unit regressions cover missing/offline dependencies, idempotent setup, installer failures, malformed metadata,
symlinked managed paths/logs, actual ignored/untracked managed paths, and strict-skip policy. A real local-wheel
pip test supplies a destination-changing configuration and verifies installation cannot escape the managed prefix.
No external network is required by that regression.

Independent read-only review found pip-config destination redirection, malformed marker handling, incomplete
ignore checks and writable log symlinks. All were fixed and tested: explicit pip prefix, metadata validation,
actual managed-path/tracked-file checks, and symlink rejection plus no-follow append opens. Network/index/certificate environment variables are preserved. Pip configuration files and destination-changing
environment options are disabled; managed prefix/root and wheel-only installation are explicit. Npm cache/log
paths are constrained. Private index settings normally stored in pip config must be supplied through environment
variables for setup. Local-wheel tests cover target/root/report/log redirection.

No user-system package installation, application build or device test is part of this change. GitHub runs are verified separately
when available after the authorized push.
