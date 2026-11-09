# Deferred dead-code candidates

These two cleanup groups are documented for the owner to handle later. **No declarations in either group have been deleted or refactored.** This document describes the source at `17cd3eaa07f39d6c3fc72c90b215578754f690df` on `codex/autonomous-dead-code-cleanup`.

## 1. Orphaned desktop backend transport interface

File: [`lib/services/backend/native_backend_transport.dart`](lib/services/backend/native_backend_transport.dart)

Declarations:

- `NativeMessageListener`
- `NativeMessageKind` and its callback-kind constants
- `NativeBackendTransport`: `init`, `call`, `subscribe`, `unsubscribe`

Evidence:

- Both ciach and dartograph reported this file/declarations as unused or unreachable.
- Current application, tests, Android/native sources and build scripts contain no imports, implementations or callers of this transport.
- Its historical consumer was `FfiBackendTransport`, which looked up the desktop `mornye_init`, `mornye_call`, `mornye_subscribe` and `mornye_unsubscribe` exports. That implementation and the Rust desktop crate were removed in the Android-only work.
- The actual Android Rust library exports the current UniFFI interface; none of those four desktop exports is present.
- The compiled Android debug kernel contains `backend_channel.dart` and `method_channel_backend.dart`, but not `native_backend_transport.dart`.

Potential future cleanup: remove the orphaned Dart file after rechecking references on the then-current branch. This is **not** a proposal to delete active native exports or Android transport code. Preserve `BackendChannel`, `MethodChannelBackend`, platform channels, UniFFI-generated bindings and JNI APIs.

## 2. Unconsumed shell navigation/history helpers

File: [`lib/services/shell_navigation_service.dart`](lib/services/shell_navigation_service.dart)

Candidate subgraphs:

- Library sidebar forwarding: `_libraryLinkHandler`, the `libraryLinkHandler` registration argument, and `requestLibraryLink`.
- Settings-detail forwarding: `_settingsDetailOwner`, `_settingsDetailNavigator`, `registerSettingsDetailNavigator`, `unregisterSettingsDetailNavigator`, and `activeBackNavigator`.
- Destination history: `_backHistory`, `_forwardHistory`, `_currentTab`, `_isNavigatingHistory`, `_tabAtCurrentIndex`, `recordTabVisit`, `canNavigateBack`, `canNavigateForward`, `navigateBack`, `navigateForward`, `_canRevisit`, `_travel`, `resetHistory`, `backHistoryForTesting`, `forwardHistoryForTesting`, and `currentTabForTesting`.

Evidence and boundaries:

- The unused public entry points are reported by ciach/dartograph. Reference searches found no external consumers for the history navigation commands, settings-detail registration or Library-link forwarding.
- Some bookkeeping still has **internal callers**: `syncState` records visits and handler unregistration resets history. Deleting only declarations would leave broken references; a future cleanup must assess the entire unconsumed subgraph.
- The actual Android Back implementation is `MainShell._handleBackPress`: it uses the root/current `Navigator.maybePop`, search handling and Home-tab selection. It does not call the destination-history APIs above.
- None of the existing tests consumes the listed history testing getters. Recheck this before changing them; do not remove tests or assertions to make cleanup pass.

Preserve the live `ShellTab` enum, tab keys, `_currentTabIndex`, `_showRepoTab`, `_showSearchTab`, `requestSearch`, `requestTab`, active tab-state synchronization, `_activeTabNavigatorKey`, `activeTabNavigator`, chrome notifiers and `ShellChromeObserver`. The similarly named `_currentTabIndex` is live and must not be confused with the history-only `_currentTab`.

## Checks for the later cleanup

- Re-run tracked-source/reference searches and confirm generated/native registrations before deleting anything.
- Run `flutter analyze` and the complete feasible Flutter suite.
- Relevant existing tests include `shell_navigation_service_test.dart`, `main_shell_keyboard_test.dart`, `detail_page_navigation_test.dart`, `tv_navigation_test.dart`, `mornye_loading_and_chrome_test.dart`, and `shell_tab_style_switch_test.dart`.
- Rebuild the Android arm64 APK, run Android JVM tests, and audit packaged ABIs/native libraries. Do not claim device behavior from host tests alone.

Current validation while both groups remain present: Android debug assembly succeeded; 176 JVM tests passed and 2 were skipped across 33 suites; the APK contains only arm64-v8a and 19 AArch64 ELF libraries. The five navigation/Back/chrome test files exercised before this deferred cleanup passed 38 tests. Physical-device testing was not performed.

## Explicitly not dead

The private `_DownloadQueueNativeWorker` extension was a false-positive candidate. `DownloadQueueNotifier` calls its adoption and queue-processing methods, including `_tryAdoptAndroidNativeWorkerSnapshot` and `_tryProcessQueueWithAndroidNativeWorker`. Preserve this worker, its recovery/fallback paths, and its platform bridge methods. Analyzer finding counts are not an instruction to delete all reported code.
