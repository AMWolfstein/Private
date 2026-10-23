# Build/dependency audit — first bounded pass

## Scope

Reviewer: dependency-auditor (`.claude/agents/dependency-auditor.md`), coordinator acting in that role. Application source `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`; checkout HEAD `5dcf7241`. Initial working tree clean. Independent audit; old findings were not imported. Reviewer restrictions are prompt-only. No application edits.

BUILD-01 manifest chunk (all lines): `.fvmrc`, `pubspec.yaml`, `rust_backend/rust-toolchain.toml`, `rust_backend/Cargo.toml`, `rust_backend/crates/{core,local,mobile,bindgen}/Cargo.toml`, `android/{settings.gradle.kts,build.gradle.kts,gradle.properties}`, `android/gradle/wrapper/gradle-wrapper.properties`, `android/app/build.gradle.kts`, `android/app/src/{main,release,profile,debug}/AndroidManifest.xml`, `android/app/src/main/res/xml/{backup_rules,backup_rules_legacy}.xml` (19 paths).

BUILD-01 supplemental script/package chunk (all lines): `scripts/{build_android.sh,build_rust_backend.sh,check_android.sh,check_rust_backend.sh,test_build_android.py,check_backend_apk.py}`, `android/app/proguard-rules.pro`, `third_party/{audio_service,audioplayers_android}/pubspec.yaml`, `assets/licenses/{native_data_jobs,native_palette}.txt` (11 paths).

Partial lock reads: `pubspec.lock` SDK footer only; `rust_backend/Cargo.lock` searched for patched crates, workspace crates, UniFFI, rusqlite and roxmltree names/versions. This is not a complete lock/manifest resolution review.

## Findings

None validated in these chunks. This is not a complete dependency or license audit.

Checks traced: Flutter version mismatch stops the release script before build; ABI validation maps both scripts to the Gradle filters; Cargo builds use `--locked`; host bindgen features are kept separate from the shipped-library build; release removes network permissions; backup rules exclude local grants/state; JNA/generated bindings have explicit R8 rules; Rust link flags request 16 KiB segment alignment. Static flags do not establish actual APK alignment, dependency compatibility, signing or device behavior.

## Verification

- `bash scripts/review_scope.sh --subsystem build`: exit 0; historical build coverage stale, graph reported fresh (built from `46c4ea6a`).
- `graphify query "Android build Gradle dependencies manifest toolchain" --budget 1600`: exit 0, truncated; used only as navigation to build scripts and fixture tests, never as evidence for missing edges.
- `bash scripts/review_scope.sh --coverage-status`: exit 0; historical subsystem rows remain stale/partial and were not promoted by this pass.
- `python3 -m unittest discover -s scripts -p 'test_build_android.py' -v`: PASS, 5 tests, zero failures/skips. Stub Flutter/auditor executables; no APK produced.
- `python3 -m unittest discover -s scripts -p 'test_*.py' -v`: PASS, 28 tests, zero failures/skips. Includes build-script, synthetic ZIP/ELF payload, and scope-tool fixtures. No real release artifact or native code execution claimed.
- Flutter not on PATH in this local session. Analyzer/full Flutter tests, real Gradle/Rust builds, manifest merge, actual signing/alignment inspection and devices NOT RUN. Prior cloud download restriction is historical evidence, not a claim about this local machine.

## Limitations

Remaining BUILD-01 work: complete resolved lock/constraint comparison; actual toolchain compatibility; remaining license/notice and vendored patch manifests; `check_android_statx.sh`; build-artifact/device checks where available. No advisory lookup or vulnerability clearance performed. Audio-engine implementation bodies remain excluded. No cosmetic or speculative finding raised for obsolete comments/keep rules or dependency presence alone.

## Result

PASS for static guards in the explicitly read chunks; BUILD-01 remains INCOMPLETE.
