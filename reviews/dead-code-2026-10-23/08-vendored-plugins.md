# Vendored plugin dead-code review (N3)

## Scope

Role dead-code-hunter, appd5d5a02 unchanged; baseline47039b90. Inventory86 third_party files, including30 code files. Lexical private-method screen56 declarations,2 singleton candidates. Full reads both plugin pubspec.yaml,Android manifests,SPOTIFLAC_PATCHES.md. Ranges: audioplayers_android AudioplayersPlugin.kt25–72; audio_service AudioServicePlugin.java270–296,870–887; AudioService.java450–475,777–800. Candidate references searched across lib/test/integration_test/android/rust_backend/crates/scripts/third_party; plugin registration/lifecycle/channel roots considered. Graph-first native query completed, truncated navigation only.

## Findings

### DEAD-015 [P3] [confidence: high] [VALIDATED — static]

- Location: third_party/audio_service/android/src/main/java/com/ryanheise/audioservice/AudioService.java:462, needCustomMediaControl;785, activateMediaSession.
- Scenario: retained plugin maintains two private wrappers with no callers.
- Root cause: earlier media-control/session implementation left obsolete helpers.
- Impact: approximately9 unnecessary lines complicate reading/upstream patch maintenance.
- Fix: remove both private methods; low risk. No upstream public API removal.
- Evidence: exact source searches return declarations only; live session activation directly remains at752,944,952,960,968.
- Cross-refs: plugin manifests/registration/patch notices and source references.
- Guards checked: ordinary private methods, not overrides/JNI/export/reflection names; no method references/tests. deactivateMediaSession is separately live and MUST stay. Coordinator independently searched names and reread453–472/778–794.

## Verification / limits

Static lexical/reference analysis only; no tests/builds/linker map or measured size claim. Public vendor API,lifecycle/channel hooks retained; Darwin-only source inventory-screened, excluded from removal findings. No security or engine behavioral review. Whole vendor reachability is not proved by token counts. No edits. Result FINDINGS, one P3.
