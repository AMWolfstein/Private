# Plan 001-android-arm64-only: Android arm64 only

## Summary

Keep the Android app and its arm64-v8a Rust backend. Remove the Flutter iOS, macOS, Windows and Linux projects,
the desktop Rust crate and its FFI loader, the armeabi-v7a target, the desktop/iOS build, packaging and CI
definitions, the desktop-only Dart code and the plugins only those platforms use. Discord SDK stays (owner decision,
removed later).

## Current system

- Backend selection: `lib/services/backend/backend_channel.dart:46` chooses `RustFfiBackend.shared` on desktop and
  `MethodChannelBackend.shared` otherwise. Android always takes the MethodChannel path. The FFI path is desktop only.
- FFI loader: `lib/services/backend/ffi_backend_transport.dart:81` opens the desktop library; `crates/desktop` is
  its C ABI. Nothing on Android calls it.
- Android Rust backend: `crates/mobile` through UniFFI (`scripts/build_rust_backend.sh` Android branch,
  `rust_backend/target/android/jniLibs`), arm64-v8a and armeabi-v7a today.
- Platform checks: about 146 Dart files reference iOS, macOS, Windows, Linux or desktop platform checks (inventory
  in the change log). Desktop-only files: `lib/widgets/desktop/`, `lib/services/link/desktop/`, `lib/services/desktop_*`,
  `lib/services/media_session_desktop.dart`, `lib/services/ffmpeg_desktop.dart`, `lib/utils/desktop_*`,
  `lib/utils/windows_path_identity.dart`, iOS-only files (`ios_container_paths.dart`, `ios_library_folder_sheet.dart`,
  `link_ios_now_playing.dart`), and their tests and integration tests.
- Build and CI: `scripts/build_ios.sh`, `scripts/package_*`, `scripts/embed_*`, `scripts/fetch_desktop_ffmpeg.sh`,
  `scripts/setup_macos_signing.sh`, `.github/workflows/desktop.yml`, iOS and desktop jobs in `ci.yml` and
  `release.yml`.

## Design

- Ownership and dependency direction: unchanged. Dart calls the backend through `MethodChannelBackend` only; Kotlin
  and the Android Rust library keep their owners.
- Contracts across Dart, Kotlin and Rust (methods, fields, units, errors): unchanged. Only the desktop FFI transport
  goes; no MethodChannel method, payload or error code changes.
- State, threads, lifecycle and cancellation: unchanged on Android. Removed desktop code had its own lifecycle; its
  removal is the only change.
- Failure: unchanged on Android. Typed failures (unsupported, not found, permission, cancellation, failure) keep their
  mapping in `MethodChannelBackend`.
- Data compatibility (song IDs, schema, backups, preference keys): unchanged. No migration. Desktop-only storage
  (sqflite_common_ffi) is removed from the dependency list; Android keeps the sqflite plugin.
- Removal: each removed path is listed in the tasks. The proof is a search for the removed symbols and paths with no
  match outside the change records, plus `flutter analyze` with no missing import.

## Decisions

- PD-1: Remove `crates/desktop` from the Rust workspace and delete it. Rationale: owner asked for desktop removal;
  an excluded crate would stay as dead code. Alternatives considered: keep it excluded from the build (rejected,
  dead code kept in the source).
- PD-2: Build the Android Rust library for `aarch64-linux-android` only. Rationale: FR-001/FR-002. Alternatives: keep
  armeabi-v7a behind a flag (rejected: owner asked for arm64 only).
- PD-3: Keep the Discord SDK code and its Lite switch unchanged. Rationale: owner said it will be removed later.
- PD-4: Remove `RustFfiBackend` and `FfiBackendTransport` and keep only `MethodChannelBackend`. Rationale: Android
  never uses the FFI path. Alternatives: keep for tests (rejected: tests of dead code).

## Constitution check

- [x] I. Owner decisions and removed features respected (owner confirmed removal; Discord kept)
- [x] II. Every step has a check; device-only behaviour listed as pending
- [x] III. Root cause stated (not a bug; removal). Smallest complete change; never-cut list untouched
- [x] IV. Tests for removed behaviour are deleted with their code; Android tests kept and must still pass
- [x] V. Failures typed and distinguishable: unchanged
- [x] VI. Boundary contracts unchanged; the MethodChannel contract keeps its tests on the Android side
- [x] VII. Originals survive failure; IDs, schema, backups and keys unchanged
- [x] VIII. Independent review planned (architecture size)
- [x] IX. No speculative layers; removal only
- [x] X. Commits: code first, then records; no push or APK without the owner

## Complexity tracking

| Deviation | Why needed | Simpler option rejected because |
|---|---|---|
| none | | |

## Verification plan

- Host checks: `analyze`, `dart-tests` (Flutter test profile), `rust` (cargo workspace test), `workflow` (work tests).
  The `android-unit` check requires `android/gradlew`, which the repository does not contain; it is reported as BLOCKED
  until the owner adds a wrapper or the check is changed.
- Searches (SC-002): no iOS, macOS, Windows, Linux or desktop platform reference outside the change records.
- Device checks for the owner: install the arm64-v8a APK on an arm64 Android device and open the library, playback
  and settings screens. Pending until the owner runs it.

## Open choices for the owner

- none
