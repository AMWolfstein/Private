# Structured resource and Bash supplement

Follow-up to CODEGRAPH_MIGRATION.md. Only workflow distribution code changes; project scripts are never executed.

## Coverage on the copied Sistrum source corpus

The configured 1189-file snapshot now reports 1115 engine-indexed files, 68 resource-indexed files and
6 shell-indexed files, with no unindexed/error/unavailable input in this configured corpus. The 68 resource
files include six XML files already recorded by CodeGraph; therefore this covers the former **68 missing
inputs** (62 resources plus six shell scripts), not 74 newly missing files. Excluded/generated/vendor files
remain separate and are not claimed analyzed.

Resources use actual JSON/ARB, XML and TOML parsers; the separate Bash worker uses pinned tree-sitter 0.25.2
and tree-sitter-bash 0.25.1. Python 3.11+ uses stdlib tomllib; 3.10 requires the conditional tomli requirement.
Install workflow/scripts/work/requirements.txt in the workflow Python; WORK_SHELL_PYTHON can select an isolated
Bash interpreter. No Graphify is needed. CodeGraph's bundled Bash WASM was tested but failed on real scripts;
it is not used or patched. No dependency is downloaded automatically; CodeGraph shim self-download is disabled.

The Bash AST inventory contains 106 commands across the six scripts and no syntax diagnostics. It does not
execute commands or resolve eval, aliases, variables, dynamic cwd, sourced environments or all runtime effects.
Structured-resource status means valid parsed data, not compiler/runtime completeness. CodeGraph's original
engine_status remains visible alongside the supplementary status.

## Relationships

- Dart l10n keys link to locale variants in the same Flutter package.
- Direct R.type.name and local XML @type/name references link within an Android module. External/ambiguous
  namespace/module references are not falsely bound. XML element text and attributes are considered.
- Literal Rust fixture macros and conventional Dart file/asset reads link existing inputs with explicit confidence.
- Cargo workspace/member/path declarations, including inherited dependencies and root manifests, link local manifests.
- Bash literal source/invocation paths are only low-confidence cwd-dependent candidates. Other commands remain inventory.

Detailed relationships are retained separately from deduplicated file dependencies so repeated keys cannot
inflate direct-user/test-impact counts. Context exposes bounded resource/script evidence and unresolved references.
Freshness includes source hashes, supplemental parser/worker code, requirements and parser capabilities.

## Verification and review

Final copied-installation suite: 162 total, 161 passed, zero failed, one optional network-namespace test skipped
by this host. Real CodeGraph and real Bash parser tests run; check workflow and fresh pass. Tests include data
parse failures/duplicate JSON keys/XML DTD rejection, Cargo shape/ancestry rules, package/module isolation,
pointer identity, comments/string false references, Bash heredocs/dynamic commands/syntax errors and a sentinel
proving scripts were not run. Resource edits, renames and deletion remove old symbols and dependencies.

A fresh read-only review reproduced seven issues; all were fixed with regressions: omitted XML text, root
Cargo inheritance, invalid members crashing, cross-module Android links, duplicate dependency counts, comments
misread as fixture access and pointer collisions. Re-review found no remaining concrete blocker. This is not
a proof of all framework resource usages or dynamic shell behavior. No app build, device test or push was performed.
