# Android FFmpegKit startup patches

Baseline: pub.dev `ffmpeg_kit_flutter_new_audio` 2.5.7, matching the previously
locked dependency. The audio AAR remains `ffmpeg-kit-audio:2.2.3`. This vendor
copy contains the Dart API and Android implementation only; no new native
codec package or conversion feature is introduced.

Adapted from upstream Mornye v5.3.0 commits `fde03233` and `71c7de52`:

- Engine attachment registers the channel without touching FFmpegKitConfig or
  loading its native libraries.
- The first method call starts shared callback registration on the executor.
  Calls received during loading retain arrival order and resume on the main
  looper after registration.
- Direct native callers can use `ensureGlobalCallbacksRegistered()` before
  wrapping global callbacks. Registration is synchronized and never replaced
  after a caller wraps it. Sistrum has no download finalizer to port.
- Load failure is logged and pending/subsequent calls receive the established
  unavailable-plugin response; attaching an engine still succeeds.

Three host-JVM tests cover deferred worker loading, queued reply order/main
looper, direct native caller registration and load failure. Each test class
uses its own JVM because registration is process-global. Stand-in Android
classes under `android/src/test` are test-only. Gradle unit tasks do not build
an APK. Cold-start/device latency and real FFmpeg callback behavior still need
an installed-device check; no upstream timing numbers are claimed here.

The package's original LICENSE and attribution are retained. Its Dart API is
unchanged; root analysis excludes this vendored dependency consistently with
other vendor packages. Compare these patches before changing package versions.
