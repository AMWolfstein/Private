# Mornye Local performance diagnostics

Production entry point: Settings → App → Performance Hub. Monitoring, HUD and
first-interaction analysis default off and use the existing AppSettings JSON
persistence. The Android application ID, native namespaces and original Mornye
glass/playback implementations are unchanged.

## Display preference

`PreferredDisplayController` requests the closest supported mode within 1Hz of
60Hz **at the currently active physical resolution** using the Activity window's
`preferredDisplayModeId`. If none exists it clears the preference; it never
selects a different resolution. It reapplies on resume, focus and display events,
registers a DisplayManager listener on resume and unregisters on pause/destroy.
It does not recreate the Activity, change global settings or schedule Flutter
frames. Android can override the request.

The isolated `com.zarz.mornye/performance_display` channel returns requested mode,
active Display.Mode, Display.getRefreshRate(), same-resolution supported rates,
and up to 32 timestamped observed mode transitions. Dart reads once at startup;
subsequent updates are native events. Reset is a user-triggered native call.
Transitions while the Activity is paused are not continuously observed; a changed
mode on resume is recorded. These are Android API observations, not physical
panel/presentation measurements. History lasts for the Activity instance.

## Collector and interpretation

One Riverpod-owned collector registers SchedulerBinding.addTimingsCallback only
while enabled and foreground, and unregisters on pause/disable/disposal.
UI/capture timers are suspended while paused and resume only when enabled.
Rolling elapsed time includes background idle; it is never classified as jank. The bounded rolling buffer is
at most 16,384 frames / 60 seconds in the active window, plus at most eight
frozen previous-screen windows with the same per-window bound. There are no per-frame channel calls, disk
writes, setState/notifications or frame requests. Live subscribers update once
per second; no UI update timer runs without subscribers. Percentile series are
sorted once per snapshot. The HUD uses IgnorePointer, plain solid Material/Text,
and no animation/blur/glass. Original child identity is preserved when toggling.

* FPS is received FrameTiming samples / elapsed rolling time. It includes idle
  and measures Flutter frame production, never SurfaceFlinger presentation FPS.
* Build/raster/totalSpan come from FrameTiming. Total span is not build+raster
  and is not physical presentation latency.
* Gaps use successive engine vsyncStart timestamps, never mixed with Dart clock
  timestamps. Long idle gaps and low idle FPS are not classified as jank.
* Slow/jank means build OR raster exceeds that sample's reported Android active
  mode budget (1000 / reported Hz). Span exceedance is reported separately.
  Missing native data stays unavailable. Mixed-rate windows are flagged. Timing
  delivery is batched, so budget and screen attribution use callback delivery
  and may be approximate at a transition.
* Root and active nested navigator/tab changes supply route context. Unnamed
  detail routes report unavailable, never private track/artist names. Changing
  screen starts a new rolling window so its FPS denominator belongs to that screen.
  The last eight previous-screen windows remain frozen and selectable in the Hub
  for viewing/copy/export. Disabling freezes collected data; enabling starts a new
  session. Reset clears both live and archived windows.
* Glass is identified as original_mornye. Read-only theme style, clarity/outline
  preferences and motion-artwork preference are reported at export time; actual
  per-surface parameters and animated-background playback remain unavailable. No glass paths/parameters are modified.

## Optional first interaction

A passive root Listener observes pointer down/move/signal without a gesture
recognizer. After the configurable idle threshold (default 3000ms), a capture
records raw pointer event time separately from Dart callback receipt/UTC time.
One passive addPostFrameCallback observes the next frame without requesting it.
The reported delay is pointer **callback receipt → observed post-frame callback**,
not input hardware latency or pointer-to-photon. Raw engine timestamps associate
subsequent FrameTimings; unavailable/unmatched data remains unavailable.

Each capture covers at most 1000ms after the pointer observation, with a short
1500ms observation cleanup timer, at most 512 timing samples and eight captures.
Late timing batches can still fill retained captures using their engine-time
window while monitoring and interaction analysis remain enabled. No
next frame means no invented latency. Reset/disable invalidates queued observers
and cancels timers. The exported report includes capture frame/gap/slow data and
native mode events within -500ms/+1500ms of each interaction, using UTC for the
cross-source event association (wall-clock changes can affect that association).

Copy/export are explicit user actions. Export uses the existing file_picker
save dialog and plain UTF-8 text. No report is written per frame. The report
records the actual build mode and runtime ABI, not assumed values.

## Validation and device procedure

Automated tests cover percentile/gap/budget/rolling/capture/settings/report
logic, collector registration/disposal, native event delivery, route context,
HUD pointer transparency, native mode selection and transition history.
The original Flutter suite provides UI/playback regression coverage; this does
not replace playback or refresh testing on hardware.

On a device, compare monitoring off/on with HUD off, then on, using identical
scroll/playback workload. Confirm requested_hz=60 separately from reported_hz;
check native mode transitions after pause/resume/focus and device rotation. Test
a display without a same-resolution 60Hz mode. Confirm idle is not shown as
jank, capture first scrolling/taps after >3s idle, and copy/export reports. Verify
original liquid-glass appearance and actual playback. Use Perfetto/SurfaceFlinger
if physical presentation or pointer-to-photon evidence is required.

## Local ARM64 build

Use the repository-pinned Flutter/Rust, JDK25, Android SDK37, NDK30 and CMake4.1.2.
The repository already falls back to the standard development/debug signing key
when `android/key.properties` is absent. Do not stage signing/environment files.
An absent proprietary Discord SDK can use the existing supported stub:

```sh
export MORNYE_RUST_ANDROID_ABIS=arm64-v8a
export MORNYE_DISCORD_SDK=0 # only if the proprietary Discord SDK is unavailable
# Point LIBCLANG_PATH and CLANG_PATH at the installed NDK's lib and bin/clang
# if host Clang lacks Android-compatible resource headers.
flutter pub get
flutter analyze
flutter test
bash scripts/build_rust_backend.sh android
flutter build apk --release --target-platform android-arm64
```

Verify the resulting APK with Android apksigner and inspect every `lib/` ZIP
entry, including the Rust library, for arm64-v8a only. Copy the verified APK to
`build/app/outputs/flutter-apk/mornye-local-arm64-release.apk`. Development signing
does not permit replacing an installation signed with a different certificate.
