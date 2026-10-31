# Bridge deep review

Scope: every app-owned boundary between Dart, Android (Kotlin, JNI/C++) and the Rust backend (UniFFI), plus the vendored-plugin channels that the app calls directly. Static review of the working tree at `9d2e7d0`, with cross-checks against the host test files. This is a code review, not a device test: no Android device was attached, and no Rust, Flutter or Kotlin test suite was run for this document.

This supersedes the open items in `BRIDGE_AUDIT.md`. Its paths are stale after the `9d2e7d0` folder reorganisation: `NativeDataJobs.kt` and `SelectedCoreBackend.kt` now live under `android/app/src/rust/kotlin/`, and the Dart bridge tests moved under `test/platform/`, `test/services/platform/` and `test/playback/`.

## 1. Method

1. Inventoried every boundary: Dart `MethodChannel`/`EventChannel` clients (10), Kotlin handlers (`MainActivity`, `UsbBitPerfectPlugin`, `MusicHapticsPlugin`, `PlayerWidgetProvider`, `SafScanProgressStream`), the UniFFI exports in `rust_backend/crates/mobile` (≈18 exported items), and JNI entry points in `native_audio.cpp` (18).
2. Cross-checked method names: every Dart `invokeMethod` name against Kotlin `when` branches across all Android source sets.
3. Read every boundary function that takes a path, a descriptor, a byte buffer or a lease, and traced its error and cancellation behaviour end to end.
4. Checked threading: which dispatcher each Kotlin branch runs on, which Rust worker threads exist, and which locks guard which state.
5. Checked the call frequency of every polling and per-item path from Dart.

## 2. Verified correct (no action)

- **Channel contract.** Every Dart method name has a Kotlin handler. The three names without a Kotlin `when` match are on other channels: `pulse` (haptics plugin), `show` (audio-output channel, `MainActivity.kt:638`) and `setEqualizer` (vendored `audioplayers`). Several Kotlin branches are reached through helpers that pass the name as a variable (`nativeInvokeMap`), so they are not dead.
- **No per-item channel traffic.** The only bridge call inside a loop is `safExistsBatch`, and it is already batched (`file_access.dart:73`, `playback_provider.dart:170`).
- **Polling is bounded.** Direct-USB position is 200 ms and guarded by `_polling` (`music_playback_deck.dart:404`). Equalizer pushes are debounced 32 ms and serialised (`:121-139`). Logs poll every 800 ms only while the Log page is open (`logger.dart:25`, `log_page.dart:60/67`). The widget sends on track or transport change only and dedupes by payload key (`player_widget_service.dart`). Audio-route reads happen on sheet open only.
- **Data job cancellation is ordered.** `NativeDataJobs.acquire` runs before the IO hop, and channel messages are FIFO, so a cancel sent after dispatch reaches the lease. `NativeDataJobs.cancel` forwards only for active IDs (`NativeDataJobs.kt:33-37`), so unknown IDs cannot create registry entries from the app path.
- **Commit rule.** `data_jobs.rs:44-50` re-checks cancellation only when the result lacks `committed: true`. Every write operation that publishes state returns `committed: true` (`native_playlists.rs:52`, `native_playlist_write.rs:109`, `native_collections.rs:166`, `native_library.rs:615,725`, `native_backup/collections.rs:210`, `native_backup/archive.rs` see F2).
- **JNI string lifetime.** Each `GetStringUTFChars` has a matching `ReleaseStringUTFChars` on every path (`native_audio.cpp:247-260`, `298-306`).
- **JNI direct buffers are bounds-checked.** `writeOboe` requires `offset <= size && count <= size - offset` (`:230-232`); `readFlac` caps capacity at 256 KiB (`:322-323`).
- **USB shutdown order.** `closeSource` and `fail` call `output.shutdown()` (which joins the worker) before `connection.close()` (`UsbDirectPlayback.kt:295-298`, `:305-308`). The worker never sees a closed descriptor.
- **USB writes never block the caller.** `Output::write` is non-blocking and bounded (`transport.rs:110-127`, frame-aligned, ≤256 KiB per call). The Kotlin feeder checks `availableBytes` before copying (`UsbDirectPlayback.kt:231`).
- **Logs are bounded.** The buffer keeps 500 entries and truncates messages at 4000 characters (`sistrum_local/logging.rs:27-28`, `:229-230`).
- **Shared Kotlin backend state is synchronised.** The directory-scope map is only touched inside `synchronized(this)` (`SelectedCoreBackend.kt` acquire/release), and `manager` access goes through `@Synchronized owner()` or `synchronized(this) { manager }`.
- **Panic strategy.** No `panic = "abort"` is set, so a Rust panic in an exported call becomes a UniFFI error rather than a process abort.
- **Widget disk writes** use SharedPreferences `commit()` on the widget's single worker thread (`PlayerWidgetProvider.kt`), not on main.

## 3. Findings

Severity: **P1** data loss or wrong audio; **P2** correctness or silent failure with a plausible path; **P3** contract, cleanup or measured-later cost.

### F1 — P2: a panic in the USB worker stalls playback silently

`transport.rs:67-95`: the iso worker thread runs `session.run(&state)`. The only path that records a failure is an `Err` return (`s.error = Some(error)`). A panic unwinds past that code: `error` stays `None`, `playing` stays true, and `notify_all` is still called by the thread closure, but nothing marks the session failed.

The Kotlin feeder then loops. `fill()` sees `availableBytes() < count` and returns (`UsbDirectPlayback.kt:231`). The pump keeps rescheduling. `frames()` stops advancing, so `complete` never fires and no `paused`/error event is emitted. The user sees playback frozen with the state still "playing".

- Trigger: any panic in the session loop (not identified yet; any `unwrap`, index or arithmetic path there qualifies).
- Fix: wrap `session.run` in `catch_unwind` and set `s.error` and `s.playing = false` on panic. On the Kotlin side, add a no-progress watchdog: if `frames()` has not advanced for N seconds while `playing`, fail the session.
- Verify: a host-side test that injects a panic in the session loop behind a test-only hook, and asserts that the next `available_bytes()`/`write()` returns an error.

### F2 — P3: backup archive returns without `committed`

`native_backup/archive.rs:114-115` ends with `check()?` and then `Ok(json!({"published": true, ...}))`. It has no `committed: true`, so `data_jobs.rs:47` re-runs `check()`. If cancellation lands in that window, the job reports `CANCELLED` although the complete archive was written to `partFile` (`backup_service.dart:263-266`).

Impact is limited. Dart's `finally` deletes `partFile` (`backup_service.dart:281`), so no stray file remains, and the user did ask to cancel. The only effect is that a backup which had finished is reported as cancelled. Fix: add `"committed": true` to the success value so the final check is skipped after publish.

### F3 — P2: JNI modified-UTF-8 used as a filesystem path (open, carried from BRIDGE_AUDIT #1)

`native_audio.cpp:247` (`openWavPack`) and `:298` (`openFlac`) pass `GetStringUTFChars` output to `DsdDecoder`/`FlacPcmSource`. JNI returns modified UTF-8, where supplementary characters (emoji and other non-BMP code points) are two surrogate sequences of three bytes each. Linux paths use standard UTF-8, so a non-BMP filename on the direct-path route fails to open. Kotlin (`UsbPcmSource.kt:30-43`) already opened the real path, so the failure surfaces as a fallback or error, not as wrong audio.

- Fix: convert with `String.getBytes(UTF_8)` on the Kotlin side and pass a `byte[]`, or open the file in Kotlin and pass its `/proc/self/fd/N` descriptor (the same route SAF uses).
- Verify: device fixture with an emoji filename on a FLAC and a DSD file.

### F4 — P2: SAF lease cap evicts leases that are still in use (carried from BRIDGE_AUDIT #5)

`MainActivity.kt:536-544` evicts the oldest playback lease when there are four, and `closeSafPlaybackLease` closes its descriptor. Dart keeps a `/proc/self/fd` lease through asynchronous source preparation (`music_player_playback.dart:129-169`). A fifth open during that window closes the descriptor Dart is about to duplicate.

- Impact: wrong source or a failed open, depending on timing. Not yet observed.
- Fix: refcount leases and evict only unreferenced ones, or raise the cap with a clear failure when everything is in use. Do not extend descriptor lifetime without an owner and a shutdown path.
- Verify: host test that holds five leases and asserts that the first remains readable.

### F5 — P2: logcat read can block the IO worker (carried from BRIDGE_AUDIT #3)

`MainActivity.kt:116-126` reads all of `logcat`'s stdout (`readText()`) before `waitFor(timeout)`. A stuck `logcat` that keeps the pipe open blocks in `readText` and never reaches `destroyForcibly()`.

- Fix: start a reader thread with a bounded buffer, then `waitFor` with the deadline and destroy on timeout; or read with a byte cap and a deadline.
- Verify: an instrumented/host test with a subprocess that keeps stdout open.

### F6 — P2: cancellation is cooperative only; its wake-up path is dead

`sistrum_core/cancellation.rs:57-58, 63-64`: `Shared` has a `Condvar` (`changed`) and a `threads` list. `notify()` calls `notify_all()` and unparks registered threads, but nothing waits on the `Condvar` and nothing ever pushes into `threads`. Cancellation is therefore a flag that code must poll.

Consequences:
- A worker blocked in I/O is not woken. `analyze` reads up to the size limit before its `check()` (`native_audio_analysis.rs:24-36`), and `media/audio.rs` uses `read_exact` without checks between reads. Latency is bounded by file size and provider speed, not measured.
- The 30 checks in the crate are the only cancellation points. `NativeDataJobs.kt:67-68` checks per page and then calls `getSafFileModTimes` on up to 500 entries with no check inside (BRIDGE_AUDIT #4).

Fix: either delete the unused `changed`/`threads` machinery to make the design honest, or implement the wake-ups and call them from blocking points. Add checks inside the SAF timestamp loop.

### F7 — P3: `cancel` creates registry entries for IDs that were never acquired

`cancellation.rs:111-123` (`cancel_many`) inserts an `Entry` with `references = 0` for any ID. `release` only removes an entry when its references reach zero during a release, so an entry created by a late cancel is never removed. A later `acquire` with the same ID is born cancelled.

Not reachable from the app's data-job path, because Kotlin's `NativeDataJobs.cancel` guards on active IDs. It is reachable through the public registry API. Fix: only mark IDs that have live references, or remove zero-reference entries on cancel.

### F8 — P3: null means failure in two bridges (AGENTS "Failure signalling" rule)

- `media_file_bridge.dart:120` (`probeSafTreeReadAccess`) returns `bool?`, where null means "provider could not confirm". Its only caller treats null as "keep the source visible", which is a tri-state carried by null.
- `audio_route_info.dart:193` (`readAudioRouteInfo`) returns null for both "no platform implementation" and "the call threw".

AGENTS.md requires a lookup's null to mean only "not found", and a failure that the user can see to return a typed result. Fix: a small sealed result (`Available`, `Unavailable(reason)`, `Denied`) for the probe, and a typed `AudioRouteResult` for the route read.

### F9 — P3: dead cancel branch in Kotlin

`SelectedCoreBackend.kt:351` (`"cancelNativeDataJob" -> …` in `invokeApplication`) is unreachable: `dispatchBackendApplication` handles `cancelNativeDataJob` first and returns (`SelectedCoreBackend.kt:18-23`). Remove the branch.

### F10 — P3: `shareContentUri` queries the provider on the main thread

`MainActivity.kt:915-920` calls `contentResolver.getType(uri)` inside the `scope.launch` on `Dispatchers.Main`. The branch is one of nine without `withContext(Dispatchers.IO)` (the others are trivial or UI work). `getType` is a provider IPC. Fix: move the lookup into `withContext(Dispatchers.IO)`.

### F11 — P3 (measure first): one isolate spawn per data job

`native_data_jobs.dart:41` runs `compute(_encodeJsonInBackground, request)` on every job. Twelve call sites use `NativeDataJobs.run`, including per-track paths such as lyrics parsing (`lyrics_parser.dart:90`) and palette extraction. `compute` starts an isolate each time, which costs time on low-end devices.

Do not change this without a measurement. A reasonable candidate is to encode on the UI isolate when the request is small (for example under 64 KiB), and keep `compute` for large requests. Measure spawn cost and p95 on a device before and after.

### F12 — P3 (measure first): three copies for picture and cover bytes

Bytes travel Dart `Uint8List` → `StandardMessageCodec` → Kotlin `ByteArray` → UniFFI `Vec<u8>` (`native_data_jobs.dart`, `data_jobs.rs`). Covers and pictures are the large case. A direct buffer or file handoff would remove two copies. Same rule as F11: measure allocations and RSS first.

### F13 — P3: directory-scope acquire holds the backend lock while opening

`SelectedCoreBackend.kt` (`acquireMediaDirectory`) runs `openMediaDirectory` inside `synchronized(this)`. `owner()` and the scan entry points are also `@Synchronized` on the same object, so a slow directory grant delays library calls. Move the grant outside the lock and insert the scope under it.

## 4. Gaps in this review

- Not reviewed in depth: the Rust scan and lyrics internals (`native_library.rs` 734 lines, `native_lyrics.rs` 1180 lines), the tag writer, and the libusb descriptor parser. They were covered only at the boundary.
- Third-party channels (`audioplayers`, `audio_service`, `ffmpeg_kit`, `shared_preferences`, `url_launcher`) are not audited internally.
- No test or build was run for this document. `scripts/check_rust_backend.sh`, `scripts/check_android.sh` and `flutter test` are the commands to run after any fix.
- Nothing here is measured on a device. Every performance item (F11, F12) is a hypothesis until profiled.

## 5. Order of work

1. F1 and F4: playback correctness, both need a test first.
2. F3 and F5: small, self-contained, testable on the host.
3. F6 and F7: design cleanup in the core crate.
4. F2, F8, F9, F10, F13: contract and hygiene fixes.
5. F11 and F12: only after an on-device baseline.
