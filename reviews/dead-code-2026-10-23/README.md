# Repository-wide dead-code review

Application baseline d5d5a02, review baseline47039b90. Review-only; all15 findings are P3. No source code removed. Scope and conservative-screen limitations: [reconciliation](09-reconciliation.md), [inventory](inventory.json).

| Chunk | Report | Findings | Commit, successfully pushed |
|---|---|---|---|
| N1 Android | [01](01-android.md) | DEAD-001/002 |59651279|
| R1 Localization/assets | [02](02-localization-assets.md) | DEAD-003 |40e9aa30|
| R2 Dependencies/tooling | [03](03-dependencies-scripts.md) | DEAD-004/005 |52ff8f92|
| R3 Test support | [04](04-test-support.md) | DEAD-006 |0aeee6b2|
| N2 Rust | [05](05-rust-entrypoints.md) | None |bd91cb78|
| D1 Dart logic | [06](06-dart-logic.md) | DEAD-007..011 |ddc53e4a|
| D2 Dart UI | [07](07-dart-ui.md) | DEAD-012..014 |de3accf2|
| N3 Vendored plugins | [08](08-vendored-plugins.md) | DEAD-015 |b41a72df|

| ID | Removal candidate |
|---|---|
|DEAD-001|Uncalled SAF staged writer/helper island|
|DEAD-002|Two nonexistent-component ProGuard blocks|
|DEAD-003|Six unused old documentation/vector assets,1,130,688 bytes; no APK saving claimed|
|DEAD-004|Unused open_filex plugin dependency|
|DEAD-005|Redundant direct timezone/html/synchronized declarations; transitive requirements retained|
|DEAD-006|Two orphan test-support libraries,137 lines|
|DEAD-007|HistoryMaintenanceUpdate class|
|DEAD-008|MusicPlayerController.shuffleLibrary method|
|DEAD-009|navigateToTrackAlbum wrapper/private helper|
|DEAD-010|displayFormatForCodec function|
|DEAD-011|LocalLibraryState.existsInLibrary wrapper|
|DEAD-012|Obsolete completion/probe policy island,approximately415 lines; keep live paging helpers|
|DEAD-013|Two orphan gesture widgets and dedicated tests|
|DEAD-014|Unused PlayerPlaybackMode enum|
|DEAD-015|Two private vendored AudioService wrappers|

Compiler-level analysis/build/tests NOT RUN (Flutter unavailable; review-only). Source references were independently validated, including test-only exceptions, runtime registration,traits,FFI and assets. Test-only primitives/compatibility/injection seams retained unless actual obsolete consumers proved. Owner-requested security checks skipped. Each implementation batch will require its own applicable verification; this report does not authorize automatic removal of retained APIs.

N4 [C++/JNI and registered Java entrypoint supplement](10-cpp-jni-entrypoints.md): no new findings; all18 JNI methods have Kotlin/Java callers. Reconciliation checkpoint427cd455 successfully pushed.
