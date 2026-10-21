# Upstream v5.2.0 selective backport — final report

All planned PORT_PLAN batches are complete on `ccr-2fb644cd-nmesyt`. Scope follows the actual v5.1.1 baseline `78699a91`, then owner-approved Mornye follow-ups through `e0563ffa`; histories were not merged. Current fork architecture remains authoritative.

- Evaluated tracked upstream items: **35** — **2 ADOPT**, **28 ADAPT**, **5 REJECT**. These are item IDs, not commit counts. Source/local mappings and mixed-commit exclusions: [audit matrix](upstream-v5.2.0-audit.md) and [UPSTREAM.md](UPSTREAM.md).
- ALREADY IMPLEMENTED: equivalent retained title behavior under U-206, plus matching retained dependency versions/toolchain pins in Batch 15; not double-counted as new ports. No whole release was adopted.
- Local parity work: 17 MORN, eight HOME and four PLAY findings, with checks recorded in [PORT_EXECUTION.md](PORT_EXECUTION.md).
- Batch 16 rechecked 60 cleanup findings and retired the related RUST-201 finding. **58 dispositions** were archived, including explicit retain decisions, not 58 new runtime fixes. DEAD-604/702/806 remain separate; retained/deferred risks are below.
- DEFER: Media3/ExoPlayer, Sistrum and replacement DSP architecture. No new playback engine or format migration.

Batch 16 source: `ef8ba64d766e4196a92602147ab7ef149823856e`. Graph checkpoint: `331ab3d0` (built from `ef8ba64d766e4196a92602147ab7ef149823856e`). Source scope: 324 files changed, 1418 insertions(+), 30561 deletions(-).

## Implemented cleanup

Removed unreachable Material Expressive layouts/components and direct dependencies/font, download/provider/re-enrichment helpers, unused iOS bridge methods and Rust filename/progress/clock/Hi-Res/AC4 tails. Removed dead model/settings fields, widgets, native resource helpers and resources. Legacy database schemas and backup import readers stay compatible. Regenerated model serializers and host UniFFI bindings; Android production and instrumentation Kotlin compile against the retained interface.

Removed **70** unused localization keys across **20** locale files after the code cleanup; the second usage scan is empty. Retired tests exclusively exercising deleted APIs; retained fixtures now exercise Mornye controls, local album filtering, timing/ownership and deletion behavior. Added root-aware permission skip, shared paging fixture/timeout, bounded subprocess shutdown, temporary-directory cleanup and `scripts/check_android.sh`. Disabled selection actions explicitly expose disabled semantics and retain a 48px target. Artwork readback tests wait for the expected result with a bound instead of a fixed 30ms completion assumption.

## Verification

| Check | Result |
|---|---|
| Flutter analysis | PASS — No issues found |
| Full Flutter tests | PASS — `02:09 +1513 ~3: All tests passed!` |
| Rust fmt / Clippy with warnings denied / workspace tests | PASS — 165 passed, one ignored |
| Android host unit tests | PASS — 55 passed, one skipped |
| Android instrumentation Kotlin | PASS — compile only; device execution NOT RUN |
| Paging regression | PASS — 10/10 runs with `--concurrency=8` |
| UniFFI host binding generation | PASS |
| Graphify | PASS — 22,436 unique nodes, 42,940 links; endpoint/ID validation passed |
| Diff whitespace / removal and locale usage scans | PASS; retained transitive dependency documented below |
| Physical device / APK | NOT RUN / NOT BUILT |

Logs: `/workspace/batch-16-*.log` and exit files. Earlier intermediate runs failed on old Material fixtures and an asynchronous contrast test; those were corrected before the recorded final pass. No claim of a regression-free device build or measured runtime speedup.

## Retained boundaries and remaining risks

- `NativeReplayGainPolicy` and `MANAGE_EXTERNAL_STORAGE` remain by owner decision. Live `TrackListSkeleton`, `ErrorCard`, artwork aspect ratio, `loveAllTracks`, canonical ISRC helper and haptics SAF jobs remain. Atomic SAF helper remains as directed; active metadata publication and native analysis are intact.
- `material_ui` remains an **existing transitive dependency of go_router 18.0.2**, with no production import/delegate or direct declaration. Replacing the router to eliminate it is outside the authorized cleanup. `material_3_expressive` and Google Sans Flex are removed.
- DEAD-806 legacy bookmark/path compatibility and the cheap on-open normalization hook remain. DEAD-702 artist mode plumbing is live and outside the assigned cleanup rows. DEAD-604's legacy HTTP branch delegates to the local-only image widget, which already rejects remote URLs; it does not restore network loading.
- DATA-501, KT-202 and other unrelated findings remain in FINDINGS.md. This report completes the approved port plan, not every independent code-review fix.
- Material Expressive UI, online services, removed settings/details/conversion/Wishlist, external player and output-folder onboarding are not restored. Local editing, artwork, lyrics, playlists/Loved, statistics and existing engine integrations are retained. No new music-file writes or migration is introduced by the cleanup.

Push status: the code → graph → docs checkpoints are pushed to the active branch; the final docs SHA is discoverable with `git log -1 -- reviews/upstream-v5.2.0-final-report.md`. Confirm against fetched origin on resume. Detailed implementation commits and their upstream sources: PORT_EXECUTION.md/UPSTREAM.md; the final docs commit contains this report.

Next exact work unit: physical-device verification listed in the [backlog](upstream-v5.2.0-backlog.md), followed only by separately scoped review fixes. Recommended thinking effort: MEDIUM, HIGH for file-integrity/FFI work. SOL-only policy followed without model switching; runtime identity/effort was not exposed.

Graphify note: existing vendor syntax/preprocessor extraction warnings remain. Community names use retained labels or hub-based fallback; semantic relabeling was not run. The AST dependency graph and endpoints are synchronized.
