# Bridge deep review

Reviewed source: `5f81d64c` on `desloppify/code-health`, 2026-10-31. This document replaces the earlier deep review at `9d2e7d0`; it corrects several claims and unsafe proposed fixes. It is a static review of app-owned bridge paths supplemented by the host tests below. No production code was changed. No Android device was attached, no APK was built, and device-specific outcomes and native performance remain unverified. Third-party plugin internals, all Rust algorithm internals, and every Android API/ABI combination were not exhaustively audited.

## Bridge inventory and ownership

```text
Dart UI/services
  ├─ backend MethodChannel ── MainActivity / SelectedCoreBackend
  │    ├─ Android ContentResolver, storage, sharing, logcat, UI
  │    └─ NativeDataJobs / RustCoreBackend ── generated UniFFI ── Rust mobile/core
  ├─ library scan EventChannel ── SafScanProgressStream ── Rust scan progress
  ├─ usb_pcm MethodChannel + events EventChannel ── UsbBitPerfectPlugin
  │    ├─ UsbDirectPlayback ── UniFFI UsbDirectOutput ── Rust/libusb
  │    └─ Android playback engines ── Kotlin NativeAudio JNI ── C++ Oboe,
  │       FLAC and WavPack sources
  ├─ audio_route MethodChannel ── UsbBitPerfectPlugin / AudioRouteInfo
  ├─ haptics MethodChannel ── MusicHapticsPlugin
  ├─ audio_output MethodChannel ── MainActivity
  ├─ player_widget MethodChannel ◄── PlayerWidgetProvider
  └─ xyz.luan/audioplayers MethodChannel ── vendored audioplayers plugin
```

The backend channel is shared by several Dart wrappers, including logging (`lib/services/native/native_channel.dart:11`, `lib/services/platform/native_log_source.dart:9`). The widget route is native-to-Dart (`android/app/src/main/kotlin/com/amwolfstein/sistrum/PlayerWidgetProvider.kt:220`). Registrations are in `MainActivity.kt:636-676`, `UsbBitPerfectPlugin.kt:37-55`, and `MusicHapticsPlugin.kt:26`; Dart USB and scan clients are in `lib/services/playback/audio/usb_pcm_bridge.dart:7-12` and `lib/services/native/library_scan_bridge.dart:46`. The app also uses third-party plugins, including audio service and FFmpeg; their internal bridges were not reviewed. No app-owned Pigeon interface or Dart `dart:ffi` route was identified in the searched app sources. Generated UniFFI is Kotlin-to-Rust, not Dart FFI. JNI declarations and native entry points are in `android/app/src/main/kotlin/com/amwolfstein/sistrum/NativeAudio.kt:7-25` and `android/app/src/main/cpp/native_audio.cpp:218-333`; Rust exports are in `rust_backend/crates/mobile/src/`.

Default native ABIs are `arm64-v8a` and `armeabi-v7a`, configurable by environment; Android min SDK is taken from Flutter (`android/app/build.gradle.kts:30-40,94-98,113-115`). Static configuration is not proof of binary or device compatibility. The Android 34 gate on one USB engine is explicit (`UsbBitPerfectPlugin.kt:73-74,95-98`). JNI direct-buffer bounds checks exist (`native_audio.cpp:228-233,319-324`); USB teardown normally joins before closing its connection (`UsbDirectPlayback.kt:291-309`), subject to the hang risk below. No blanket claim is made that every method contract, shutdown path, or native failure is correct.

## Findings

Priority denotes potential impact and urgency, not measured frequency. “Confirmed” describes what the code does; consequences that require timing, failure injection, or a device are explicitly conditional.

### 1. P1/P2 — USB drain can wait indefinitely if pending transfers never retire

`rust_backend/crates/mobile/src/usb_audio/transport.rs:533-550` cancels pending libusb transfers, then ignores event-processing errors while waiting for callbacks to clear all pending slots. `transport.rs:179-187` joins the worker, while `android/app/src/main/kotlin/com/amwolfstein/sistrum/UsbDirectPlayback.kt:291-309` closes the connection only after shutdown. The code path is confirmed; an indefinitely pending transfer following persistent event failure or detach is a plausible, unobserved trigger. It can prevent shutdown and resource release.

**Next:** fault-inject persistent event errors and detach while transfers are pending. Design a bounded, ownership-safe failure strategy with libusb's asynchronous cancellation rules; do not free pending transfers or buffers merely to enforce a timeout.

### 2. P2 — JNI paths use modified UTF-8

`android/app/src/main/cpp/native_audio.cpp:246-250,297-301` passes `GetStringUTFChars` output to filesystem-based decoders (`native_audio.cpp:200-202`, `flac_pcm_source.cpp:18-20`). JNI modified UTF-8 encodes supplementary characters differently from normal UTF-8 filesystem names. Direct paths containing such characters can therefore fail to open even when Kotlin can open the original path (`UsbPcmSource.kt:30-43`). SAF `/proc/self/fd/...` paths are ASCII and are not evidence that every emoji-named file fails. No device reproduction was performed.

**Next:** pass explicitly encoded standard UTF-8 bytes or use a correctly owned descriptor; test FLAC and WavPack direct paths with supplementary Unicode on a device and test descriptor lifetime.

### 3. P2 — SAF lease eviction can close a descriptor still owned by a caller

`android/app/src/main/kotlin/com/amwolfstein/sistrum/MainActivity.kt:525-551` closes the oldest descriptor when the four-lease cap is reached without checking whether it is still in use. Dart retains a lease during asynchronous preparation (`lib/services/playback/music_player/music_player_playback.dart:129-169`). Activity destruction also closes leases (`MainActivity.kt:559-606`). Closing an active descriptor is established by the eviction policy; overlapping requests, recreation, descriptor reuse, and resulting failed or wrong-source playback need controlled reproduction. Generation checks mitigate some stale operations, not the ownership question.

**Next:** test five concurrent/overlapping acquisitions, stale generations, fd reuse, and Activity recreation. Define engine-versus-Activity ownership, explicitly release active leases, and use bounded rejection/backpressure rather than silently closing an in-use descriptor.

### 4. P2 — USB worker panic is not supervised

The spawned USB worker updates shared error state only when `session.run` returns `Err`; its `notify_all` is after that call and is skipped if it unwinds (`transport.rs:67-95`). A panic while holding the mutex can poison it; callers use `unwrap` (`transport.rs:115,130`). Depending on where a panic occurs, a dead worker could leave stale playback state, stall the feeder, or cause further errors; no actual panic trigger or device symptom has been established. UniFFI handling of a panic on an exported-call thread does not supervise this separately spawned thread.

**Next:** inject worker panics both inside and outside the state lock; supervise worker termination, handle poison and cleanup safely, and surface a failure. A watchdog needs pause/underrun semantics and tests to avoid false positives.

### 5. P2 — logcat timeout cannot interrupt the preceding read

`MainActivity.kt:116-124` reads stdout to EOF before calling timed `waitFor`; a process that leaves its pipe open can block before timeout handling. This runs on `Dispatchers.IO` (`MainActivity.kt:700`), so the demonstrated risk is a stuck IO task, not a proven main-thread stall.

**Next:** test with a subprocess that holds stdout open; enforce a deadline and output bound across both reading and process termination, with cleanup of the reader and child.

### 6. P2/P3 — cancellation has unbounded checkpoint gaps

Cancellation is cooperative: the SAF snapshot job checks before each page, then resolves as many as 500 URIs without another lease check (`android/app/src/rust/kotlin/com/amwolfstein/sistrum/NativeDataJobs.kt:51-68`; `MainActivitySafScan.kt:1672-1681`). Rust audio analysis also performs reads between checks (`rust_backend/crates/core/src/native_audio_analysis.rs:11-32`). `CancellationRegistry` has notification machinery (`rust_backend/crates/core/src/cancellation.rs:54-74`), but this does not by itself interrupt a blocked provider or kernel read. Real cancellation latency has not been measured and is not necessarily bounded by file size.

**Next:** test slow/blocking providers and cancellation mid-page; add checkpoints where safe and investigate cancellation-aware I/O while preserving cleanup and commit semantics.

### 7. P2/P3 — backup replacement can discard an existing destination before rename

`lib/services/backup/backup_service.dart:275-281` deletes an existing output before renaming the completed staging file. Names have one-second resolution (`backup_service.dart:290-296`), so reuse is possible. If replacement is attempted and rename then fails, the previous output has already been deleted; this failure is conditional and has not been reproduced.

**Next:** test an existing destination with injected rename failure; design atomic replacement where supported, or preserve/restore the previous file. Separately, the Rust archive's `published` refers to the staging path (`rust_backend/crates/mobile/src/native_backup/archive.rs:107-118`), whereas final publication is the Dart rename (`backup_service.dart:263-276`). The former review's suggested `committed: true` at Rust completion could allow publication after cancellation; do not apply it without defining and testing the end-to-end commit boundary.

### 8. P3 — provider type lookup runs on the main dispatcher

`MainActivity.kt:64,681,915-920` performs `contentResolver.getType` during the main-dispatcher share handler. This can involve provider IPC; a slow provider could block UI, but impact is unmeasured. Move only the provider lookup to IO and keep Android UI operations on main; test failure and Activity lifecycle.

### 9. P3 — engine switching does not await the previous stop

On prepare, `UsbBitPerfectPlugin.kt:58-75` queues a stop and immediately selects and prepares the next engine. The engines use separate handler threads (`UsbDirectPlayback.kt:112-140`, `HiResPlayback.kt:41-70`), so completion order across engines is not established. A transient exclusive-resource conflict is plausible, not reproduced. Test rapid switches and detach, then consider awaiting stop completion with generation and error handling.

### 10. P3 — redundant dispatch branch and potentially contended backend lock

`SelectedCoreBackend.kt:17-23,351` handles `cancelNativeDataJob` before normal application dispatch, making the later branch unreachable through that path. Remove only after contract tests confirm no other caller uses it. `SelectedCoreBackend.kt:78-80,341-347` performs directory acquisition under the same synchronized backend lock used by other operations and shutdown (`:109-115`); contention has not been measured. The old recommendation to move the outer call outside the lock is insufficient because the callee is itself synchronized and can race shutdown. Profile first and design a coordinated lifecycle before changing locking.

## Corrections and performance hypotheses

- **Pre-cancellation is intentional:** `rust_backend/crates/core/src/cancellation.rs:111-124,222-233` records cancellation before acquisition and tests that a later lease is cancelled. The app's data-job adapter forwards cancellation only for active IDs (`NativeDataJobs.kt:16-27`). A stream of arbitrary never-acquired IDs could grow the general registry, but no such app path or impact was established. Do not delete these entries or change this contract without a bounded design and compatible tests.
- **Per-item bridge calls do exist:** ReplayGain batch operations loop over tracks (`lib/widgets/library/batch_track_actions.dart:107-117`); the service performs per-track work in the same file. The previous claim of no per-item traffic was incorrect. Measure actual channel cost against decoding, file I/O and tag writing before proposing batching.
- **Encoding and copies:** `lib/services/native/native_data_jobs.dart:29-55` schedules JSON encoding with `compute` per job and sends bytes separately through the channel; Rust accepts a `Vec<u8>` (`rust_backend/crates/mobile/src/data_jobs.rs:15-21`). Isolate scheduling, serialization and copying may matter for some workloads, but exact copy counts, allocation cost, a 64 KiB crossover and gains from direct buffers have not been measured. Profile before changing transport.
- **Nullable probe results:** `media_file_bridge.dart` and `audio_route_info.dart` use nullable results for different unavailable/failure conditions. A typed result could improve diagnosis, but changing fallback behavior requires product/contract review; this is not established data loss.
- A completed temporary archive is not the final backup. A panic does not execute the worker's post-call notification. The former review's claims to the contrary were incorrect.

## Verification and measurements

On this checkout, these host tests passed: `flutter test --no-pub --reporter expanded test/services/playback/audio/usb_pcm_bridge_test.dart test/platform/native_data_job_bridge_test.dart test/services/platform/native_log_source_test.dart test/platform/native_log_polling_test.dart test/playback/bridge_transport_benchmark_test.dart` — 17 tests. Also, `cargo test --locked -p sistrum-core cancellation` passed 7 matching host tests. The Flutter tests include mocked cancellation ordering, logging, event sharing, and handler/error behavior; they do not run Android, JNI, UniFFI or USB hardware.

The existing `test/playback/bridge_transport_benchmark_test.dart:36-67` uses a host mock messenger, 50 warmups and 1,000 sequential echo calls per payload. One run on this host produced:

| Payload | p50 µs | p95 µs | p99 µs | calls/s | RSS delta bytes |
|---|---:|---:|---:|---:|---:|
| 0 bytes | 34 | 75 | 203 | 12,145.5 | 9,838,592 |
| 1,024 bytes | 45 | 116 | 493 | 11,166.2 | -3,248,128 |
| 65,536 bytes | 35 | 156 | 1,502 | 10,332.4 | 884,736 |

These are noisy test-process mock timings including codec and test overhead, not Android bridge latency or native execution. RSS is a process snapshot affected by GC, not allocation count or peak memory. Concurrent host load is uncontrolled. `integration_test/bridge_latency_benchmark_test.dart` provides an existing device harness but was not run: `adb devices -l` listed no devices. No before/after performance claim is possible because there is no production change or equivalent-device comparison.

For a useful baseline, repeat on the same device, Android version, ABI, build mode, thermal state and commit; record warmups and repeated p50/p95/p99, throughput, allocations, peak/steady RSS and UI responsiveness. Use matched test-only no-op channel, UniFFI and JNI controls plus codec-only and operation-only measurements to separate dispatch from useful work; compare equivalent workloads rather than subtracting host mock figures. Include realistic small/large payloads, cancellation, lifecycle stress, PCM integrity and underruns. Test both configured ABIs and representative supported Android versions.

Missing verification includes native USB panic/detach/event-error injection, lease eviction/recreation and fd reuse, Unicode paths, slow providers and cancellation, logcat timeout, backup replacement failure, engine switching and Android instrumentation. Existing host mocks cannot establish native resource safety.

## Safe implementation phases

1. Add focused fault-injection and lifecycle tests for USB teardown, worker failure, SAF lease ownership and backup publication; reproduce outcomes on device where needed.
2. Review designs for lifetime, error propagation and commit boundaries; implement narrowly, preserving features and intentional pre-cancellation semantics.
3. Address confirmed encoding and bounded subprocess handling, then check cancellation and main-thread provider work with appropriate tests.
4. Establish equivalent-device baselines before considering batching, caching, dispatch or buffer changes; report regressions as well as improvements. Do not replace MethodChannels with FFI/JNI by default, rewrite the audio engine, remove FFmpeg, migrate to Media3, or replace Rust/C++ implementations.
