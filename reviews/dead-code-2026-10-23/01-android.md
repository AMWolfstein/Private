# Android dead-code review (N1)

## Scope

Role dead-code-hunter; application d5d5a02 unchanged, review baseline47039b90. Inventory303 native paths screened by filenames. Android declaration search output truncated, so no complete private-symbol coverage claim. Whole reads reported by reviewer: SafFileOps.kt; NativeReplayGainPolicy.kt and its test (retained by explicit owner decision); AndroidManifest.xml; proguard-rules.pro; CMakeLists.txt; native_audio.map. Additional Saf metadata-policy read not certified here because reported filename differed from inventory. Paths under android/app/src/main unless specified.

Graph native dead-code query completed, truncated navigation only. Candidate reference searches spanned android,rust_backend,third_party,lib,test,scripts,assets,pubspec.yaml. JNI, manifests, bindings, CMake exports and public entrypoints considered. Prompt-only read restrictions; no application edits.

## Findings

### DEAD-001 [P3] [confidence: high] [VALIDATED — static]

- Location: android/app/src/main/kotlin/com/zarz/spotiflac/SafFileOps.kt:116, writeFileToSafLocked.
- Scenario: maintained SAF utility contains a private staged-file writer with no caller; its exclusive replacement/cleanup helpers remain compiled.
- Root cause: offline feature removal left an unreachable writer island.
- Impact: approximately150–180 lines of obsolete publication/cleanup policy obscure the live SAF path.
- Fix: remove writer116–163, PublishTrace30–43, syncOutputStream52–58, replaceFinalDocument67–98, normalizeExt167–172, staging helpers175–212, STAGED constant19 and now-unused imports; separately remove definition-only findDocumentDir314–330. Low static removal risk; Android checks required when implemented.
- Evidence: writer name occurs only at declaration; helpers have references only inside this island. MainActivity905–914 uses live sanitizeFilename/ensureDocumentDir/createOrReuseDocumentFile and writeUriFromPath instead.
- Cross-refs: MainActivity.kt, AndroidManifest.xml, native/FFI export searches.
- Guards checked: private method has no channel/JNI/reflection registration or regression-test entrypoint. Live SAF utilities must remain. Coordinator independently searched candidates repository-wide and reread writer105–178/live caller895–917.

### DEAD-002 [P3] [confidence: high] [VALIDATED — static]

- Location: android/app/proguard-rules.pro:48, removed-component keep blocks.
- Scenario: shrinker configuration still names DownloadService and DownloadQueueWidgetProvider, but both classes/components are absent.
- Root cause: stale keep rules from removed download functionality.
- Impact: misleading retention policy, six unnecessary lines.
- Fix: remove only the two blocks; negligible behavior risk.
- Evidence: source search matches only rules and a NativeReplayGainPolicy comment; manifest instead registers BackgroundWorkService/PlayerWidgetProvider.
- Cross-refs: AndroidManifest.xml, Kotlin source inventory.
- Guards checked: MainActivity/JNI/JNA/generated registrant rules live and retained; NativeReplayGainPolicy explicitly kept for future Media3, not reported dead. Coordinator reread rules42–59 and candidate references.

## Verification / limitations

Static reference proof only. No Kotlin/Gradle/Flutter tests/builds/device checks. Broad declaration screen incomplete due truncation; report certifies the candidate islands only, not absence of all unused private Kotlin symbols. NativeReplayGainPolicy, JNI/public exported methods and test contracts retained. No security checks. Result FINDINGS.
