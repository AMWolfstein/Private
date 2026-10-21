# Upstream port execution checkpoints

## Completed batch 6 (2026-10-20)

U-210 fits collection covers to short screens. U-217 adds release-triggered upward mini-player opening while keeping horizontal dismissal. U-218 adds bounded normalization pre-amp and Track/Album gain, with one cached tag read and live settings changes. U-303 adds a tappable quality badge and Mornye audio-info sheet with read-only Android route facts, current gain/rate/direct state, local analysis and copied reports.

Source → graph: U-210 `c2f38c86` → `e0f9ba6d` (d28e3f65); U-217 `8a9f6091` → `53b473f0` (37162363); U-218 `0d126507` → `ae93ce55` (9eea6a1a); U-303 `bd8f88a6` → `44cbd9e8` (40f65d3a plus U-209 acbc614f number-pattern reuse). Fixture correction `8b7adfe6` → graph checkpoint (see history); initial imported sheet tests lacked ProviderScope, corrected before final verification.

PASS: analysis clean; Flutter 1670 passed / 3 skipped / zero failures (03:59); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 1735a8c3, source 8b7adfe6: 23,304 unique nodes / 44,944 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. No dependencies, schema or user-music writes added. Native route support varies by device; actual playback/GPU/route behavior needs device checks. U-303 standalone HiResCheckCard depends on absent services/online wrappers and is excluded; existing AudioAnalysisCard retained. Audio-info EQ reporting is pending U-301 batch 9.
Next: batch 7 (U-308, U-302). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 7 (2026-10-20)

U-308 completes local lyric quote cards, menu/long-press entry points, on-demand document reads and stale-share guards, restyled using retained Mornye controls. Compatible held-word glow honors reduced motion and a bounded fade window, preserving settled/background ticker suspension. U-302 adds optional local music haptics, stable SAF identity and owned decoder jobs, transport synchronization, basic-motor support and bounded sensitivity/strength settings.

Source → graph: U-308 `d83068e6` → `9ae8c833` (78a5e078/2782b1f7); U-302 `df164fb1` → `ba844ef0` (11c6cf99/2455cabc/9acaa760). Follow-ups: artwork guard lint `b02895b0` → `1bb926e3`; Mornye selection fixture `a9433d82` → `6bb22e86`; virtualized-card assertion `de546bd7` → `e0fd4bbe`.

PASS: analysis clean; Flutter 1692 passed / 3 skipped / zero failures (03:55); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph e0fd4bbe, source b02895b0: 23,480 unique nodes / 45,224 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. No dependencies/schema changes or user-music writes. Music haptics defaults off; physical motor sensation/timing and OS share targets NOT RUN. Android VIBRATE permission is the only permission added. Initial quote-limit fixture assumed all rows remained visible; corrected to reveal rows, assert 5/5 and scope preview checks to LyricsShareCard before final verification. New card preserves local artwork policy; no network provider restored.
Next: batch 8 (U-304, U-305, U-307, U-312). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 8 (2026-10-20)

U-304 adds local Rewind highlights and seasonal invitations using recorded listening statistics and Mornye surfaces. U-305 adds pinned Unicode/month section headers and adaptive fast scrolling without changing the dedicated Songs/category layout or bounded paging. U-307 adapts compact launcher-player sizing, preserving existing controls/themes. U-312 bounds restoration checks, virtualizes Settings search, limits logo decoding, avoids redundant static contrast readbacks and scopes pinch updates to the grid.

Source → graph: U-304 `f4fb6794` → `39f9bf4a`; U-305 `6052f9ea` → `ef111d26` (includes U-209 cached locale formatters and U-312 pinned lists); U-307 `2c9c0305` → `e51d221c`; U-312 `c49d7af9` → `c05701ff`. Compatibility fixes `1c589407` → `4f5bc88d`; Rewind header/offline fixture fix `c3d79e0d` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1739 passed / 3 skipped / zero failures (04:10); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 9020a7aa, source c3d79e0d: 23,813 unique nodes / 45,709 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. No dependency/schema changes or user-owned music writes. Rewind share targets and launcher resizing on physical devices NOT RUN. Initial analysis mismatches corrected using retained APIs; initial Flutter failures caught an unbounded close control and an upstream remote-source fixture assumption, both corrected before final checks. No runtime speedup measurement. Android widget visual redesign/preview intentionally excluded.
Next: batch 9 (U-301 equalizer only). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 9 (2026-10-20)

U-301 adds the owner-selected optional per-player Android equalizer: 5/10/15/31 bands, tone/preamp/balance, headroom, limiter/compressor, local presets and bounded JSON import/share. A Mornye-only editor and player/settings menu routes use retained grouped controls. Audio-info now reports EQ/bypass/native errors. Existing playback transport and direct/exclusive output remain intact.

U-301 source `8e05cbbf` → graph `babdbbbe` (ecf594aa + 68c739df); installed picker/API and bounded stream import correction `892eb173` → `5c602c59`; scrolled-control test fixture `c7924c53` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1753 passed / 3 skipped / zero failures (04:16); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph fd1a520b, source 892eb173: 23,940 unique nodes / 45,919 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. No dependencies/schema changes, user-music writes, Darwin backend or engine replacement. EQ defaults off and native failures are visible; direct/exclusive output bypass is covered by mocked transport tests. Physical sound/driver support and share/picker targets NOT RUN. Initial Dart/native check failures were installed picker/theme API mismatches, fixed before final verification; focused widget fixtures now settle scrolling before interaction. Model/preset/native-payload/transport/input-boundary tests imported or added. No APK.
Next: batch 10 (MORN-001..005 and MORN-017; FIX_PLAN M1+M2). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 10 (2026-10-20)

MORN-001..005 and MORN-017 align retained collection UI behavior: album selection owns the toolbar and hides playback actions; playlist/Loved use shared circular toolbar controls and collapse titles; hydration shows skeletons instead of empty flashes; current rows pause/resume without queue restart. Artist/album loading/error/empty presentation now uses retained Mornye primitives and hides an empty Popular heading.

Source `bc983981` → graph `afcb349a`; fixture duration `b55043ba` → `36cdf5d4`; hydration fixture isolation `b602dfb3` → `de2c48ba`, duplicate override correction `ad7e26eb` → `d6b8c566`. Upstream-latest collection patterns inspected at e0563ffa; existing offline behavior retained.

PASS: analysis clean; Flutter 1759 passed / 3 skipped / zero failures (04:13); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph d6b8c566, source ad7e26eb: 23,954 unique nodes / 45,967 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. Six new light/dark collection-state regressions cover selection exit, hydration and current-row toggling. Initial fixture failures were missing duration and duplicate provider setup; corrected before final verification. No dependencies, schemas, music-file writes, native changes or APK. Physical visual checks NOT RUN.
Next: batch 11 (MORN-006..012; FIX_PLAN M3+M4). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 11 (2026-10-20)

MORN-006..012 adapt local album metadata and artist presentation: genre/year metadata, localized footer duration, first-playable Play-all, ReplayGain section labeling; matching artist controls, slot-specific placeholders, 280px collapse threshold, compact Popular rows and responsive album cards with year/local track counts and explicit single badges.

Source `df09d3ea` → graph `496dd75b`; shelf lint correction `2a6ea366` → `d1dd2638`; CUE-fixture real-song identity correction `b1fd7886` → `ff70d508`. Upstream-latest artist card/row patterns inspected at e0563ffa; adapted to retained local data and menus.

PASS: analysis clean; Flutter 1759 passed / 3 skipped / zero failures (04:13); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph ff70d508, source 2a6ea366: 23,960 unique nodes / 45,975 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. Retained playback regressions now begin with a virtual CUE row and compact release-date metadata, covering both themes; first real-song identity remains explicit in later fixture checks. Artist visual/device checks NOT RUN. Single badges require explicit total-track tags=1. No EP type exists in the local browse model/database, so EP badges are omitted rather than inferred from file counts; EPs remain under Albums. No dependencies, schemas, music-file writes, native changes or APK.
Next: batch 12 (MORN-013..016; FIX_PLAN M5+M6). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 12 (2026-10-21)

MORN-013..016 unify effective collection artwork, use tonal Loved/playlist actions with feedback, fit short-screen covers, and improve Mornye contrast and segmented touch targets.

Source `ce2538bf` → graph `5c2bdc49`; header fixture correction `8477c4bc` → final graph checkpoint. MORN-015 was already implemented by U-210 `c2f38c86` in batch 6.

PASS: analysis clean; Flutter 1769 passed / 3 skipped / zero failures (04:17); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 4bb91e88, source 8477c4bc: 23,970 unique nodes / 46,006 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. Ten light/dark artwork, feedback, contrast and accessibility regressions pass. Initial fixture lookup failures corrected to inspect the configured header before sliver flattening. No native/dependency/schema changes or music-file writes. Physical visual checks NOT RUN.
Next: batch 13 (HOME-001..008; FIX_PLAN M7–M9). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 13 (2026-10-21)

HOME-001..008 adapt the local editorial feed: aspect-preserving indexed artwork with embedded fallback, cached shelves across scans, pull-to-refresh, guided empty/retry states and loading skeletons; localized dates, explicit labels and responsive themed cards; stable identities and Home reselect scrolling. Removed two unused Home parts and the unreachable branding intro.

Source `0d9dbf9c`, lint correction `504a38df` → graph `4b4fe09f`; cached-refresh fixture `f5ec3973` and hydration guard `c4e9e536` → graph `8ad07efd`. Compared upstream Home sizing/skeleton patterns at e0563ffa.

PASS: analysis clean; Flutter 1771 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 8ad07efd, source c4e9e536: 23,983 unique nodes / 46,028 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. Recently Added ordering and release-tag-only Latest Releases queries unchanged. Optional long-press menus omitted; existing local detail navigation retained. Initial tests exposed viewport assumptions and missing standalone Intl date initialization, corrected before final checks. No music-file writes/dependencies/native changes or APK. Home same-path image invalidation remains with existing metadata/cache ownership. Tablet/device visual comparisons NOT RUN.
Next: batch 14 (PLAY-001..004 and U-311). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 14 (2026-10-21)

PLAY-001..004 and U-311 adapt Immersive cover proportions/fade and a shared artwork/title swipe scope, retain the background across rotation, label the lyrics-size control and match queue swipe corners. Separate inset/full-bleed artwork keys and bounded ownership prevent rotation/rapid-view conflicts; queue-index selection avoids transport rebuilds on clock updates.

U-311 upstream `05a56133` → source `3dfa8b73` → graph `140ecef1`; lint `45c40118` → `9f62788e`; fixtures `5fd4892a` → `72145734`; ownership/subscription correction `822a4656` → `3c9fe836`, labels `53a17a8e`. PLAY-003 behavior also present in upstream befcd2ad; adapted using Semantics around the installed Flutter Slider.

PASS: analysis clean; Flutter 1775 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 53a17a8e, source 822a4656: 23,988 unique nodes / 46,040 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. Normal remains default; persisted Immersive and landscape two-column behavior retained. Existing backdrop saturation and full-bleed Hero gating already match useful upstream behavior. Focused regressions caught and fixed GlobalKey ownership and clock-rebuild defects; ten corrected regressions pass. Transparent foreground artwork gesture region intentionally receives Immersive drags. Physical side-by-side visuals NOT RUN. No engine/dependencies/native changes, user-music writes or APK.
Next: batch 15 (shared dependency comparison against refreshed upstream main). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 15 (2026-10-21)

Refreshed upstream main remains e0563ffa. Compared all shared Pub declarations and overrides, resolved shared Cargo versions through both workspaces, and checked Flutter/Gradle/Android toolchain pins. No retained dependency version changes are available; no manifest or lockfile changes required.

Comparison-only checkpoint. Evidence: reviews/upstream-v5.2.0-dependencies.json; upstream e0563ffad6df9f01d3e73e6099f74417422374de. Source remains batch 14.

REUSED batch 14 verification for identical source; no redundant test execution in documentation-only batch 15. PASS: analysis clean; Flutter 1775 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 53a17a8e, source 822a4656: 23,988 unique nodes / 46,040 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. 33 shared runtime packages, eight development packages, one common override and 20 shared workspace Cargo dependencies have matching versions; direct mobile workspace declarations resolve to the same roxmltree/rusqlite versions. Local-only crate has no equivalent upstream path. Upstream-only network, service, iOS and branding dependencies rejected. No dependency additions or APK.
Next: batch 16 (one reviewed dead-code patch and final compatibility report). User authorized continuing through the remaining PORT_PLAN batches without asking again.

## Completed batch 16 (2026-10-21)

Retired unreachable Material Expressive UI and direct dependencies, download/provider/re-enrichment and iOS bridge APIs, dead Rust modules and unused settings/widgets/resources. Preserved offline metadata/lyrics editing, Audio Quality Analysis, CUE, local collections, playback and legacy backup/schema compatibility. Removed 70 unused l10n keys last; added native check script and test resource/timeout cleanup. Disabled selection actions retain explicit accessible state and 48px targets.

One reviewed source patch `ef8ba64d`; Graphify checkpoint recorded below. Cleanup follows FIX_PLAN Tier 3, not an upstream merge. Existing source-to-upstream mappings remain in UPSTREAM.md and prior PORT_EXECUTION checkpoints.

PASS: analysis clean; Flutter 1513 passed / 3 skipped / zero failures (02:09); Android unit 55 passed / 1 skipped; Rust fmt/Clippy PASS, 165 passed / 1 ignored.
Graph 331ab3d0, source ef8ba64d: 22,436 unique nodes / 42,940 valid links; synchronized, existing vendor extraction warnings remain.
No APK built; device-only behavior NOT RUN. Native unit checks and Rust fmt/Clippy/tests pass; regenerated host UniFFI bindings. Instrumentation sources compile, but device execution is NOT RUN. Paging regression passes 10/10. Test-only APIs and their obsolete cases were retired; retained Mornye fixtures were adapted, not skipped. DEAD-806 remains partially open for legacy bookmark/path compatibility; DEAD-702 and unrelated DATA-501/KT-202 remain outside this batch. NativeReplayGainPolicy, MANAGE_EXTERNAL_STORAGE, live skeleton/ErrorCard/artist artwork, canonical ISRC helper and haptics SAF jobs retained. Atomic SAF helper retained per plan. No APK or runtime performance claim. material_ui remains an existing transitive dependency of retained go_router 18.0.2; no production material_ui imports/delegate remain. Replacing the router to remove that transitive dependency is outside this cleanup and needs a separate architectural decision.
Next: none in PORT_PLAN; physical-device verification and separately approved remaining review fixes. User authorized continuing through the remaining PORT_PLAN batches without asking again.

