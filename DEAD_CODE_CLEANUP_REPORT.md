# Dead Code Cleanup Report

## Executive summary

- Repository: `AMWolfstein/Private`; Android arm64 application.
- Starting commit and unchanged base branch `mornye-reboot3`: `e408b8cc6fe6da2d68c601d654890c0b5b12e20d`.
- Cleanup branch: `codex/autonomous-dead-code-cleanup`.
- Final source commit: `16827263bd2179d47e9403c543277df8fe4fa1e4`.
- The final report is committed separately. Its commit is the commit containing this file (`git log -1 --format=%H -- DEAD_CODE_CLEANUP_REPORT.md`); the source commit above excludes documentation.
- Two validated cleanup batches removed one orphaned Dart file and unused declarations from three other Dart files: **418 source lines removed, zero source lines added**. No dependencies, tests, assets, localization messages, native exports or generated bindings were removed.
- Live selection logic and the live `TrackListTile` implementation were verified byte-for-byte unchanged. Existing widget tests cover the retained headers, selection controls and badges. No UI redesign, playback change or duplicate-code consolidation was performed.
- Android compilation and device behavior remain unverified because SDK/NDK prerequisites are absent. This is not a claim that the application is free of all dead code.

## Repository verification and architecture

The selected remote branch SHA matched the starting commit. The platform originally checked out the snapshot as `work`; the requested `mornye-reboot3` branch was selected before this task. A dedicated cleanup branch was created without changing the base branch.

The only initial untracked paths were Flutter-generated artifacts under `ios/`, `linux/`, `macos/` and `windows/`, left by the previous environment setup. None contained tracked files on this Android-only branch. They were preserved intact outside the checkout at `/workspace/preserved-before-dead-code-e408b8c`; no user source changes were discarded. The working tree was clean before source cleanup began.

`AGENTS.md`, the repository work/fix/review/ship guidance, constitution, architecture/build documentation, manifests and the existing Android-only decision record were read. The pre-existing `001-android-arm64-only` workflow record was not edited, advanced or declared complete by this cleanup.

Current application structure:

- Flutter/Dart UI, providers, controllers and services under `lib/`; executable entry point `lib/main.dart`, background entry-point annotations, routes and framework registrations are retention roots.
- Rust workspace: `core`, `network`, `providers`, `extensions`, `mobile`, `cast`, and `bindgen`. `mobile` exposes UniFFI APIs; the build script generates Kotlin bindings and stages the Android library. Android-only `cfg` branches and public generated-binding surfaces remain protected.
- Kotlin/Java channel adapters and Android services/components under `android/`; Gradle includes the Rust adapter and generated Kotlin directories. Manifest components, services/receivers, channel callbacks and runtime registrations were treated as live.
- C++17 audio backend: Oboe, WavPack and FLAC. `JNI_AUDIO(name)` creates JNI names using token pasting. All **18** Kotlin `external fun` declarations match both the macro-expanded C++ export names and `native_audio.map`. These files were not changed.
- Only `arm64-v8a` / `aarch64-linux-android` is supported by the application build. Gradle rejects other Rust ABIs. Compile/target SDK is 37, NDK is `30.0.16248370`, Java/Kotlin target is 25, and Android CMake is pinned to 4.1.2. Host FLAC tests use `MORNYE_AUDIO_HOST_TESTS=ON`; this does not compile the Android JNI backend.

## Tools and initial discovery

No application dependency was added for analysis. Tools were installed only in ignored `.work/` environments or the external tool cache.

| Tool/check | Version or coverage | Result/limitation |
| --- | --- | --- |
| Flutter / Dart | 3.47.8 / 3.13.7 | Pinned SDK; required repository SDK patch retained |
| Rust | 1.99.1 | Pinned toolchain, rustfmt and Clippy |
| CodeGraph | 1.6.2 | Workflow doctor passed after project-local setup |
| dartograph | 0.17.0 | Whole-application reachability, dependency and override-only reports |
| ciach | 0.7.1 | Independent LSP reference analysis; 680 files, 17,153 declarations; no warnings or analysis problems |
| CMake / Ninja / GCC | 4.4.4 / 1.13.2 / 14.2.0 | Isolated host build tools; FLAC compilation uses warnings as errors |
| cargo-fallow / cargo-udeps | Not installed | Availability checked; not required or treated as proof of absence |
| clang-tidy / IWYU / Clang | Unavailable | GCC diagnostics, CMake compilation database and manual native tracing used; no native cleanup attempted |

The initial tracked-file inventory contained 2,880 files, including 1,357 Dart, 765 Rust, 157 Kotlin, 38 Java, 7 C++ and 24 C files. These counts include vendored/generated/support files; they are not semantic coverage claims. The configured project map covered 1,872 inputs: 1,773 AST-indexed, 95 structured resources and four Bash inputs. Vendored/generated exclusions and dynamic binding gaps remain explicit.

Initial results were **99 dartograph dead findings**, **21 override-only findings**, and **84 ciach unused declarations**. Counts use different units and must not be added. Tool suggestions were reviewed against source, tests, configuration, imports/exports and native boundaries; no automatic bulk-removal option was used.

### Confirmed and removed

| Batch / file | Declarations removed | Source lines removed |
| --- | --- | ---: |
| 1: `lib/widgets/track_lists/detail_header.dart` | Entire unimported library: `detailBottomInset`, `_toolbarHeight`, `detailArtworkSize`, `detailSubtitleStyle`, `detailHeaderSlivers` | 255 |
| 1: `lib/utils/adaptive_layout.dart` | `wideContentMaxWidth` | 2 |
| 2: `lib/widgets/track_lists/list_selection.dart` | `selectionModifierPressed`, `selectionClickKind`, `isContextMenuKey`, `RowDoubleClick`, `ContextMenuTarget`, `ListScope`, `_ListScopeState`, and two now-unused Flutter imports | 109 |
| 2: `lib/widgets/track_list_tile.dart` | Uninstantiated `TrackListTileBadges` | 52 |

Evidence common to these removals:

1. ciach independently reported the declarations unused; dartograph reported unreachable declarations/libraries or types retained only by their unused framework overrides.
2. CodeGraph indexed all four affected files without parser diagnostics or unresolved-reference counts in those files. Its relationships were navigation evidence, not compiler proof.
3. Tracked source/reference searches found no external callers or importers for the removed declarations. Remaining references were within the same dead subgraph. Tests, integration tests, Android/native sources, build scripts and manifests were included in the reference checks.
4. None of the removed declarations was an executable entry point, native export, generated registration, channel endpoint, background callback or serialized schema registration. Flutter AOT cannot reach these ordinary declarations through an unregistered symbol-name lookup.
5. `RowClick`, `applySelectionClickTo`, actual collection headers and the live tile's inline badge rendering were retained. Assertions comparing the retained source against the base commit passed. Protected native/service/dependency/test paths have no diff.

### Probable or uncertain findings retained

| Area | Finding / reason retained |
| --- | --- |
| Playback and analysis | `TrackListTile.activate`, playback engine/volume helpers, autoplay training helpers and failure/fallback methods have static unused suggestions. Audio, fallback and runtime paths require Android integration evidence; they were not pruned. |
| Native/background work | Legacy `NativeBackendTransport`, native download-worker helpers and platform bridge methods appear in tool reports. Public native surfaces, generated callbacks and Android background integration are protected; missing static edges are not sufficient. |
| Navigation | Shell history/settings-detail helpers and Link-related navigation candidates need separate lifecycle/route characterization before removing their associated state. |
| Compatibility | Extension storage exception types and storage-mode failures were retained rather than altering compatibility/error surfaces. |
| Framework members | Render-object setters, constructor callback fields, notifier/provider members and serialization-shaped properties can have framework/dynamic uses that a graph misses. They remain uncertain. |
| Test hooks and constructors | Testing factories/debug accessors and private constructors preventing instantiation were retained intentionally. Tests and benchmarks were not deleted. |
| Rust | Host compilation does not cover all Android `cfg` branches, libusb use or UniFFI-generated consumers. No additional Rust deletion was confirmed with sufficient supported-platform coverage. |
| C++ / Kotlin / Java | JNI, Media3/audio code, manifest registrations, services/receivers and native wrappers remain live or unresolved. Android build limitations prevent speculative native cleanup. |
| Assets / localization | Bundled fonts/assets and gen-l10n resources may be loaded by configuration and runtime paths. No asset or translation deletion met the confidence threshold. |

The dependency audit suggested `app_links`, `cupertino_icons`, `build_runner`, `flutter_launcher_icons` and `riverpod_lint`. No dependency was removed: plugin registration/deep-link behavior needs runtime tracing; Cupertino icon fonts are asset consumers; code generation and launcher icons are documented CLI workflows; `analysis_options.yaml` explicitly configures `riverpod_lint`.

## Validation

| Check | Baseline | Final |
| --- | --- | --- |
| `flutter analyze` | No issues | No issues |
| Complete feasible Flutter suite | 4,488 passed, 1 failed, 24 skipped | **4,489 passed, 0 failed, 24 skipped** (completed exit 0) |
| Targeted affected-area suite | 93 passed, 3 skipped | Batch 1: 60 passed, 3 skipped; batch 2: 33 passed |
| Isolated baseline failure | `library_loading_test.dart`: 17 passed | No failure in final whole-suite run; no timing/test changes made |
| Rust workspace tests, locked, no-fail-fast | 556 passed, 0 failed, 8 ignored | 556 passed, 0 failed, 8 ignored |
| Rust Clippy, workspace/all-targets, warnings denied | Passed | Passed |
| Rust formatting | Not separately run before cleanup; Rust source is unchanged | Passed |
| C++ FLAC host build/test | 1/1 passed | 1/1 passed |
| Android arm64 debug APK | Blocked: no Android SDK | Blocked again: no Android SDK (exit 1) |
| Device/instrumentation tests | Not run | Not run; no physical device claim |

Whole Flutter command: `flutter test --no-pub --concurrency=4 --timeout 120s -r expanded`. The baseline loading test failed on its bounded readiness expectation under the whole-suite load, then its entire file passed alone. No unrelated test or production fix was made.

Rust commands ran from `rust_backend/` with the pinned toolchain: `cargo +1.99.1 test --workspace --locked --no-fail-fast`, `cargo +1.99.1 clippy --workspace --all-targets --locked -- -D warnings`, and final `cargo +1.99.1 fmt --all -- --check`. These are host results, not Android cross-compilation results.

The C++ host target was configured with `-DMORNYE_AUDIO_HOST_TESTS=ON -DCMAKE_BUILD_TYPE=Debug -DCMAKE_EXPORT_COMPILE_COMMANDS=ON`; build parallelism was four. Compilation preserved upstream download checksums and TLS verification. Android Oboe/JNI/WavPack linkage was not claimed verified by the FLAC host test.

The configured `work.py check auto --base e408b8c` orchestration was actually attempted with a 180-second bound. It launches each top-level test file as a separate Flutter process. The orchestration timed out (exit 124); it is **incomplete**, not a workflow-gate pass. Completed chunk logs were retained. The complete direct Flutter result above is separate evidence, not a fabricated successful workflow report. `work.py fresh` consequently reported `STALE_OR_INCOMPLETE`; its map state is current. This gate remains open.

Final Dart formatting and `git diff --check`: Passed; formatter checked all three retained edited files with zero changes. Cross-language source/export sets remained unchanged; all 18 JNI names still match. No generated bindings were regenerated or edited, and no stored data/schema migration was changed.

### Final discovery and independent review

The final whole-application dartograph scan reports **80** normal findings (down from 99) and **6** override-only findings (down from 21). None of the deleted target symbols remains. A focused ciach rerun checked all 52 remaining declarations in the three edited files, reported no analysis problems, and retained only `TrackListTile.activate` as an unused suggestion; it was preserved for the playback-safety reason above. The final CodeGraph map is current.

A fresh-context, read-only code reviewer examined the complete base-to-HEAD diff, retained callers and repository references. **VERDICT: CLEAN; no findings.** The reviewer did not rerun tests/builds or claim Android/device verification. Review evidence is retained in `.work/dead-code/independent-review.txt`.

## Git history and change accounting

| Commit | Change | Validation before commit |
| --- | --- | --- |
| `6fdd4a694a98490fdb7e38c05ea5963f66dcd97e` | Remove orphaned detail-header library and unused layout constant | Analyzer clean; 60 targeted tests passed, 3 skipped; formatting and current map |
| `16827263bd2179d47e9403c543277df8fe4fa1e4` | Remove unreachable list-interaction declarations and badges widget | Analyzer clean; 33 targeted tests passed; formatting and current map |
| Report commit containing this file | Record evidence, retained findings and limitations separately | Final evidence above; no application code changes |

Source-only change: **4 files changed, 418 removed, 0 added**; one file deleted and three edited. Report-only additions: 131 lines added in this report (recorded separately from source deletions). No application dependency declarations or lockfiles changed, no tests or benchmarks were changed, and no unrelated fixes were included.

The base branch still resolves to the exact starting SHA. The cleanup branch contains the two source commits above and a separate report commit. No merge, history rewrite or force push occurred. No remote publication was attempted; commits are preserved locally for review. The working tree was verified clean before creating this report and is checked again after its separate commit.

## Remaining work and evidence

1. Supply Android SDK 37, NDK `30.0.16248370`, Java 25 and Android CMake 4.1.2, then run Gradle JVM tests and the documented arm64 build. The available Java runtime is 21; no SDK/NDK bindings are configured. Run audio/device regression tests on actual hardware before claiming physical-device parity.
2. Investigate the baseline readiness timing independently; retain it as a baseline finding rather than silently changing its waits or assertions.
3. Review remaining playback/native/provider/navigation candidates with supported Android configurations and generated-binding consumers. Do not interpret the remaining static reports as deletion instructions.

Raw inventory, initial/final analyzer reports, candidate evidence, unchanged-live-code checks, per-batch logs, complete suite logs and the review packet are retained locally under `.work/dead-code/`. Workflow chunk logs are under `.work/runs/`. These ignored artifacts are not included as application files in commits.
