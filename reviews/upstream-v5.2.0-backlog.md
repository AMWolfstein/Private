# Upstream v5.2.0 — prioritized backport backlog

Initial checkpoint only. **No implementation completed or started.** Manual adaptation is the default because the fork has a parentless snapshot, intentional removals and different UI/provider structure. Do not merge the release or cherry-pick large mixed commits. Every batch below is independently scoped; check current HEAD, handoff and source before acting.

## Next bounded work unit — comparison only

**B01 comparison, HIGH:** inspect upstream `378c8f374987c6a8a8f8cbf6330736f136414d94` against current `lib/providers/local_library_provider.dart`, notification service, platform bridge and Android scan/lifecycle code. Use a scoped Graphify query/path first. Determine the smallest recovery/notification patch, active source/start-time protocol, API guards, cancellation semantics and fault-injection tests. No implementation is authorized as part of this discovery checkpoint; a subsequent implementation invocation may execute the narrowed approved batch after this comparison.

Do not import upstream provider/Android module splits. Produce a concrete plan for these separately testable concerns:

1. Clear in-memory scanning state and stop polling even if persisting the original error fails; retain the original diagnostic.
2. Serialize progress/terminal notification transitions and drain them before background work ends; handle cancellation/disposal and rejected notification futures.
3. Recover interrupted runs without deleting valid rows or losing checkpoints; do not depend on auto-scan being enabled. Match Android exit records to process/time and guard APIs below 30.

Acceptance requires targeted Dart recovery/error/cancellation tests and relevant Kotlin helper tests; a build is not necessary during comparison. Split the eventual implementation if recovery is larger than the minimal error-ordering correction.

## Approved scoped candidates — implementation pending

ADAPT is approval of the listed behavior in principle, subject to local call-graph review and passing targeted tests. It is not approval to copy the whole upstream commit. No source batch is marked complete until its implementation, tests, code commit, Graphify refresh/commit and handoff checkpoint exist.

| Batch | Priority / source | Smallest permitted scope | Dependency / safeguards | Verification gate | Effort / risk |
|---|---|---|---|---|---|
| B01 | P1 correctness — `378c8f374987c6a8a8f8cbf6330736f136414d94` | Scan terminal-state correctness, notification ordering, then bounded recovery as narrowed by next comparison | Existing preferences/channels; API guards; preserve checkpoints, source IDs and rows; avoid upstream splits | DB failure during error handling; progress vs completion/cancel; restart/auto-scan off; lifecycle and native exit matching | HIGH / medium |
| B02 | P2 resource correctness — `fe29f304aa79b018fe08675cdd755812cc0cfb4e` | One local playlist-name dialog owns/disposes controller; reuse only where local validation semantics match | Existing Mornye dialog/TextFormField; no upstream expressive form dependency | Create/rename/trim/empty/duplicate/cancel; repeated dialog lifecycle and focus | MEDIUM / low–medium |
| B03 | P2 static performance — `ef5fa1cb4607a6ff30438ec2f0d163cf7e35fe50` | Compile local lyrics credit regexes once | Existing Rust regex + std LazyLock; reject extensions hunk; preserve text byte/Unicode semantics | Local LRC/TTML credits, whitespace, Unicode, repeated parse equivalence; targeted Rust tests | HIGH / low–medium |
| B04 | P2 artwork correctness — `080df889d05f70abd390a25d2c6c89f9321a82c3` | Missing/empty local-cover fallback using existing resolver in retained rows/detail artwork | No remote URLs; bounded cache/stale-result guard; keep real artwork and StackFit sizing fix | File/SAF/missing/empty/stale identity/cache bounds; row/widget image dimensions | MEDIUM / medium |
| B05 | P2 static performance — `afab47ae4d4cdeaf2695051675404a53d7fc16b5` | Timed lyric geometry cache and correct invalidation | Keep current local lyrics painter, TTML/RTL/pronunciation behavior; no provider/sharing import | Width/font/text-scale change; mixed scripts/background vocals; timed rendering/repaint | MEDIUM / medium |
| B06 | P2 static performance — `acbc614f422809b5eb586ca5d9ef2848678025cb` | Hoist constants in aligned_lyric_pronunciation.dart only | No metadata-details route, online album screen, audio-info screen or absent sectioned library restoration | Word alignment/Unicode/whitespace fixtures; output equivalence | MEDIUM / low |
| B07 | P3 UI consistency — `8ff1490d9ed53c745c6573e30282d57027511abf` | Logs level picker as existing Mornye shared sheet | No ExpressiveButton import; Detailed logging remains first, no App category | Every level; cancel/dismiss; RTL/large text; mounted lifecycle | MEDIUM / low–medium |

No runtime performance gain has been measured for B03/B05/B06. Benefits are avoided repeated work visible in source.

## Investigations — not approved implementations

| ID | Priority / source | Evidence still needed | Decision boundary |
|---|---|---|---|
| I02 | P0 investigation — `f426b2d1f0cc256d34267b511665c0e8de6d16c8` | Reproduce/trace local native onError→completion→queue advancement and focus state | Only a confirmed critical defect permits a minimal legacy-player correction; defer rate/deck/engine restructuring |
| I01 | P1 — `186c66aeb8c07025402afe78e58a76e4578f6cfa` | Graph editor→SAF sidecar publication reachability, opaque ID ancestry, API24/25 fallback and explicit failure contracts | No user-owned write change without safeguards; no online re-enrichment/Embed Lyrics restoration |
| I04 | P2 — `cb51d089393eb0af431930192dd683b5296e5dfe`, `36694c6e27c34276a550c458f384815e6b83b251` | Native crash/death distinction, bounded redaction/retention, manifest/startup behavior, existing local diagnostics overlap | Local-only diagnostics and existing Mornye primitives; no Expressive banner or telemetry |
| I03 | P3 — `83a55fb80b1c08460a485f604fb89a48bfbc2096` | Paged/variable-row fast scrolling, selection/RTL and current local layout comparison | Adapt only useful scrolling; keep Genres/Loved Songs categories and no overview Recently Added/swipe deletion import |
| I06 | P3 — `befcd2adec7ba9e3cd95da11e2ad5641e90de4bf` | Retained controls' semantic labels, contrast and touch targets, separate from Material/online hunks | Adapt retained accessibility only; no parallel UI infrastructure |
| I07 | P3 — `bd0b4a50c3c3560306f4752e8a49030b69df741f` | Current wideListInset/adaptive_layout vs retained tablet routes and two-column player | No upstream navigation replacement |
| I08 | P3 — `8d1a42e01ae39c470f59d136cb8b5d015b8b19f6`, `97d8ee3695384cf3f32b89d610f761c90c601f8f` | Mini-player/queue feedback and rapid-skip title behavior vs current implementation | UI-only refinements; engine changes deferred unless critical |
| I09 | P3 — `78a5e078cd7a7d6088d6fd76f19f2749bcbcf972` | Local timed-vocal transition behavior separated from sharing/provider work | Preserve local lyrics and current player views; no network fetch |
| I10 | Audit completeness | Remaining path-only entries, dependency/lock/native transitive effects and security evidence | Finish one subsystem per invocation; no title-only claim of semantic review |
| I11 | Existing local discrepancy | Current residual material_ui/material_3_expressive/helper graph and retained callers | No changes this audit unit; cannot claim Expressive code/dependencies entirely absent |
| I05 | Release bookkeeping — `22f3ec52f9bd1e57f661ca0b17e3aaa34b0e8ae8` | Merge resolution independently of ancestor changes (inventory records first-parent paths) | Do not cherry-pick release merge |

Inventory-only DEFER decisions for generic refactors/tests/docs are provisional: when a functional batch requires a helper/test, review its source and reclassify that narrow portion. Do not port every upstream test, file split, manifest or localization cleanup.

## Already implemented / rejected / deferred

- **Already implemented:** retained normal/immersive artwork preference (`05a56133`); removed online Rust-crate dependencies (`5254760b`, pin-centralization remainder deferred). Retained atomic playlist export safety is present, while the new shared helper (`190801c3`) remains deferred.
- **Rejected:** whole Material Expressive/theme/navigation/components/dependencies; online search/download/provider/lyrics/extension/regional/service-status flows; removed pages/settings/features; default-quality preference (`75907951`); unnecessary dev-interface declaration (`317cd254`) unless a future retained test imports it. Per-commit inventory defines exact scope.
- **D01 deferred:** native FLAC decoder replacement (`3dc2d690`), multiband EQ, haptics and complex AutoMix/player refactoring. A precision fixture investigation does not approve a decoder replacement or future Media3/Sistrum/DSP work.
- **D02 deferred:** shared atomic-write consolidation (`190801c3`) until all retained write semantics justify it.
- **D03 deferred:** retained Rust pin-centralization cleanup; never undo Android vendor patches.
- **D04 deferred:** independent offline Android CI plan; no upstream online/iOS publishing automation import.
- **D05 deferred:** broad structural/test/docs imports pending concrete retained benefit.

## Per-batch execution contract

Inspect current Git status/branch, STATE/HANDOFF, audit and latest checkpoint. Use current Graphify workflow and source, inspect exact upstream hunks and prerequisites, prefer smallest manual adaptation, add meaningful regressions, run targeted analysis/tests, inspect diff. Commit source/tests/config first, then `graphify update .` and a graph-only commit, then reports/progress checkpoint per AGENTS.md. Record upstream→local commit traceability, PASS/FAIL/NOT RUN/BLOCKED and push the active review/checkpoint branch when authorized. Preserve unrelated edits. Stop after one bounded work unit. Do not create empty code/graph commits for documentation-only comparisons.

A final compatibility review and `upstream-v5.2.0-final-report.md` are **not due yet**. Create them only after remaining comparisons, selected implementations and phase-boundary verification; keep rejected features absent and explicitly report any pre-existing residual infrastructure.
