# Concurrency audit — non-engine native-job lifecycle

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

Baseline: `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`. Reviewer definition: `.claude/agents/concurrency-auditor.md`. No old findings consulted; audio engine excluded.

## Exact read ledger

| Path | Lines |
|---|---|
| lib/services/platform_bridge.dart | 1–310,750–874 |
| lib/services/activity_attachment.dart | 1–32 |
| android/app/src/main/kotlin/com/amwolfstein/sistrum/MainActivity.kt | 57–115,126–258,332–440,558–610,685–775,1306–1345; non-engine only |
| android/app/src/rust/kotlin/com/amwolfstein/sistrum/NativeDataJobs.kt | 1–108 |
| android/app/src/rust/kotlin/com/amwolfstein/sistrum/SelectedCoreBackend.kt | 1–119,286–365 |
| rust_backend/crates/mobile/src/cancellation.rs | 1–79 |
| rust_backend/crates/mobile/src/data_jobs.rs | 1–184; audio-analysis internals excluded |
| rust_backend/crates/core/src/cancellation.rs | 1–430 |
| lib/main.dart | 1–100; attachment caller only |
| android/app/src/test/kotlin/com/amwolfstein/sistrum/NativeDataJobsTest.kt | 1–150; test source inspected, not executed |

## Findings

None in this bounded chunk. Confirmed Dart cancellation during encoding, Kotlin lease acquisition before IO queueing, synchronized same-ID registry, identity-checked idempotent release, completed delta ownership before cancellation checks, `finally` spill cleanup, and committed-result cancellation exemption. Coordinator re-read PlatformBridge 118–165 and NativeDataJobs 12–108.

## Verification and limitations

Static inspection PASS for this scope. Graphify query `NativeDataJobs cancellation` narrowed after truncation to path-qualified `CancellationRegistry`; ambiguous unqualified result was not used as evidence. Existing queued/shared-ID tests inspected, NOT RUN. Activity recreation, blocking-IO coroutine interruption, device leaks, Kotlin compilation and Flutter execution NOT RUN. No runtime happens-before or device-level guarantee claimed. Producer atomicity and unrelated state lifecycles remain in later units. Read-only enforcement prompt-only.

Prior checkpoint `0efa84d` pushed successfully to `origin/ccr-2fb644cd-nmesyt`; this report is a separate audit-kind checkpoint.
