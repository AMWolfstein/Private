# Mornye Local — implementation and verification

Status: **implemented and APK verified; overall verification FAILED/INCOMPLETE.**
The user explicitly authorized committing and pushing the source changes to
`mornye-reboot` after being informed of the failed/incomplete full-suite result.
This authorization does not change the recorded verification status.
Source base commit: `0912a8e9fedfca35e9a25197be6debcbde6437c2` (Mornye v5.3.1).
Source commit message: `feat(android): add 60Hz preference and release performance hub`.

## Files changed

- `PERFORMANCE_HUB.md`
- `PERFORMANCE_HUB_VERIFICATION.md`
- `android/app/src/main/AndroidManifest.xml`
- `android/app/src/main/kotlin/com/zarz/mornye/MainActivity.kt`
- `android/app/src/main/kotlin/com/zarz/mornye/PreferredDisplayController.kt`
- `android/app/src/test/kotlin/com/zarz/mornye/PreferredDisplayControllerTest.kt`
- `lib/app.dart`
- `lib/models/settings.dart`
- `lib/models/settings.g.dart`
- `lib/providers/performance_provider.dart`
- `lib/providers/settings_provider.dart`
- `lib/screens/main_shell.dart`
- `lib/screens/settings/app_settings_page.dart`
- `lib/screens/settings/performance_hub_page.dart`
- `lib/services/performance/performance_recorder.dart`
- `lib/widgets/performance_runtime.dart`
- `test/performance_controller_test.dart`
- `test/performance_hub_page_test.dart`
- `test/performance_recorder_test.dart`
- `test/performance_runtime_test.dart`

No original glass shaders, playback implementations, Rust crates, package names,
application ID or production signing configuration were changed. Generated
settings serialization is included as source; generated build directories,
keystores, APKs, passwords and local environment configuration are excluded.

## 60Hz preference

`PreferredDisplayController` selects a supported mode within 1Hz of 60Hz at the
current physical resolution and requests its ID through window attributes. It
clears the preference when unsupported. Resume/focus/display events reapply it;
pause/destroy unregister the listener. There is no Activity recreation, global
Android setting change, synthetic frame scheduling or Flutter VSync override.

An isolated method channel reports requested Hz/mode separately from Android's
active mode, Display.getRefreshRate(), current-resolution supported rates and a
bounded timestamped transition history. Android may override the preference.
**No physical refresh rate or device presentation cadence was verified.**

## Production Performance Hub

Normal navigation: **Settings → App → Performance Hub**, including Release mode.
Five controls are persisted through AppSettings/SettingsNotifier: monitoring,
HUD, first-interaction analysis, idle threshold and rolling window. Monitoring,
HUD and interaction analysis default off; defaults are 3000ms idle and 10000ms
rolling duration. Reset, clipboard copy and UTF-8 text export use existing APIs.

One Riverpod-owned collector uses release-safe FrameTiming callbacks. It is
registered only while enabled and foreground and removed on pause/disable/dispose.
No per-frame native calls, disk writes or UI notifications occur. Live UI/HUD
updates are bounded to 1Hz while there are listeners and suspend when paused.
HUD input transparency is tested and it uses no blur, glass or animations.

Collected data includes build/raster/span P50/P90/P95/P99, rendered frame
production rate, sample/window counts, engine timestamp gaps and percentiles,
maximum gap, active-mode budget, build-or-raster exceedance and slow-frame count.
Span exceedance is separate. Idle gaps/low idle FPS are not jank. Current and up
to eight frozen previous-screen windows are selectable for viewing and export;
disabling freezes data, enabling starts a new session, reset clears it.

Optional first interaction records raw pointer timestamp separately from Dart
receipt/UTC, observed idle duration, the next passive post-frame observation,
and engine-associated timings for a bounded 1000ms window. Eight captures and
512 frames per capture are retained. Delayed timing batches can fill retained
windows. Reset/pause/disable invalidate pending observers. Pointer recognition
and scrolling are unchanged; **the delay is not pointer-to-photon latency**.

Root/active nested navigation supplies screen identifiers; unknown detail routes
remain unavailable. Existing theme style, glass clarity/outline preferences and
motion-artwork preference are read without changing them. Effective per-surface
parameters and actual background animation playback remain unavailable.

## Verification results

| Check | Result |
|---|---|
| Pinned Flutter/Dart | Flutter 3.47.8 / Dart 3.13.7 |
| Rust toolchain | 1.99.1 |
| `flutter pub get` | Passed; lockfile unchanged |
| `dart format` | Passed |
| `flutter analyze` | Passed, no issues |
| New diagnostics Flutter tests | **19 passed** |
| Selected original shell/keyboard/glass/playback tests | **49 passed** |
| Android `:app:testDebugUnitTest` | **179 total: 177 passed, 2 skipped, 0 failed** |
| New native display policy/history tests | **4 passed** (included above) |
| ARM64 Rust backend staging | Passed, including required Kotlin bindings |
| Full `flutter test` | **Failed/incomplete**; final counters 6204 passed, 25 skipped, 86 failures/errors |
| Final ARM64 release build | Passed |
| Signature, package metadata, ZIP alignment, native ABI verification | Passed |
| Hardware/installation/refresh-rate/playback test | **NOT DEVICE-VERIFIED**; no connected Android device |

The full suite initially reported 83 failures and stalled. A desktop Library
row test timed out after ten minutes; subsequent assertions and shutdown errors
increased the reported counter to 86. The runner was interrupted after the long
stall; its shutdown exit code is **not** treated as evidence of success.
The playlist-import line was the last progress message, not the stalled file.
The timeout was in `desktop_library_table_rows_test.dart`.

An isolated unchanged checkout of the imported base reproduced failures in
`library_directory_entries_test.dart` (missing `offline.origin_file_path` in
its SQLite fixture) and `link_phone_sources_test.dart` (asynchronous assertions).
That baseline run had 36 passed / 3 failed. This confirms pre-existing failures;
**not every failure in the full run has been independently isolated**. Original
source/assertions were not changed to bypass these failures.

The 49 selected original regression tests cover `main_shell_rebuild_test.dart`,
`main_shell_keyboard_test.dart`, `mornye_glass_interaction_test.dart`,
`expressive_playback_transport_test.dart`, and `playback_deck_selection_test.dart`.
They support preservation of those behaviors but do not replace physical device
UI/audio testing or a successful full suite.

Logs available in this workspace:

- `/tmp/mornye-performance-tests-final.log`
- `/tmp/mornye-ui-playback-regression.log`
- `/tmp/mornye-android-tests.log`
- `/tmp/mornye-all-tests.log`
- `/tmp/mornye-baseline-tests.log`
- `/tmp/mornye-analyze-final.log`
- `/tmp/mornye-apk-build-verified-source.log`
- `/tmp/mornye-apk-signature.txt`
- `/tmp/mornye-apk-abi-verification.json`

## Verified APK

- Path: `build/app/outputs/flutter-apk/mornye-local-arm64-release.apk`
- Size: **88,377,932 bytes** (88.38 MB; 84.28 MiB).
- APK SHA-256: `9a39c53516c440c325953a28f69ba6c27b698b7155b2b15146a81a3a7e557ecf`.
- Launcher name: **Mornye Local**.
- Application ID: **com.zarz.mornye** (unchanged).
- Version: **5.3.1 (167)**; min SDK 24, target/compile SDK 37.
- Build: **Release**, not debuggable; development/debug signing only.
- Certificate subject: **C=US, O=Android, CN=Android Debug**.
- Certificate SHA-256: `fe6e5e3398814a32a468a2a60a4075490a31a523814aa1242689fbc0f83cb2b2`.
- `apksigner verify --verbose --print-certs`: valid **v2** signature, one signer.
- `zipalign -c -P 16 4`: passed.
- `aapt dump badging`: correct label/package and only `arm64-v8a`.
- All **20** native libraries have ELF64 little-endian AArch64 headers;
  verified `libapp.so`, `libflutter.so`, `libmornye_mobile.so` and `libmornye_audio.so`.
- Verified ABIs: **arm64-v8a only**.

The existing Gradle debug-signing fallback was used without `android/key.properties`.
Gradle generated its standard local development key outside the repository.
No production key was used; no keystore/password/APK was staged or committed.
Structural/signature verification passed; the APK was **not installed on a device**.
An official build signed with another certificate cannot be updated in place
with this development-signed APK.

## Build and diagnostic limitations

- The proprietary Discord SDK was absent. The existing supported
  `MORNYE_DISCORD_SDK=0` stub was used; proprietary Discord functionality is
  unavailable in this APK. The original Rust music backend was built and packaged.
- Android mode APIs do not prove physical panel rate or displayed FPS.
- FrameTiming delivery is batched. Screen/budget attribution uses callback
  delivery; mixed budgets are flagged. Archived windows are explicitly frozen;
  reported display/preferences represent the latest export-time observations.
- Interaction association is observational; absent/mismatched data stays
  unavailable. No causal input-to-photon or build+raster presentation claim is made.
- Transition history is bounded to 32 events and observed while the Activity is
  resumed, with a resume comparison; it is not continuous hardware telemetry.
- No device, Perfetto, SurfaceFlinger presentation, actual refresh-rate honor,
  battery/thermal overhead or physical playback verification was performed.
- The full test failure gate remains unresolved. Source publication was explicitly
  authorized by the user despite this failed/incomplete verification status.

See `PERFORMANCE_HUB.md` for implementation details and a device validation procedure.
