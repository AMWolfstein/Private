# API compatibility audit — transport chunk

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

Source: `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`. Role: `.claude/agents/api-compat-auditor.md`. Independent current-source assessment; old findings not consulted. Audio-engine methods excluded.

## Read ledger

| Path | Lines read |
|---|---|
| lib/services/platform_bridge.dart | 1–352, 392–874 |
| lib/services/library_native_adapter.dart | 1–414 |
| lib/services/activity_attachment.dart | 1–32 |
| lib/services/native_cache_maintenance.dart | 1–29 |
| lib/services/native_log_source.dart | 1–30 |
| android/app/src/main/kotlin/com/amwolfstein/sistrum/MainActivity.kt | 57–118,126–219,332–461,486–495,558–608,666–889,902–1345; non-engine handlers |
| android/app/src/rust/kotlin/com/amwolfstein/sistrum/NativeDataJobs.kt | 1–108 |
| android/app/src/rust/kotlin/com/amwolfstein/sistrum/SelectedCoreBackend.kt | 1–365; non-engine dispatch, explicit endpoint expansion |
| rust_backend/crates/mobile/src/lib.rs | 1–20 |
| rust_backend/crates/mobile/src/data_jobs.rs | 1–73,103–184 |
| rust_backend/crates/mobile/src/cancellation.rs | 1–79 |
| rust_backend/crates/core/src/cancellation.rs | 1–289 |

## Findings

None validated in this chunk. Request keys/bytes, request IDs, spill-file map decoding, NDJSON count/error-count validation, staged versus durable publication, nullable SAF access and numeric log indexes agree at the inspected endpoints. Coordinator directly re-read PlatformBridge 118–165 and NativeDataJobs 12–108 to check cancellation/request dispatch guards.

## Evidence and remaining chunks

- Graphify query `runNativeDataJob cancelNativeDataJob`: exit 0, 11 nodes; existing graph reported fresh from `46c4ea6a`. Graph navigation only; direct source is authoritative.
- Python scripts suite: `python3 -m unittest discover -s scripts -p 'test_*.py' -v`: 28 passed, exit 0; evidence `/tmp/fresh-audit-python.log` in this instance. This validates review/build helpers, not application contracts.
- Flutter execution BLOCKED: toolchain absent, official Flutter download host CONNECT denied (403). No generated-binding drift, Kotlin compiler or Android device execution claimed.
- Remaining: SAF payload producers/import consumers, native-library request schemas, cache/log payload bodies, generated UniFFI drift, dedicated backup/settings contracts. These are scheduled in later audit units.

Result: PASS for static transport chunk; overall contract coverage remains partial.
