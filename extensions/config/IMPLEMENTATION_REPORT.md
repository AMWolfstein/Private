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

## Resumed updater batch — 2026-11-11

The historical first-batch results/limitations above describe that earlier commit.
The signed native updater and Android readiness caller are now implemented. The
initial release public key and signed bundled revision1 are provisioned; only the
private signing key remains outside Git. A 24-hour completed-HTTP poll/15-minute
offline retry worker is explicitly started after policy setup, cancelled/joined by
its Backend, and installs only authenticated higher revisions for next initialization.
Repeated checks preserve pending_restart until the revision is active.

Fresh verification: 9 worker tests, 8 configuration tests; full Rust workspace
577 passed/0 failed/8 ignored; affected-crate Clippy all-targets with warnings denied
PASS. Qualified Android app unit check PASS including the readiness tests and actual
regenerated UniFFI bindings on JDK25. Signing CLI verifies bundled revision1; the
own-repository raw configuration endpoint returned HTTP200 anonymously. Fresh
independent code review CLEAN. No APK or physical-device test for this batch.

T005 is complete. This is still not the whole migration: T004 artwork/identity/app
integration and T006 final upstream-tooling review remain unfinished. Schema v1
updates origin settings only; it cannot replace provider parsers/paths/headers.

- 2026-11-11: Final `work.py check auto --base 933e0bd6` PASS (Android root unit tests and Rust PASS; source_changed_during_run=false). App-qualified unit XML totals: 179 passed, 2 skipped, no failures/errors. Java25 test-tool compatibility settings remained outside the repository. No APK built.

## 2026-11-11: inactive native artwork foundation

Code commit: `f08bac0f`. This is a partial T004 implementation, not completion
of the artwork migration. Native Apple artist/album and Deezer artist codecs and
on-demand HTTP clients now exist in `providers/src/artwork/`. Application callers
and artwork JSON settings are still pending. All 13 end-to-end source migrations
remain incomplete; the existing metadata path and all 14 lyric implementations
are unchanged. See `extensions/artwork/README.md` for the precise boundary.

Verification on the final code tree:

- Offline pinned-reference oracle: 20 cases matched.
- `cargo +1.99.1 test --manifest-path rust_backend/Cargo.toml -p mornye-providers artwork --locked`: 12 passed.
- Provider Clippy, all targets, locked, `-D warnings`: passed.
- `work.py check auto`, run `20261111T082335913882Z`: PASS;
  Android unit checks PASS, Rust workspace 589 passed / 0 failed / 8 ignored;
  `source_changed_during_run=false`. The legacy automatic Rust command is
  `cargo test --manifest-path rust_backend/Cargo.toml --workspace`, with
  `RUSTUP_TOOLCHAIN=1.99.1`; it does not add `--locked`.
- Android app unit XML: 181 tests, 179 passed / 0 failed / 0 errors / 2 skipped,
  on Java 25. Root Gradle plugin tests also completed successfully.
- Fresh independent code review: CLEAN in round 3, after fixing two error
  classifications. Both new regressions failed before their fixes: Deezer quota
  errors are not resource misses; malformed Apple catalog envelopes are invalid
  rather than missing. The regression tests are retained in the code commit.

The first resumed automatic run was INCOMPLETE because the shell had no selected
Rust toolchain; Android passed. Explicitly selecting 1.99.1 resolved that environment
issue. No source or test changes were made to suppress it.

No live HTTP integration or physical-device behavior was verified. Retry/token
cache parity and app/JSON integration are pending. No APK was built.


## Owner-directed consolidation and inactive JavaScript removal

The owner selected a new branch, `extension-system-rust-json`, with one combined
commit based on `60af01ad2f2af3e45287ebcd4ef0b906387f01c9`, combining the eleven
commits from `20e04ad1` through `cb7c06e1`. The original `extension-system` history
is preserved. Historical implementation sections above describe their original
snapshots; they do not assert that the removed JavaScript copies still exist.

Removed only inactive `sources/`, CommonJS lyric ports/host draft, JavaScript-only
tests, extraction dependencies and the local development oracle. Retained all
native Rust/app code, golden artwork fixtures, signed JSON, original lyric and
upstream provenance, licences, and the Python review-only update tooling. The
workflow template no longer invokes removed Node/npm tools and proposes PRs to
the new branch. The existing signed-config publication URL is unchanged.

This cleanup does not activate artwork or complete T004/T006. Existing installed
extensions continue using their original application runtime. No APK is built.
