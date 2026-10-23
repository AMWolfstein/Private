# Independent current-branch audit

- Source: `d5d5a02ecdad86dca50a4448cf7810b7eec43ad9`, branch `ccr-2fb644cd-nmesyt`.
- Fresh checkout: `/workspace/Private-audit`; report folder created for this request.
- Evaluate current implementation independently. Do not compare against or import old audit findings.
- Review only; no application fixes. Specialist definitions: `.claude/agents/`. Coordinator follows `.claude/skills/audit-project/SKILL.md` and `reviews/PROTOCOL.md`, with the owner's fresh-audit instructions taking precedence over old-finding reconciliation.
- Exclude the audio engine: decoding/rendering, USB audio transport, DSP, audio focus/engine lifetimes, vendored audio-player internals, and engine-specific tests. Retained application UI, library/metadata/file operations, persistence, permissions, and non-engine lifecycle remain in scope.
- Graphify CLI installed outside checkout; existing graph reported fresh by scope helper (built from `46c4ea6a`). Graph has 23,088 nodes. Queries identify navigation leads; findings require direct source evidence.
- Reviewers are instructed read-only; enforcement is prompt-only. Coordinator owns edits, checks, commits and pushes. Maximum three active specialist reviewers per bounded unit, with named chunks and concerns.
- Application builds/device checks are not implied by static review. Record unrun/blocked checks explicitly.

## Planned audit order

1. Cross-language contracts and non-engine cancellation/lifecycle.
2. Metadata/file-write integrity, backups/collections/playlists, scanning/database integrity.
3. Non-engine Rust safety, Android storage/security, build/dependencies.
4. State/business logic, Flutter implementation, UX/accessibility, optimization/dead code.
5. Tests, documentation, inventory reconciliation and final task list.

Each audit type receives a report and commit/push checkpoint. `TASKS.md` is generated after the reviews; old reports remain untouched. Exact planned/read path ledgers and verification evidence accompany each unit.

## CONTRACT-01 planned scope

Owner: api-compat-auditor, secondary concurrency-auditor. Baseline above; clean working tree before report creation.
Planned paths: `lib/services/platform_bridge.dart`, `lib/services/library_native_adapter.dart`, `lib/services/activity_attachment.dart`, `lib/services/native_cache_maintenance.dart`, `lib/services/native_log_source.dart`, `android/app/src/main/kotlin/com/zarz/spotiflac/MainActivity.kt`, `android/app/src/rust/kotlin/com/zarz/spotiflac/NativeDataJobs.kt`, `rust_backend/crates/mobile/src/lib.rs`, `rust_backend/crates/mobile/src/data_jobs.rs`, `rust_backend/crates/mobile/src/cancellation.rs`, `rust_backend/crates/core/src/cancellation.rs`.
Concerns are distinct: API names/types/error mapping versus cancellation/disposal/late completion. Split direct endpoint additions into further <=6k-line chunks; record actual reads. Exclude audio-specific methods in shared files.
Graph navigation: `graphify query 'platform bridge data jobs cancellation library native' --budget 1800` (truncated; narrow queries required); `graphify explain PlatformBridge` identified source at L110.
Status: in progress. No readiness claim.
