# Rust + JSON migration: first batch

Status: **INCOMPLETE migration; validated native lyrics configuration batch**.
Base: `933e0bd6fbc00899372a815a74ab6fffc3a5fe73`, branch `extension-system`.

## Implemented

- Bundled, versioned JSON origin settings used when constructing the 14 existing
  native lyric providers. Their algorithms and original Rust source files remain.
- Complete-inventory/schema/size/duplicate-key and HTTPS service-boundary validation.
- Ed25519 signed-envelope verification with app-bundled public-key ownership.
- Native-only serialized installation, atomic replacement, startup fallback
  diagnostics and activation at next Backend initialization.
- Cache persistence separated by configuration revision; current jobs and token
  state are never hot-swapped.
- Native validate/sign/verify operator tool and rejection/restart/CLI tests.
- Android Gradle inputs include the JSON assets embedded in the Rust library.
- Upstream review documentation now describes native Rust/schema adaptation.

## Not implemented

- Native ports of the 13 artist-artwork sources and Apple's additional album,
  motion/logo/editorial capabilities. JavaScript references remain inactive.
- Local artist/album-to-provider identity resolution and artwork app integration.
- Automatic configuration downloads or a Dart/Kotlin installation caller.
- Production signing identity provisioning: trusted-keys.json is intentionally empty.
- Path, header, timeout, provider order/enablement or parser configuration. Schema v1
  only supports tightly constrained origin substitution; it cannot repair arbitrary
  provider changes. See README.md for supported origin groups.

No code has been deleted on the assumption that unfinished replacements work.
No upstream repository was modified and no application/device release was published.

## Verification

| Check | Result |
| --- | --- |
| Native providers before changes | 75 passed, 4 ignored |
| Final Rust workspace, cargo +1.99.1 test --workspace --locked | 568 passed, 0 failed, 8 ignored |
| Provider crate targeted tests | 83 passed, 4 ignored; operator CLI integration test also passed |
| New Backend installation/restart tests | 3 passed |
| Clippy, affected crates/all targets, -D warnings | PASS |
| Existing JavaScript reference/import tests | 101 passed |
| Upstream watcher/publisher tests | 17 passed |
| Android :app:testDebugUnitTest | 176 passed, 0 failed/errors, 2 skipped, 33 suites |
| flutter build apk --debug | PASS |
| work.py check auto (selected Android + Rust) | INCOMPLETE: root plugin tests fail; Rust PASS |
| Flutter analyzer/Dart tests | Not rerun; no Dart files changed |
| Physical Android device / live service equivalence | Not tested |

The root Android selector includes third-party plugin tests. The initial failure
was inability to create `/home/agent/.robolectric-download-lock`. With a writable
JVM home, flutter_local_notifications' Robolectric 4.14.1 failed on Java class
major version 69. Temporary plugin-JDK21 attempts instead failed loading classes
compiled for 69 on a runtime supporting 65. Five bounded attempts were made.
The app's qualified tests and APK build passed on JDK25. No selector or application
dependency was modified to turn these failures into a pass. Full root-plugin
baseline was not run on the unmodified branch before these changes.

Temporary compatibility settings were outside Git in `/tmp/mornye-json-gradle/`
and JVM home `/workspace/.toolchains/robolectric-home`. They are not application
configuration. Raw logs remain ignored under `.work/`.

Both independent code reviewers returned CLEAN for the implemented batch. The
architecture record remains in build phase with unfinished tasks; it is not marked
ship/done. Ordinary restart and atomic replacement are tested; parent-directory
power-loss durability is explicitly not claimed.

Native implementation commit: `0363d733aec85ea12e251ba1b4b18e8b219b149f`. Documentation/process records are committed separately.
