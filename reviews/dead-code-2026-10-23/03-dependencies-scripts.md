# Dependency declarations and tooling reachability (R2)

## Scope

Role dead-code-hunter; app source d5d5a02 unchanged, baseline47039b90. pubspec dependencies screened against all tracked lib Dart imports, then candidates searched across test/integration_test/android/third_party/scripts/assets/build docs; pubspec.lock inspected at package entries. All12 scripts inventoried as manual/build/test entrypoints; wrapper review_scope.sh and generator sync_opencode_agents.py read, check_android_statx.sh read in full. README/CONTRIBUTING/AGENTS and config references checked.45 .claude/.opencode tracked configuration/agent/skill paths are entrypoints loaded by tooling, not app-import candidates. Graph scripts/assets/entrypoint query completed truncated; no absence-of-edge proof.

## Findings

### DEAD-004 [P3] [confidence: high] [VALIDATED — static]

- Location: pubspec.yaml:61, open_filex dependency.
- Scenario: offline app resolves/registers file-opening plugin although no Dart call/import or custom channel caller remains.
- Root cause: obsolete direct dependency survived removal of external-player/file-opening path.
- Impact: unnecessary plugin resolution, Android registration and manifest surface; no measured APK-size claim.
- Fix: remove direct declaration and regenerate lock/plugin registration through normal dependency tools; low static removal risk, platform build/tests required.
- Evidence: repository package/import/OpenFilex/channel-name search finds only pubspec declaration/lock; no callers in lib/test/integration_test/native/plugin code. No pubspec asset path needs this package.
- Cross-refs: pubspec.lock and generated plugin mechanism (generated outputs are not callers themselves).
- Guards checked: registration alone does not invoke the plugin; no reflection/channel path found. Retained local sharing/editing/CUE functions use other APIs.

### DEAD-005 [P3] [confidence: high] [VALIDATED — static]

- Location: pubspec.yaml:17,65–66 (timezone,html,synchronized).
- Scenario: app retains three direct package declarations without any direct imports/API use.
- Root cause: removed implementation paths left redundant direct requirements.
- Impact: misleading ownership/version pins and dependency-maintenance burden; no claim that all three disappear from resolved transitive graph.
- Fix: remove redundant direct declarations, resolve with lock preservation and run required gates; three lines, low source risk, resolution risk must be checked.
- Evidence: no package:<name>/ imports in tracked application/tests or vendored Dart; name hits outside manifests are prose/native synchronized keywords, not Dart package use.
- Cross-refs: pubspec.lock, application import inventory.
- Guards checked: a dependency can remain transitively needed (e.g.notification libraries) after direct declaration removal; do not delete transitive lock entries by hand. Cupertino_icons explicitly retained: Flutter CupertinoIcons embeds its package/font reference and tests load its font by string even without package import.

## Retained tooling and limits

Manual scripts/benchmarks/examples/tests are executable entrypoints and are not dead merely because imported nowhere. check_android_statx.sh exercises the retained android_statx_smoke Rust example. sync_opencode_agents.py is invoked by AGENTS; review_scope wrapper calls Python engine. Test files are discovered by language runners. No script deletion proposed; exhaustive private Python function analysis not claimed. Stale missing tool/check_translations.dart references are documentation issues, not existing dead executable code.

No package removal, pub resolution, plugin regeneration, Flutter/compiler checks or security checks executed. Static dependency reachability only. Result FINDINGS.
