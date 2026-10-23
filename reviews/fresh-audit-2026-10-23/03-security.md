# Security audit — channel/file trust boundaries

Baseline `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`; role `.claude/agents/security-auditor.md`, using `.claude/skills/audit/SKILL.md`. Independent current implementation; no old findings imported. Audio engine excluded.

## Read ledger

| Path | Lines |
|---|---|
| lib/services/platform_bridge.dart | 1–260,288–484,615–710,760–874 |
| lib/utils/file_access.dart | 1–169 |
| android/app/src/rust/kotlin/com/zarz/spotiflac/NativeDataJobs.kt | 1–108 |
| android/app/src/main/kotlin/com/zarz/spotiflac/NativeMediaWorkspace.kt | 1–48 |
| android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt | 110–175,325–425,558–585,678–879,902–1020,1038–1075; audio handlers excluded |
| android/app/src/main/kotlin/com/zarz/spotiflac/MainActivitySafIo.kt | 1–327,357–436 |
| rust_backend/crates/mobile/src/data_jobs.rs | 1–73,103–184; engine-analysis internals excluded |
| rust_backend/crates/mobile/src/native_cache.rs | 1–19 |
| rust_backend/crates/mobile/src/native_cache/unix.rs | 1–397; explicit direct endpoint expansion |

## Findings

None validated in this bounded pass. Native-created private spill paths are distinct from decoded JSON properties; a JSON `__json_file` property does not become a file-delete instruction. Temporary inputs use process-private `createTempFile` storage with failed-copy cleanup. Cache traversal uses descriptor-relative NOFOLLOW access, inode checks and resource bounds. Failed persisted grants do not become successful picker results. Ordinary deletion rejects virtual CUE paths.

## Follow-up and evidence

- Data integrity lead (not a validated security finding): `MainActivitySafIo.kt:374–382` opens write-back destination with `wt` before source opening; handler `MainActivity.kt:1039–1052` deletes input in `finally`. DATA-01 must verify reachable callers, interruption and recovery.
- Graphify query `NativeDataJobs NativeMediaWorkspace PlatformBridge --budget 1800` completed with truncation; direct endpoint reads supplied evidence. No graph modifications.
- Crafted-provider/device execution and dynamic security tests NOT RUN. Backup/archive parsers, manifest exposure and metadata writer internals are separate scheduled chunks.
- Reviewer edited no files. Enforcement prompt-only.

Result: static trust-boundary chunk PASS; broader security coverage remains partial.
Prior checkpoint `634e709` pushed successfully to `origin/ccr-2fb644cd-nmesyt`.
