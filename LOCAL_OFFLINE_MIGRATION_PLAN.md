# Local / Offline / Android-only Migration Plan

Goal: convert `spotiflac_android` from an **extension-driven online downloader** into a
**local, offline, Android-only music player**.

Chosen scope (confirmed):
- Rust backend: keep local parts, strip online.
- Remove: extensions + providers + download engine, network storage (SMB/WebDAV),
  non-Android platforms, online UI surfaces, Discord presence.
- Approach: plan doc, then phased commits (one reviewable commit per subsystem).

Verification for every phase: `flutter analyze`, `bash scripts/check_rust_backend.sh`
(cargo fmt/clippy/test), `bash scripts/build_rust_backend.sh android`, then
`flutter build apk`; run `graphify update .` after code changes.
**Current user instruction (2026-10-19): restore the former metadata-page local actions
in the new song ellipsis menus, retaining Edit Metadata and Audio Quality Analysis, and fix
popover placement so it follows the tapped ellipsis. Keep the metadata page removed.**

---

## Progress

_Last updated: 2026-10-22_

**Status:** Phases 1-8 and the requested local-player refinements are implemented.
Latest source validation passed. The signed ARM64-only side-by-side **build 168** includes
fetched `d4dff781` (glass slider fix), source `2a2ab3be`, all completed upstream ports and Batch 16 cleanup.
It retains **SpotiFLAC Local** (`com.zarz.spotiflac.local`), the cream/green launcher icon
and the certificate used by build 167. Physical-device validation remains pending.
`c29daef` removes the About page credits, translators, special thanks, links and social sections
(with `url_launcher`) and the Search tab Recent list (app-state schema v5 drops its tables);
`flutter analyze` and the full `flutter test` run now pass in batch 1b.
Vision refinements V1-V4 captured; Phase 6 decisions recorded in `PHASE6_DECISIONS.md`.

**Local ARM64 build 168 (2026-10-21):** Owner paused the new audit and requested the latest branch build. Fetched `d4dff781`; release metadata source `2a2ab3be`, graph `686a463f`. Analysis clean; full Flutter 1,514 passed / 3 skipped before the version-only bump; signed release compilation and artifact audits PASS. VersionCode2168, ARM64-only SpotiFLAC Local, cream/green icon and certificate matching167. APK 52,787,208 bytes, SHA256 `98c0ab17ef57b39870e24b654a1ad6be8883d7d09923a9a61c6ee5a2032cdecf`. Device NOT RUN. [Download](https://github.com/AMWolfstein/Private/raw/refs/heads/apk-local-arm64-168/SpotiFLAC-Local-168-arm64-v8a.apk); details in reviews/LOCAL_BUILD_168.md. This supersedes the earlier source-session note that its environment could not package an APK.

**Floating glass headers and adaptive bar (2026-10-22):** `a844497` headers, `9e597b9` bottom bar, graph `eb417e2`. `AppSliverHeader` (21 pages incl. settings), the album toolbar and the artist toolbar are transparent unless the level is flat or contrast blocks glass (then the old opaque bar). New `mornye_floating_header.dart`: glass back circle, runs of `IconButton` actions in one capsule (the Home avatar keeps its circle), and a `LiquidGlassScrollEdge` backing that fades in only when content is scrolled under (liquid: blur 5, 72% page tint; frosted, reduced motion or no shader filters: no blur, 94% tint and no lens). Status-bar style is explicit (a transparent AppBar estimates as dark); title/leading/action insets are directional. The album toolbar over its cover takes its palette and status icons from the cover's top-quarter CIE L* (`CoverPalette.topLightness`, one 112px decode, cached), otherwise the page. LiquidGlassAppBar was rejected (single capsule, no sliver collapse, no RTL). Bottom bar: where liquid chrome is allowed the shell wraps its pages in one `LiquidGlassView` (batch/realtime off) with an invisible `LiquidGlassAdaptiveArea` over the bar footprint; its verdict drives the bar theme and navigation-bar icons (artist page override still wins) and lets light bar glass drop its 50% floor (navigation 0.49→~0.28, mini player 0.70→~0.41). Sampling is held by `LiquidGlassAdaptivityController`: zero captures at rest, 6 Hz while scrolling, one look on scroll end, +400 ms and on visible-page change. Headers do not sample: inside the page they would read their own glass and band. Light-mode "solid white" bar was a style choice (≥50% white floor, `strongTint` skips the clarity clear-fill) over white pages, not a setting or device fallback.

PASS: analysis clean; full Flutter suite `06:11 +1545 ~4: All tests passed!`; new `mornye_floating_header_test` (glass/frosted/reduced-motion/no-shader/flat/high-contrast headers, back pops, title collapses, RTL, status bar, album artwork verdict) and `mornye_chrome_adaptivity_test` (no view when gated, held at rest, live while scrolling, single looks, page-change look, override precedence, clear light tint); `mornye_tab_pill_motion_test` now counts the bar capsule's lens. No golden tests exist. APK NOT BUILT: `scripts/build_android.sh` stops with "No Android SDK found"; dl.google.com is refused by the network policy, and NDK, Rust Android target, cargo-ndk and `android/key.properties` are absent. Device look/readability/smoothness NOT RUN.

**Liquid-glass controls (2026-10-21):** `d42fef0` switch, `449ba4c` sliders, `9fa1948` tab bar. Shared `MornyeGlassThumb`: a painted pill at rest (no lens, ticker or capture) swapped for one `LiquidGlassMotionPill` (liquid_glass_easy 5.0.0) from touch-down until the contraction hides the glass. Gate (`mornyeGlassThumbsEnabled`): shader filters, liquid tier, clarity > 0.2, motion and contrast permitted, enabled control; latched per touch. AppSwitch keeps its gestures/InkWell/semantics/RTL/0.5 disabled opacity and onChanged rules (credit upstream Mornye `9247b99a^`; NativeGlassMetrics not reintroduced). `MornyeSlider` replaces `Slider` at the five settings sliders with identical arguments; with glass open its resting thumb is a white pill (owner option i: Material thumb remains the fallback). Horizontal `MornyeLevelSlider` (EQ pre-amp) gets the glass knob; vertical faders, seek and volume unchanged. Tab pill: drag squash/stretch via `LiquidGlassLensMotion` (12% cap); light resting pill tuned to the Apple Music reference (4% fill, shadow outside the fill; measured ~4% vs reference ~3.5-4% darkening). New `mornyeShaderFiltersSupportedProvider` makes the shader gate testable.

PASS: analysis clean; full Flutter suite `05:33 +1532 ~4: All tests passed!`; new `app_switch_glass_test`, `mornye_slider_glass_test` (drawn thumb equals Slider's painted centre, LTR/RTL, discrete/continuous), `mornye_tab_pill_motion_test`. Graph refreshed in `e9cdfe2` (it already included the slider and tab-pill sources from the working tree; later refreshes had no topology changes). APK NOT BUILT (network policy blocks `dl.google.com`; Android SDK/NDK, JDK 25, signing key absent). Device look/smoothness NOT RUN.

**Glass clarity drag preview (2026-10-21):** `d6d467c` makes the Appearance clarity slider preview-only while dragging. It holds a local drag value; only the preview panel follows it, through a new optional `clarity` override on `MornyeGlassPanel`/`MornyeGlass`. Glass elsewhere (bottom bar, chrome, menus, glass preparation) keeps the committed provider value, so it no longer rebuilds per step or crosses the 0.2 lens/warm-up threshold mid-drag. Release saves once and updates the app in one step; when idle the slider follows the provider (resets, restores).

PASS: analysis clean; full Flutter suite `05:42 +1515 ~4: All tests passed!`; new `appearance_clarity_drag_test` (no provider write or outside rebuild during drag, preview follows the drag, one persisted commit, external changes update the idle slider). Graph `d89f518`. APK NOT BUILT: `dl.google.com` is blocked by this environment's network policy and the Android SDK/NDK, JDK 25 and `android/key.properties` are absent. Device check NOT RUN.

**Glass clarity slider jank (2026-10-21):** `a935e65` moves glass clarity and outlines out of the `MornyeTheme` ThemeExtension into `mornyeGlassClarityProvider`/`mornyeGlassOutlinesProvider`. `MornyeThemeWrapper` selects only accent, system font and theme mode, so a slider tick no longer rebuilds both ThemeData objects, runs MaterialApp's 300ms theme lerp or rebuilds every `Theme.of` dependent. The Appearance page and custom font tile select their fields. The clarity preview and slider, and the bottom-bar mini player, have their own repaint boundaries (the tab bar and side capsules already had them). No visual values changed; persist:false while dragging, saved on drag end.

PASS: analysis clean; full Flutter suite `05:52 +1513 ~4: All tests passed!`; new `mornye_glass_theme_isolation_test` build-counter test. Integration tests updated but NOT RUN (need a device). Graph `de9edcd`. APK NOT BUILT: this container has no Android SDK, NDK 30.0.16248370, Rust `aarch64-linux-android` target, cargo-ndk or `android/key.properties`. Device smoothness and glass appearance NOT RUN.

**Local ARM64 build 167 (2026-10-21):** Built from `c76237c6`, incorporating all completed upstream ports and Batch 16 cleanup. Version 5.1.1 / build 167, split versionCode 2167. Release flags: `SPOTIFLAC_SIDE_BY_SIDE=true SPOTIFLAC_RUST_ANDROID_ABIS=arm64-v8a flutter build apk --release --target-platform android-arm64 --split-per-abi --dart-define=GIT_COMMIT=c76237c6`.

APK `SpotiFLAC-Local-167-arm64-v8a.apk`, 52,983,816 bytes; SHA-256 `8b5521fe78bbc1640675e26b1838776f370191c440a4288402d63efcc2b80639`. Package `com.zarz.spotiflac.local`, label SpotiFLAC Local, minimum API 24 / target API 37, ARM64 only. All 17 native libraries are AArch64 ELF64 with at least 16KB LOAD alignment; ZIP 16KB alignment, CRC/backend audit, embedded source revision, cream icon background and absence of INTERNET permission verified. APK signature verifies and certificate matches build 166 (`b912cdc7e97b78a19aff3ac8398abc3b36251de2af67243e8a6da2870e15c7b3`). This is an update to the existing Local app and installs alongside the original package.

Analysis clean; full Flutter suite PASS: `03:16 +1513 ~3: All tests passed!`. Physical-device installation/playback NOT RUN. Initial build encountered a generated-plugin race when tests ran concurrently; after tests completed, release was rebuilt serially and passed. Do not run Flutter tests and APK builds concurrently in this checkout.

Download branch: `apk-local-arm64-167`, containing APK, README, SHA256SUMS and APK_DETAILS.json. [Download APK](https://github.com/AMWolfstein/Private/raw/refs/heads/apk-local-arm64-167/SpotiFLAC-Local-167-arm64-v8a.apk). Source → graph checkpoints: `c76237c6` → `a08624d2`; release docs checkpoint follows.

**Upstream port batch 16 (2026-10-21):** Retired unreachable Material Expressive UI and direct dependencies, download/provider/re-enrichment and iOS bridge APIs, dead Rust modules and unused settings/widgets/resources. Preserved offline metadata/lyrics editing, Audio Quality Analysis, CUE, local collections, playback and legacy backup/schema compatibility. Removed 70 unused l10n keys last; added native check script and test resource/timeout cleanup. Disabled selection actions retain explicit accessible state and 48px targets.

One reviewed source patch `ef8ba64d`; Graphify checkpoint recorded below. Cleanup follows FIX_PLAN Tier 3, not an upstream merge. Existing source-to-upstream mappings remain in UPSTREAM.md and prior PORT_EXECUTION checkpoints.

PASS: analysis clean; Flutter 1513 passed / 3 skipped / zero failures (02:09); Android unit 55 passed / 1 skipped; Rust fmt/Clippy PASS, 165 passed / 1 ignored.
Graph 331ab3d0, source ef8ba64d: 22,436 unique nodes / 42,940 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Native unit checks and Rust fmt/Clippy/tests pass; regenerated host UniFFI bindings. Instrumentation sources compile, but device execution is NOT RUN. Paging regression passes 10/10. Test-only APIs and their obsolete cases were retired; retained Mornye fixtures were adapted, not skipped. DEAD-806 remains partially open for legacy bookmark/path compatibility; DEAD-702 and unrelated DATA-501/KT-202 remain outside this batch. NativeReplayGainPolicy, MANAGE_EXTERNAL_STORAGE, live skeleton/ErrorCard/artist artwork, canonical ISRC helper and haptics SAF jobs retained. Atomic SAF helper retained per plan. No APK or runtime performance claim. material_ui remains an existing transitive dependency of retained go_router 18.0.2; no production material_ui imports/delegate remain. Replacing the router to remove that transitive dependency is outside this cleanup and needs a separate architectural decision. Next: none in PORT_PLAN; physical-device verification and separately approved remaining review fixes.

**Upstream port batch 15 (2026-10-21):** Refreshed upstream main remains e0563ffa. Compared all shared Pub declarations and overrides, resolved shared Cargo versions through both workspaces, and checked Flutter/Gradle/Android toolchain pins. No retained dependency version changes are available; no manifest or lockfile changes required.

Comparison-only checkpoint. Evidence: reviews/upstream-v5.2.0-dependencies.json; upstream e0563ffad6df9f01d3e73e6099f74417422374de. Source remains batch 14.

REUSED batch 14 verification for identical source; no redundant test execution in documentation-only batch 15. PASS: analysis clean; Flutter 1775 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 53a17a8e, source 822a4656: 23,988 unique nodes / 46,040 valid links; synchronized, existing vendor extraction warnings remain.
No APK; 33 shared runtime packages, eight development packages, one common override and 20 shared workspace Cargo dependencies have matching versions; direct mobile workspace declarations resolve to the same roxmltree/rusqlite versions. Local-only crate has no equivalent upstream path. Upstream-only network, service, iOS and branding dependencies rejected. No dependency additions or APK. Next: batch 16 (one reviewed dead-code patch and final compatibility report).

**Upstream port batch 14 (2026-10-21):** PLAY-001..004 and U-311 adapt Immersive cover proportions/fade and a shared artwork/title swipe scope, retain the background across rotation, label the lyrics-size control and match queue swipe corners. Separate inset/full-bleed artwork keys and bounded ownership prevent rotation/rapid-view conflicts; queue-index selection avoids transport rebuilds on clock updates.

U-311 upstream `05a56133` → source `3dfa8b73` → graph `140ecef1`; lint `45c40118` → `9f62788e`; fixtures `5fd4892a` → `72145734`; ownership/subscription correction `822a4656` → `3c9fe836`, labels `53a17a8e`. PLAY-003 behavior also present in upstream befcd2ad; adapted using Semantics around the installed Flutter Slider.

PASS: analysis clean; Flutter 1775 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 53a17a8e, source 822a4656: 23,988 unique nodes / 46,040 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Normal remains default; persisted Immersive and landscape two-column behavior retained. Existing backdrop saturation and full-bleed Hero gating already match useful upstream behavior. Focused regressions caught and fixed GlobalKey ownership and clock-rebuild defects; ten corrected regressions pass. Transparent foreground artwork gesture region intentionally receives Immersive drags. Physical side-by-side visuals NOT RUN. No engine/dependencies/native changes, user-music writes or APK. Next: batch 15 (shared dependency comparison against refreshed upstream main).

**Upstream port batch 13 (2026-10-21):** HOME-001..008 adapt the local editorial feed: aspect-preserving indexed artwork with embedded fallback, cached shelves across scans, pull-to-refresh, guided empty/retry states and loading skeletons; localized dates, explicit labels and responsive themed cards; stable identities and Home reselect scrolling. Removed two unused Home parts and the unreachable branding intro.

Source `0d9dbf9c`, lint correction `504a38df` → graph `4b4fe09f`; cached-refresh fixture `f5ec3973` and hydration guard `c4e9e536` → graph `8ad07efd`. Compared upstream Home sizing/skeleton patterns at e0563ffa.

PASS: analysis clean; Flutter 1771 passed / 3 skipped / zero failures (04:18); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 8ad07efd, source c4e9e536: 23,983 unique nodes / 46,028 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Recently Added ordering and release-tag-only Latest Releases queries unchanged. Optional long-press menus omitted; existing local detail navigation retained. Initial tests exposed viewport assumptions and missing standalone Intl date initialization, corrected before final checks. No music-file writes/dependencies/native changes or APK. Home same-path image invalidation remains with existing metadata/cache ownership. Tablet/device visual comparisons NOT RUN. Next: batch 14 (PLAY-001..004 and U-311).

**Upstream port batch 12 (2026-10-21):** MORN-013..016 unify effective collection artwork, use tonal Loved/playlist actions with feedback, fit short-screen covers, and improve Mornye contrast and segmented touch targets.

Source `ce2538bf` → graph `5c2bdc49`; header fixture correction `8477c4bc` → final graph checkpoint. MORN-015 was already implemented by U-210 `c2f38c86` in batch 6.

PASS: analysis clean; Flutter 1769 passed / 3 skipped / zero failures (04:17); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph 4bb91e88, source 8477c4bc: 23,970 unique nodes / 46,006 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Ten light/dark artwork, feedback, contrast and accessibility regressions pass. Initial fixture lookup failures corrected to inspect the configured header before sliver flattening. No native/dependency/schema changes or music-file writes. Physical visual checks NOT RUN. Next: batch 13 (HOME-001..008; FIX_PLAN M7–M9).

**Upstream port batch 11 (2026-10-20):** MORN-006..012 adapt local album metadata and artist presentation: genre/year metadata, localized footer duration, first-playable Play-all, ReplayGain section labeling; matching artist controls, slot-specific placeholders, 280px collapse threshold, compact Popular rows and responsive album cards with year/local track counts and explicit single badges.

Source `df09d3ea` → graph `496dd75b`; shelf lint correction `2a6ea366` → `d1dd2638`; CUE-fixture real-song identity correction `b1fd7886` → `ff70d508`. Upstream-latest artist card/row patterns inspected at e0563ffa; adapted to retained local data and menus.

PASS: analysis clean; Flutter 1759 passed / 3 skipped / zero failures (04:13); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph ff70d508, source 2a6ea366: 23,960 unique nodes / 45,975 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Retained playback regressions now begin with a virtual CUE row and compact release-date metadata, covering both themes; first real-song identity remains explicit in later fixture checks. Artist visual/device checks NOT RUN. Single badges require explicit total-track tags=1. No EP type exists in the local browse model/database, so EP badges are omitted rather than inferred from file counts; EPs remain under Albums. No dependencies, schemas, music-file writes, native changes or APK. Next: batch 12 (MORN-013..016; FIX_PLAN M5+M6).

**Upstream port batch 10 (2026-10-20):** MORN-001..005 and MORN-017 align retained collection UI behavior: album selection owns the toolbar and hides playback actions; playlist/Loved use shared circular toolbar controls and collapse titles; hydration shows skeletons instead of empty flashes; current rows pause/resume without queue restart. Artist/album loading/error/empty presentation now uses retained Mornye primitives and hides an empty Popular heading.

Source `bc983981` → graph `afcb349a`; fixture duration `b55043ba` → `36cdf5d4`; hydration fixture isolation `b602dfb3` → `de2c48ba`, duplicate override correction `ad7e26eb` → `d6b8c566`. Upstream-latest collection patterns inspected at e0563ffa; existing offline behavior retained.

PASS: analysis clean; Flutter 1759 passed / 3 skipped / zero failures (04:13); Kotlin checks NOT RUN (no Kotlin source changes); Rust script NOT RUN (no Rust source changes).
Graph d6b8c566, source ad7e26eb: 23,954 unique nodes / 45,967 valid links; synchronized, existing vendor extraction warnings remain.
No APK; Six new light/dark collection-state regressions cover selection exit, hydration and current-row toggling. Initial fixture failures were missing duration and duplicate provider setup; corrected before final verification. No dependencies, schemas, music-file writes, native changes or APK. Physical visual checks NOT RUN. Next: batch 11 (MORN-006..012; FIX_PLAN M3+M4).

**Upstream port batch 9 (2026-10-20):** U-301 adds the owner-selected optional per-player Android equalizer: 5/10/15/31 bands, tone/preamp/balance, headroom, limiter/compressor, local presets and bounded JSON import/share. A Mornye-only editor and player/settings menu routes use retained grouped controls. Audio-info now reports EQ/bypass/native errors. Existing playback transport and direct/exclusive output remain intact.

U-301 source `8e05cbbf` → graph `babdbbbe` (ecf594aa + 68c739df); installed picker/API and bounded stream import correction `892eb173` → `5c602c59`; scrolled-control test fixture `c7924c53` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1753 passed / 3 skipped / zero failures (04:16); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph fd1a520b, source 892eb173: 23,940 unique nodes / 45,919 valid links; synchronized, existing vendor extraction warnings remain.
No APK; No dependencies/schema changes, user-music writes, Darwin backend or engine replacement. EQ defaults off and native failures are visible; direct/exclusive output bypass is covered by mocked transport tests. Physical sound/driver support and share/picker targets NOT RUN. Initial Dart/native check failures were installed picker/theme API mismatches, fixed before final verification; focused widget fixtures now settle scrolling before interaction. Model/preset/native-payload/transport/input-boundary tests imported or added. No APK. Next: batch 10 (MORN-001..005 and MORN-017; FIX_PLAN M1+M2).

**Upstream port batch 8 (2026-10-20):** U-304 adds local Rewind highlights and seasonal invitations using recorded listening statistics and Mornye surfaces. U-305 adds pinned Unicode/month section headers and adaptive fast scrolling without changing the dedicated Songs/category layout or bounded paging. U-307 adapts compact launcher-player sizing, preserving existing controls/themes. U-312 bounds restoration checks, virtualizes Settings search, limits logo decoding, avoids redundant static contrast readbacks and scopes pinch updates to the grid.

Source → graph: U-304 `f4fb6794` → `39f9bf4a`; U-305 `6052f9ea` → `ef111d26` (includes U-209 cached locale formatters and U-312 pinned lists); U-307 `2c9c0305` → `e51d221c`; U-312 `c49d7af9` → `c05701ff`. Compatibility fixes `1c589407` → `4f5bc88d`; Rewind header/offline fixture fix `c3d79e0d` → final graph checkpoint (see history).

PASS: analysis clean; Flutter 1739 passed / 3 skipped / zero failures (04:10); Android unit 62 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 9020a7aa, source c3d79e0d: 23,813 unique nodes / 45,709 valid links; synchronized, existing vendor extraction warnings remain.
No APK; No dependency/schema changes or user-owned music writes. Rewind share targets and launcher resizing on physical devices NOT RUN. Initial analysis mismatches corrected using retained APIs; initial Flutter failures caught an unbounded close control and an upstream remote-source fixture assumption, both corrected before final checks. No runtime speedup measurement. Android widget visual redesign/preview intentionally excluded. Next: batch 9 (U-301 equalizer only).

**Upstream port batch 7 (2026-10-20):** U-308 completes local lyric quote cards, menu/long-press entry points, on-demand document reads and stale-share guards, restyled using retained Mornye controls. Compatible held-word glow honors reduced motion and a bounded fade window, preserving settled/background ticker suspension. U-302 adds optional local music haptics, stable SAF identity and owned decoder jobs, transport synchronization, basic-motor support and bounded sensitivity/strength settings.

Source → graph: U-308 `d83068e6` → `9ae8c833` (78a5e078/2782b1f7); U-302 `df164fb1` → `ba844ef0` (11c6cf99/2455cabc/9acaa760). Follow-ups: artwork guard lint `b02895b0` → `1bb926e3`; Mornye selection fixture `a9433d82` → `6bb22e86`; virtualized-card assertion `de546bd7` → `e0fd4bbe`.

PASS: analysis clean; Flutter 1692 passed / 3 skipped / zero failures (03:55); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph e0fd4bbe, source b02895b0: 23,480 unique nodes / 45,224 valid links; synchronized, existing vendor extraction warnings remain.
No APK; No dependencies/schema changes or user-music writes. Music haptics defaults off; physical motor sensation/timing and OS share targets NOT RUN. Android VIBRATE permission is the only permission added. Initial quote-limit fixture assumed all rows remained visible; corrected to reveal rows, assert 5/5 and scope preview checks to LyricsShareCard before final verification. New card preserves local artwork policy; no network provider restored. Next: batch 8 (U-304, U-305, U-307, U-312).

**Upstream port batch 6 (2026-10-20):** U-210 fits collection covers to short screens. U-217 adds release-triggered upward mini-player opening while keeping horizontal dismissal. U-218 adds bounded normalization pre-amp and Track/Album gain, with one cached tag read and live settings changes. U-303 adds a tappable quality badge and Mornye audio-info sheet with read-only Android route facts, current gain/rate/direct state, local analysis and copied reports.

Source → graph: U-210 `c2f38c86` → `e0f9ba6d` (d28e3f65); U-217 `8a9f6091` → `53b473f0` (37162363); U-218 `0d126507` → `ae93ce55` (9eea6a1a); U-303 `bd8f88a6` → `44cbd9e8` (40f65d3a plus U-209 acbc614f number-pattern reuse). Fixture correction `8b7adfe6` → graph checkpoint (see history); initial imported sheet tests lacked ProviderScope, corrected before final verification.

PASS: analysis clean; Flutter 1670 passed / 3 skipped / zero failures (03:59); Android unit 61 passed / 1 skipped; Rust script NOT RUN (no Rust source changes).
Graph 1735a8c3, source 8b7adfe6: 23,304 unique nodes / 44,944 valid links; synchronized, existing vendor extraction warnings remain.
No APK; No dependencies, schema or user-music writes added. Native route support varies by device; actual playback/GPU/route behavior needs device checks. U-303 standalone HiResCheckCard depends on absent services/online wrappers and is excluded; existing AudioAnalysisCard retained. Audio-info EQ reporting is pending U-301 batch 9. Next: batch 7 (U-308, U-302).

**Upstream port batch 5 (2026-10-20; continued MEDIUM preference):** U-214
`10c04f7a` gates local Android startup channels on Activity attachment; U-215 `fa838caa`
applies the existing renderer rules before shared engine creation and adds the scoped
Android 15 Xiaomi workaround. Minimal Application registration and vendor patch documented;
no crash reporter or playback replacement. U-208 Material-only slider hunk rejected.
U-209 `ba751b35` / `2c4ce3ff` reuse existing Dart lyric-alignment and Rust credit patterns.
Removed online/download/history hunks rejected; missing audio-info and queue-section
formatter hunks deferred to their scheduled batches 6/8. Graph `11d8f750` synchronized
from `2c4ce3ff` (23,147 nodes / 44,693 links). PASS: analysis clean; full Flutter 1,659 passed / 3 skipped / zero failures (4m02s); Rust fmt/Clippy clean, 231 passed / 1 ignored; Android unit 61 passed / 1 skipped (1m06s).
No APK, dependency/schema changes or physical-device validation. Next: batch 6 only
(U-210/U-303/U-217/U-218); KT-202 remains open.

**Upstream port batch 4 (2026-10-20; requested MEDIUM):** U-205 `6e44c6be` reports
Android output failures without advancing the queue and supports retry; U-216 `95e2b158`
notifies open players when a same-ID snapshot gains duration/artwork/metadata. U-206 targets
the legacy Material fallback and is not imported: retained Mornye title/swipe behavior
already avoids the outgoing-title stack. U-207 `d0818d7a` resolves verified SAF parents and propagates requested
LRC write failures; excluded online re-enrichment/download tests remain absent. Current
engine, UI and vendored descriptor patch retained. Graph checkpoints `a95ffcf6`, `4c66e5e7`,
`a85b4965`; final graph 23,112 nodes / 44,630 links. No dependency/schema/Rust source changes.
Batch 4 verification: PASS: analysis clean; full Flutter 1,657 passed / 3 skipped / zero failures (4m10s); Android unit 59 passed / 1 skipped; changed plugin and instrumentation Kotlin/Java compiled (1m58s). No APK. Next is port batch 5.

**Upstream port batch 3 (2026-10-20):** U-203 `e70ae974` recovers missing local album
artwork in headers/grids, retaining Mornye controls and local images. U-212 `1d8e8f76`
shares aligned ID3 picture parsing, safely strips recognized-image NUL padding and repairs
app-owned cached previews; extension hunks excluded. U-213 `d256e0c7` extends existing
embedded artwork recovery to filesystem playback without any online fetching. U-204
`a41d3d4e` waits for audible progress/alignment before effect handoff and renders enough
input for faster effects; current engine, fallback and cancellation retained. Each source
commit has its own Graphify checkpoint (last `de32a041`; 23,093 nodes / 44,593 links).
Batch 3 verification: PASS: analysis clean; full Flutter 1,644 passed / 3 skipped / zero failures (3m55s); Rust fmt/Clippy clean, 231 passed / 1 ignored. No APK. Next is port batch 4.

**Upstream port batch 2 (2026-10-20):** U-202 `0f51f5d0` adapts `3dc2d690` to
preserve integer FLAC samples in the existing exact PCM output paths, bypassing vendor
extractors that may reduce precision. Statically linked libFLAC 1.5.0 is checksum-pinned;
its license and byte-precision/seek/truncation tests are included. No player-engine migration.
U-201b `e58217c8` has only removed-network production changes, even in local provider files;
local native cancellation already exists, so none imported. Optional `931b1091` importance
diagnostics are unnecessary for U-201. KT-202 remains open: scan recovery does not fix
incremental CUE duplicates. Graph `6361145f` synchronized; WIP patch removed after review.
Verification: PASS: analysis clean; full Flutter 1,629 passed / 3 skipped / zero failures (4m02s); Android unit 59 passed / 1 skipped; native host CTest 1/1 passed; ARM64 JNI/library build passed. No APK built. Next is port batch 3.

**Upstream port batch 1b (2026-10-20):** U-103b ports lyric spring scrolling (`91add520`,
code `f10f45f6`) and lyric-only performance improvements (`7600c169`, code `81869c48`):
indexed overlapping voices, cached prefix geometry, bounded/deferred long-document row
measurement, stopped subscriptions/timers while hidden or backgrounded and stopped completed
word tickers. Keeps quick scrubbing, reduced motion, manual-scroll ownership and the existing
single-file lyric widget. U-308 is partial: display-end estimates, held overlap focus and
backing-vocal drop-in from `78a5e078` are present; share cards, sharing entry points,
provider work and glow styling remain pending. No Material-only UI or branding ports.
U-104 dominant cover colors (`913faaa`) and U-201 scan recovery (`e8cff13`) are validated;
`f34ead84` fixes the latter's nullable subtitle lint. Analysis is clean; full Flutter suite
passes **1,629 tests, 3 skipped**. Android unit tests pass **59, 1 skipped**, including both
scan exit-info tests. No APK built. Graph refreshed and validated; next is port batch 2.

**Upstream port batch 1 (2026-10-20):** U-001 per-field tag separators (`5393d1d`: artist,
album artist, composer and genre separators applied on Edit Metadata saves through the Rust
writers and the FFmpeg fallback; Local Library > Tag separators; backups round-trip),
U-101 AutoMix advancing-audio wait (`a5bc4a8`), U-102 adjacent-title cache (`051ff44`) and
U-103 lyric segment geometry cache (`940fd79`). `flutter analyze` clean, Rust backend check
passes; full `flutter test` has only the accepted `file_stat_boundary_test` failure plus the
pre-existing `models_and_utils_test` app-state v4 expectation (database is now v5).

**Review-agent system (2026-10-19):** Adds a quota-bounded review setup without changing app
source: `reviews/PROTOCOL.md` (shared rules), `reviews/` state files, 14 read-only reviewer
agents plus `review-fixer` in `.claude/agents/`, `/review` and `/audit` skills, and
`scripts/review_scope.sh` for model-free scope, reviewer routing and graph freshness. No code
review has run yet; baseline analyze/test/Rust checks are logged in `reviews/VERIFICATION.md`.

**Song-menu actions and anchoring follow-up (2026-10-19, `6ac8efd`):** Restores the old local
track overflow actions in Songs, playlists/Loved Songs, albums, Genres and Artist Popular.
Play/Share shortcuts, Play next/Add to queue, local album/artist navigation, Copy file path,
Edit Metadata, ReplayGain apply/remove, Audio Quality Analysis and confirmed deletion reuse
local playback/tag/queue/index services. CUE tracks offer Split into Tracks with confirmation
and a SAF destination picker, private staging and cleanup; virtual-row deletion only removes
the index row. Physical deletion clears shared file index entries and refreshes album rows.
The removed metadata route, Wishlist, format conversion and online actions stay removed.

Every production song ellipsis captures its own root-overlay rectangle before async local
lookup. Song popovers constrain their height to the larger available region above/below the
button and scroll; existing context-menu callers retain their default layout behavior.
Regression checks cover actual row buttons at top/bottom positions in LTR/RTL, access to
the last action, restored menu contents, queue dispatch, clipboard, cancel/confirm physical
deletion, CUE split cancellation and backing-file preservation, editor/analysis navigation,
and album playback controls.
Validation: `flutter analyze` reports **No issues found**; the full `flutter test`
run passes **1,597 tests, 3 skipped**. The focused regression suite passes 42 tests.
The code graph has been refreshed. This follow-up is committed in source; published
Local build 166 predates it and no replacement APK was built during this fix.

**Settings cleanup and Local build 166 (2026-10-19, `3d798c2`):** Detailed logging moves to the
first content group in Logs, retaining its existing persisted switch and log-buffer behavior.
The now-empty App settings category/page is removed; settings search routes logging to Logs.
Embed lyrics, its output-mode submenu, unused preference fields/setters/serialization and
13 retired labels are removed. Local lyrics playback and metadata/lyrics editing remain.
Appearance no longer has the decorative Library preview; color, glass, Player view and
other appearance controls remain. Mornye Settings/Library subpages reuse the album header's
HeaderCircleButton and back icon; custom selection-mode close controls stay functional.
Build/log numbers increment to 166 for the ARM64 side-by-side Local release.
Validation: generated settings/localizations refreshed; `flutter analyze` reports
**No issues found**, and the full `flutter test` run passes **1,590 tests, 3 skipped**.
The existing log-selection test now scrolls to the first log row after the new switch
increases content height. Removed settings/preview symbols and search entries are absent.
Source changes were pushed before building the verified APK described below.

**Verified ARM64 Local build 166:** Source `b62b3d9e`, version 5.1.1 / build 166,
split versionCode 2166. Built with `SPOTIFLAC_SIDE_BY_SIDE=true`,
`SPOTIFLAC_RUST_ANDROID_ABIS=arm64-v8a` and `flutter build apk --release
--target-platform android-arm64 --split-per-abi --dart-define=GIT_COMMIT=b62b3d9e`.

APK: **54,065,931 bytes**. Audited package `com.zarz.spotiflac.local`, label
SpotiFLAC Local, minimum API 24 / target API 37, ARM64 only and all 17 native libraries.
APK CRC/backend checks, AArch64 ELF/ZIP 16 KB alignment, embedded source revision, offline
permissions and cream adaptive icon background pass. APK signatures verify and match
build 165, preserving Local app updates/data. Analysis is clean; 1,590 tests pass, 3 skip.
No physical-device installation/playback test was run in this environment.

Download branch: `apk-local-arm64-166` (APK, README, SHA256SUMS, APK_DETAILS.json).
SHA-256: `5884f74494d15f06897b64461e193c286bfb492edb1a10607f4722aa42b363bd`.

**Local song controls, metadata-page retirement and Genres (2026-10-19, `26f8e71`):** The separate
metadata details route and its display/cover/lyrics/menu/file-action modules are removed,
including the unused barcode visualization/encoder and 69 unused page-only translation
keys. Existing Home, Search, artist, album, Songs and collection song entry points now
start local playback instead of opening the removed route. Player details remain their
separate existing read-only sheet. Per-song menus contain Edit Metadata and Audio Quality
Analysis; the former keeps the existing editor/controller and tag/cover/lyrics persistence,
and the latter opens the retained analysis card/cache/spectrogram workflow. The old
single-file menu actions are removed; existing independent batch operations remain.

A shared song row provides artwork, title plus explicit E badge, artist, circular play
control and ellipsis for Songs, playlists and Loved Songs. Album rows reuse it with track
numbers. Selection/range selection and queue context remain supported. Artist Popular
retains its compact five-per-page layout, with playback on row taps and a song menu.
Edited file tags refresh the library index without changing file/source identity or
unrelated audio facts; changed cover art is extracted to a new library cache entry.
Album rows refresh after saving. Collection rows resolve current scanned tags by ID.

Library categories are Playlists, Artists, Albums, Songs, Genres, Loved Songs and Favorite
Artists. The Loved Songs rename is localized and leaves existing collection keys/backup
formats intact. Genres uses 40-row local SQLite pages over the visible-source view;
blank tags are excluded, semicolon/newline multi-value tags are split, case variants are
grouped, and repeated tags count a song once. Genre selection opens matching local tracks,
with exact tag matching (Rap does not include Trap), the shared row, playback and editing.
Local index changes refresh genre pages. No network catalog or schema migration is added.

Validation: `flutter analyze` reports **No issues found**; the full `flutter test` run
passes **1,590 tests, 3 skipped**. Coverage includes editor availability, menu analysis
navigation, artwork/number rows, album pause/resume, selection and range selection,
Loved Songs/category navigation, tag refresh identity, and real SQLite genre grouping,
exact matching and paging. Songs list controls retain current-track pause/resume.
No APK was built at that source commit; the change is included in build 166 above.
Physical-device validation remains pending.

**ARM64 Local build 165 (2026-10-19):** `c4b79cee` includes the artwork row layout fix
and increments Flutter/log build numbers to 165. Same release flags as build 164:
`SPOTIFLAC_SIDE_BY_SIDE=true SPOTIFLAC_RUST_ANDROID_ABIS=arm64-v8a`,
`flutter build apk --release --target-platform android-arm64 --split-per-abi
--dart-define=GIT_COMMIT=c4b79cee`.

APK: **54,328,531 bytes**, version 5.1.1 / build 165, split versionCode 2165.
Verified **SpotiFLAC Local** / `com.zarz.spotiflac.local`, min API 24, target API 37,
only ARM64, all 17 native libraries AArch64 with 16 KB ELF/ZIP alignment, Rust packaging,
offline permissions, cream adaptive background and the embedded source revision. Signature
verification passes and the certificate matches build 164, preserving in-place updates.
Static analysis is clean; **1,609 Flutter tests passed, 3 skipped**. No physical-device
verification in this environment; user confirmation of Loved after updating remains pending.

Download branch: `apk-local-arm64-165` (APK, README, SHA256SUMS, APK_DETAILS.json).
SHA-256: `bcaedfb169b3dec2f3d6e84485608f8c534926a6a0b449913ccf75b9b17a0bf0`.

**Loved local-artwork layout follow-up (2026-10-19):** `c4b79ce` fixes the row layout.
The user confirmed build 164
still displayed one saved Loved track but no row; the device log contained no errors.
The previous no-artwork/ticker test missed the failing local-cover branch. Reproducing
with an actual PNG exposes `BoxConstraints forces an infinite width and infinite height`
at `LocalCoverImage`'s fade Stack inside a collection row. `Image.frameBuilder` wraps the
image outside its own width/height constraints; the expanding Stack therefore received
unbounded list-row axes and prevented the entire track card from laying out.

The shared image fade Stack now passes constraints through to the image, which supplies
its explicit/intrinsic size, while the placeholder fills that resulting size as a positioned
background. Fades and placeholders remain supported. Loved regression coverage includes
real/missing local covers, paused/active tickers, navigation into Loved, finite compact row
bounds and empty-to-populated collection updates. This applies to playlist thumbnails too.
Validation: **42 focused tests pass** for collection playback/selection, real/missing
artwork and image decode/detail behavior. The new real-artwork test failed before the fix
with infinite constraints and no visible row; it passes after the fix, including route
navigation and finite compact row bounds. `flutter analyze`: **No issues found**. Full
Flutter suite: **1,609 passed, 3 skipped**. Build 165 contains this follow-up; the earlier
published build 164 does not. Physical-device confirmation remains pending.

**ARM64 Local build 164 (2026-10-19):** `1d29cf4f` increments the Flutter and log build
numbers to 164, retaining version 5.1.1. Built with the same settings as build 163:
```
source /workspace/toolchains/activate.sh
SPOTIFLAC_SIDE_BY_SIDE=true SPOTIFLAC_RUST_ANDROID_ABIS=arm64-v8a \
  flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --dart-define=GIT_COMMIT=1d29cf4f
```

Output: **SpotiFLAC-Local-arm64-v8a.apk**, **54,328,531 bytes**, version 5.1.1 /
build 164 (split versionCode 2164). Verified app name **SpotiFLAC Local**, package
`com.zarz.spotiflac.local`, minimum API 24 and target API 37. The certificate matches build
163, so it installs as an update to Local while retaining the original SpotiFLAC app.
All **17 native libraries** are AArch64 ELF64 with 16 KB-compatible ELF/ZIP alignment.
Rust backend packaging, source revision, offline permissions, signature verification and
the compiled cream adaptive icon background passed inspection. Host and ARM64 Rust backend
were rebuilt by Gradle. Static analysis is clean; the code immediately before the
build-number-only change passed **1,607 Flutter tests, 3 skipped**. Physical-device
installation/playback remains untested in this environment.

APK download branch: `apk-local-arm64-164` (APK, README, SHA256SUMS, APK_DETAILS.json).
SHA-256: `888ab03c7ad9487b7f6895dd8eb7e21e07b4fad6beca0d5bb409f585be165e15`.

**Local Library preference cleanup (2026-10-19):** `5651613` removes Default view and Audio quality
label selection from the Local Library page and settings search. Their picker
sheets, preference fields/serialization, constants, normalization and setters are deleted.
Old settings/backup JSON ignores both retired keys and excludes them when re-exported.
Library sections retain the active/last-used section instead of applying a configured
reset on tab activation; the unused shell-to-Library activation plumbing is removed.

Quality metadata remains available for local playback and file information. Library card
badges and common album-header labels use the former standard measured/stored bitrate
policy, with detected codec fallback for legacy lossy files. Alternate label-mode dispatch,
mode-dependent caches/provider subscriptions and an unused download-completion label helper
are removed. Scanning, folder/source management, duplicate controls and cleanup remain.
Unused control-only translations are removed; shared metadata labels remain.

Validation: generated settings JSON/localizations refreshed; `flutter analyze` reports
**No issues found**. Full Flutter suite: **1,607 passed, 3 skipped**. Coverage checks the
removed rows/search entries, legacy JSON import/export, standard bitrate/legacy codec
labels, preserved tab selection, library scanning/cleanup and local playback. Source search
finds retired preference keys only in the compatibility regression test. Graph refreshed;
no native changes or APK build.

**Earlier Loved row visibility attempt (2026-10-19; incomplete on device):** `964a054` removes the entrance-animation wrapper
from Loved and playlist song rows. A regression test reproduces an invisible single row
while its count remains visible when animation tickers are paused; collection rows now
paint immediately without depending on ticker progress. The same test covers ordinary
animation settings and an empty-to-populated update. Saved collections, playback and
selection behavior remain intact. The physical-device screenshot's exact navigation
sequence has not been reproduced on a device.

Validation: `flutter analyze` reports **No issues found**; **35 focused widget/playback tests
pass**, including the new opacity regression, collection selection/queue behavior and
Mornye detail headers. No native changes or APK build. Code, refreshed graph and progress
notes use the repository's separate commits.

**Home and Library cleanup (2026-10-19):** Home no longer renders or subscribes to the
Recent access-history section; the separate Search surface retains its existing history.
Latest Releases uses a bounded `release-date-newest` album query over scanned song tags.
Year, year-month, ISO date/timestamp, slash-date and compact YYYYMMDD metadata normalize to
chronological sort keys; invalid calendar dates and undated groups are excluded. An album
uses its newest valid song tag. Equal dates use a stable album key, with no scan/add-time
fallback. The displayed date preserves the source tag's precision rather than presenting
an invented January 1 for year-only metadata. Home's Recently Added loader/order is unchanged.

Library overview now contains only matching category rows: Playlists, Artists, Albums,
Songs, Loved and Favorite Artists. The last two open their existing local collection pages.
The overview no longer queries, renders or pages the Recently Added album grid. Albums,
Artists and cross-library search retain their existing bounded queries. Dedicated Songs
removes collection/individual-playlist rows and includes playlist-member songs instead of
hiding them; Playlists remains in its own section.

Validation: `flutter analyze` reports **No issues found**. **26 focused tests pass**, covering
release metadata versus scan time, date formats/calendar validation, stable cursor pages,
metadata updates, original tag display, unchanged Recently Added ordering, no Home history
subscription, Library row ordering/routes, no overview album query and songs already saved
in playlists. Final full Flutter suite: **1,613 passed, 3 skipped**. No native code/schema changes
or APK build. Graph refreshed from the finished source. Per the user's request, this phase
uses one combined commit, then publishes to `main`, including the previously committed guide
consolidation (`f5d0afd` through `eb7aa5d`).

**Unified first-run guide (2026-10-19):** `f5d0afd` removes the obsolete download/output-folder
setup page, folder selection/recovery handlers and output-directory writes from setup.
The existing local search, playback, Library, music-folder and settings tips now live in
`local_guide_pages.dart` inside the same setup PageView, after Welcome/language and before
permissions. This yields nine steps on Android 13+ and eight on older Android versions,
sharing one counter and Back/Next navigation. Get Started sits on the former penultimate
permission step (notifications on Android 13+, storage otherwise) and opens Home directly.
The separate TutorialScreen is deleted; its old route redirects to unified setup. Both
completion flags are persisted together before publication, preventing a second guide after
completion/restart. Versioned progress drafts retain their page and notification skip choice;
legacy permission/folder indices migrate to their corresponding retained permission page,
ignoring former output-folder fields. Local Library settings still select scanning folders.

Unused setup-folder and duplicate welcome translations were removed. The guide copy checks
also exposed incorrect Hindi/Russian app-name translations, now corrected. Regression tests
cover both Android permission layouts, integrated tip titles, Back navigation/resume, old
folder drafts, permission refresh, optional notification skipping, Home completion, atomic
completion flags and restart routing. The obsolete iOS output-folder setup test was deleted.
`flutter analyze` reports **No issues found**; the final full suite passes **1,610 tests,
3 skipped**. The initial full run identified that obsolete iOS test as its only failure;
the final run is clean. Graph refreshed (`e15e51a`) and no TutorialScreen node remains.
No native code changed, APK was built, or commits were pushed for this task.

**Wishlist removal (2026-10-18):** `d44a273` removes Wishlist Library cards/rows and
navigation, track-menu actions, folder mode, provider mutation APIs, state/index fields,
backup counts/preview rows/restore commands, hydration/export paths and localized strings.
Native collection reads and restore publication now use schema v3 with only retained
collections. The upgrade drops the obsolete table from v1/v2 databases without rewriting
Loved, playlists or favorite artists. Older JSON/preferences imports ignore removed data;
new collection exports omit it. Playlist hydration now has its own named accumulator.

Validation: `flutter analyze` reports **No issues found**; the full Flutter suite passes
**1,611 tests, 3 skipped**. New regression tests cover real SQLite v1/v2 upgrades preserving
retained rows, ignored malformed legacy JSON and absent Wishlist menu actions. Existing
collection mutation/rollback, paging, hydration, backup and playlist playback coverage was
adapted to retained collections. `bash scripts/check_rust_backend.sh` passes formatting,
Clippy with warnings denied and **227 Rust tests, 1 ignored**. Device integration fixtures
were updated to schema v3 but not executed without a device. Source search leaves only the
obsolete-table deletion and regression fixtures; the refreshed graph query finds no
Wishlist nodes (`e6015e5`). No APK was built in that removal task. Its commits were subsequently pushed to `main`
through `39ba329` at the user’s request.

**ARM64 Local build 163 and contrasting icon (2026-10-18):** `1474c860` replaces the black
launcher background with light cream (`#FFF4DF` for the adaptive icon), keeps the existing
green adaptive/monochrome logo, and regenerates the Android launcher resources. The legacy
raster icon uses the matching cream-background design. Increments `pubspec.yaml` and the
in-app log build number from 162 to 163 while retaining version 5.1.1. The existing
side-by-side switch keeps **SpotiFLAC Local** / `com.zarz.spotiflac.local`, separate from the
original SpotiFLAC package.

Built using the same release/side-by-side settings as build 162, with ARM64 only:
```
source /workspace/toolchains/activate.sh
SPOTIFLAC_SIDE_BY_SIDE=true SPOTIFLAC_RUST_ANDROID_ABIS=arm64-v8a \
  flutter build apk --release --target-platform android-arm64 --split-per-abi \
  --dart-define=GIT_COMMIT=1474c860
```

Output: **SpotiFLAC-Local-arm64-v8a.apk**, **54,345,707 bytes**, version 5.1.1 / build 163
(split manifest versionCode 2163), minimum API 24, target API 37. The signed manifest confirms
`com.zarz.spotiflac.local`, label SpotiFLAC Local and only `arm64-v8a`. All **17 native
libraries** are AArch64 ELF64 with 16 KB-compatible ELF/ZIP alignment. Rust packaging, source
revision, offline permissions, light legacy icon backgrounds and the compiled cream adaptive
background passed inspection. `apksigner verify` passes; the certificate matches the previous
Local APK, enabling an update without uninstalling or changing the original SpotiFLAC app.

Static analysis is clean. The application code passed **1,615 Flutter tests, 3 skipped**
immediately before this icon/version-only change. The host and ARM64 Rust backend were rebuilt
in the APK build. Graph refreshed after the source commit. Physical-device testing remains
pending. Latest collection-action commits were pushed to `main` through `bbc56e0`; icon/build
source and this record are pushed with this build.

APK download branch: `apk-local-arm64-163` (APK, README, SHA256SUMS and APK_DETAILS.json).
SHA-256: `bef4e5213fcb40cb529b809c4605a840a50cfcb05dd780a20cef39845410b83f`.

**Centered collection playback actions (2026-10-18):** `d78043f` updates the shared album/playlist action
row now includes both Play/Pause and Shuffle between Loved on the left and Add to playlist
on the right. Previously the presence of the two outer icons hid the inline Shuffle action,
leaving it in the corner toolbar. Removes the toolbar Shuffle controls from local albums and
Library collection folders; playlists, Loved and Wishlist all use the corrected shared row.

Reuses the existing filled Play and translucent Shuffle pills, with equal available widths,
compact padding/icons/type and 48px minimum touch heights. Outer Loved/playlist icons use
48px targets. The physical left-to-right order remains consistent with RTL metadata. Header
colors, playback/pause behavior, shuffle queue loading, Loved mutations, playlist picking,
playlist editing/export, selection and the separate artist header are preserved.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,615 passed, 3 skipped**. Focused tests cover the four controls'
order, bounds, touch targets, styling and callbacks in light/dark, 320px widths, RTL and 2x
text. Album and playlist playback checks exercise Shuffle from the new row; playlist/Loved/
Wishlist screen tests check that no toolbar Shuffle remains. The graph was refreshed after
the code commit. No APK was built in that change; the commits were subsequently pushed to
`main` through `bbc56e0` and are included in the new build 163 recorded above.

**Selectable player view and History View cleanup (2026-10-18):** `c609d90` adds
**Player view → Normal view / Immersive view**. Normal remains the default. The preference
uses the existing Mornye full-bleed artwork layout/background rather than adding another
player implementation. Immersive portrait artwork stays edge-to-edge while paused and fades
into the existing controls; landscape keeps the established two-column layout. The saved
theme setting loads at bootstrap, survives subsequent theme edits and serializes safely;
unknown/missing values fall back to Normal.

The full cover stays mounted while lyrics/queue panels fade, with pointer/semantics and hero
ownership handed to the compact header. View changes and rotation replace the background
without retaining duplicate global artwork keys. Both views use the existing seek, playback,
volume, lyrics, queue and track-navigation controls and mini-player dismissal geometry.

Removes the Layout/History View selector, Settings search result, app-setting field, setter,
JSON serialization and obsolete localized strings. Older imported JSON containing the retired
field is accepted and ignores it. Library overview cards and dedicated section rows retain
their structural layouts without reading the removed preference.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,609 passed, 3 skipped**. Focused tests cover persistence in light/dark,
legacy settings, search navigation, full-bleed geometry, pause, small portrait and landscape,
rapid lyrics/queue transitions, track changes, live view switching and both mini-player
dismissal paths. Production-source/ARB searches confirm no retired History View preference,
selector or localization references remain. Graph refreshed after the code commit. No APK
built. The player-view commits were subsequently pushed to `main` through `f63648a`.

**Format conversion removal (2026-10-18):** `19a28b3` removes Convert Format from the file metadata
menu and Convert actions from Library/queue, search results and album track selection.
Deletes the conversion sheet, lossless encoding/quality/resampler options, batch conversion
runner, conversion-specific SAF publication/history persistence, library replacement methods,
automatic conversion helpers and codec probes/cache used only by conversion. All conversion
localization keys are removed across the ARBs; bitrate and original-cover labels now have
neutral keys. Setup, tutorial and cache text no longer advertise conversion.

CUE splitting is extracted into `ffmpeg_cue.dart`; retained metadata, CUE and ReplayGain UI
helpers move to `track_metadata_file_actions.dart`. File tag/cover/lyrics editing, ReplayGain,
artwork dimension probing, safe temporary-output publication and built-in playback remain.
Conversion-specific tests are retired; shared selection and metadata menu tests assert the
absence of conversion while retaining playback, ReplayGain and metadata editing coverage.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,598 passed, 3 skipped**. Search/selection regressions pass in both theme variants and
portrait/landscape layouts. Source and ARB searches confirm the removed conversion entry
points, services and localization keys are absent. Graph refreshed after the code commit.
No APK built. The conversion-removal commits were subsequently pushed to `main` through
`ffab9ba`.

**Settings cleanup (2026-10-18):** `8fa30b9` removes the obsolete Files & Folders
output-folder page and download-era Metadata page, their root Settings destinations and
nested search entries. Their unused setters and picker-specific widget tests are removed;
local file metadata editing and compatibility fields used by tag rewriting remain. Music
source folder management stays in Local Library. Existing setup/folder-grant handling remains.

Playback uses the built-in player exclusively. The Player chooser, Now Playing external-player
actions, player-mode model/serialized field and setter, mode-based automation gates and all
external playback/fallback branches are removed. Old JSON/backups containing `playerMode`
are accepted but ignore that unknown key. Each playback entry point requires successful
built-in initialization; failure reports an error without opening another app. Queue selection,
Previous/Next, CUE checks, ReplayGain, AutoMix, autoplay, mute/headphone automation and USB
hardware/output controls are preserved. The automation helper's enable flag now controls only
automation, rather than switching a player implementation.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,625 passed, 3 skipped**. Focused regression checks cover Settings/search absence, legacy
JSON compatibility, all four playback entry points refusing external fallback on initialization
failure, queue ordering and enabled built-in controls. Retired tests covered the removed picker
pages and external-mode behavior; setup's folder-grant test and local tag-mode compatibility
coverage remain. Production source was searched to confirm no remaining removed page classes,
player-mode consumers or external-player actions. Graph refreshed after the code commit.
No APK built or GitHub push performed for this cleanup; the installed APK predates it.

**Artist Popular refinement (2026-10-18):** `7056525` replaces Songs and numeric arrow
pagination with **Popular**, five songs per page and tappable dot indicators. It shows at
most 20 unique available local tracks (four dots when 20 tracks are available; fewer for a
smaller artist library). Recorded all-time play counts determine rank, with random selection
and tie order for unplayed tracks/no history. The selection stays stable while the page is
open. Reads scan the artist in bounded 40-track pages, retain only the best 20 candidates and
query aggregated listening counts for each page's local path/ID identities. Listening database
version 2 adds a track-key index while preserving existing history. Pending recorder writes
are flushed before statistics reads.

All artist Show-more controls are removed. Albums/Singles continue loading bounded pages
when swiped near the shelf end, with Retry only for failed reads. Artist Play still loads the
entire artist queue; its loader is retained during startup so the Popular cap cannot truncate
or dispose playback. The newest featured release and tag-based Singles/Albums rules remain.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,630 passed, 3 skipped**. New provider/SQLite tests cover most-played ranking across page
boundaries, summed play counts across days, random fallback across the entire artist library,
unique 20-track caps and smaller libraries. Light/dark widget tests verify four interactive
dots, no numeric counter or Show-more controls, automatic discography pagination past 40
releases and full 41-track playback. Rendered light/dark previews were inspected. Graph
refreshed after the code commit. No APK built or GitHub push performed for this refinement;
the installed APK predates this change and the fragmented Opus header follow-up.

**Fragmented Opus header follow-up (2026-10-18):** Device scan found 1,949 tracks with
28 metadata errors, all "Ogg header spans too many pages". The previous 1,024-page cap still
rejected comment/artwork packets below the 64 MiB byte budget when spread across small pages.
`3afd609` removes that cap for metadata, artwork and tag editing. The existing 64 MiB header
byte limit remains; audio-quality identification probing retains its short 10-page limit.
Readers still stop after the two required header packets and do not scan audio for tags/art.
Malformed/truncated comments retain explicit diagnostics. No claim is made that the 28 actual
files were examined: regression fixtures exercise the pagination failure shown in the log.

Validation: the expanded Opus regression suite fails against the pre-fix readers/writer
(5 failures with the page-limit error), then passes **8/8** with the fix. Coverage includes
512 KiB comments and artwork across thousands of pages, local scan metadata, tag edits
preserving audio bytes, invalid/truncated comments and a continued packet exceeding the
64 MiB byte limit. `bash scripts/check_rust_backend.sh` passes formatting, Clippy and the
full Rust workspace suite: **227 passed, 1 existing ignored**. No Dart/Flutter behavior or
bridge signatures changed. Graph updated after the code commit. No Android/native release
or APK build was run; the previously delivered APK does not contain this fix.

**Side-by-side ARM64 APK (2026-10-18):** `eb33f36` adds opt-in
`SPOTIFLAC_SIDE_BY_SIDE=true` Gradle configuration. It sets the app name to **SpotiFLAC Local**
and application ID to `com.zarz.spotiflac.local`; ordinary builds retain the original identity.
The packaged manifest also has unique provider authorities, with the original activity class
resolved correctly under the new application ID. App settings/data and folder permissions are
independent of the original installation. Graph refreshed in `3942d11`.

Built with:
```
source /workspace/toolchains/activate.sh
SPOTIFLAC_SIDE_BY_SIDE=true SPOTIFLAC_RUST_ANDROID_ABIS=arm64-v8a \
  flutter build apk --release --target-platform android-arm64 --split-per-abi
```

Output: **SpotiFLAC-Local-arm64-v8a.apk**, 54,510,467 bytes, version 5.1.1 / Flutter build 162
(ABI split manifest versionCode 2162), minimum Android API 24. `aapt dump badging` verifies
name/package and only `arm64-v8a`; all 17 native libraries were checked as AArch64 ELF64,
including the rebuilt Rust backend. `apksigner verify` passes (v2 signature). No physical device
was attached, so installation/playback testing remains pending. The previously validated
Flutter source passed 1,626 tests (3 skipped); this change only affects Android build identity.
APK download branch: `apk-local-arm64-162` (artifact only).
SHA-256: `ddb29a6b7ae632ab614b4c9d48be0df7c99ab7ac85d4d0bf8b083f822d6e9823`.

**Home feed correction (V2, 2026-10-18):** `45e5f17` restores the original Apple Music
large featured-card composition, horizontal album/playlist shelves and circular artist cards.
Featured entries are ordered by local release-date tags; Recently Added uses SQLite ordering
and a 12-track limit instead of hydrating/sorting the full library. Album cards load the exact
local album key, playlist cards open saved collections and artist cards open the V3 detail page.
Scan/index changes refresh the feed; read failures offer Retry. Existing search and recent
access remain available. All artwork stays local. Saved playlist summaries are sorted by
last edit and limited to 12 cards. No online service or home-provider setting is restored.

Validation: `flutter analyze` reports **No issues found**; full `flutter test` reports
**1,626 passed, 3 skipped**. New tests cover scan refresh, disabled-library reads, bounded
shelves, light/dark layouts at 360px with 1.6x text, and local artist navigation. Rendered
layout previews were inspected. Graph refreshed after the code commit (`7c9a08b`). No APK
or GitHub push performed for this change.

**Committed:**
- `f0a1b45` — graphify baseline (graph + report).
- `159a9c2` — Phase 1: removed `ios/`, `third_party/discord/`, online release tooling/docs/scripts;
  trimmed `analysis_options.yaml` platform excludes.
- `91240e2` — Phase 2: Discord rich presence removed (Dart settings/model/l10n, widget, gradle,
  AndroidManifest, build/audit scripts + tests, ios/discord scripts).
- `b038493` — docs: migration plan + progress tracker.
- `757ebcc` — Phase 3: updater / remote-config / announcements / donations removed
  (services, dialogs, upgrade-intro screen, donate page, settings keys + UI, install permission,
  APK FileProvider, tests).
- Phase 4 (this commit) — network storage (SMB/WebDAV/NAS) full rip-out: 10
  `lib/services/network_*.dart`, `network_storage_screen.dart`, `network://` URI scheme +
  branches (player service/runtime, playback, hires check, audio analysis, file access),
  `networkDownloadFolder/Label` settings (model/generated/provider/codec/UI), l10n keys (en/id),
  `dart_smb2` dep + `libsmb2.txt` license, and all `network_*` tests + 2 Python SMB fixtures.
- `05bf2fe` — Phase 5a: extension store / repo tab / provider-priority settings removed
  (`RepoTab`/`repoProvider`, extension store + detail + repo card/row widgets, extensions /
  download-fallback-extensions / lyrics+metadata+provider priority / profile-priority-list
  settings pages, `showExtensionStore` setting, settings-search + download/lyrics/metadata rows);
  `main_shell`/`ShellTab` renumbered without the repository tab. **Kept** the local profile
  feature (`ProfileSettingsPage` + settings profile card) and the extension *registry* +
  `ExtensionStorageService` (keep until the download engine goes in Phase 6).
- `0567a80` — Phase 5b: online metadata autofill, batch re-enrich, local-track redownload,
  cross-extension share, open-on-platform, hi-res check, audio preview removed
  (services/widgets/providers + track-metadata, queue/library, download picker, `main_shell`
  preview observers). Downloads now resolve the default service directly. **Deferred to Phase 6**
  (removed with the download engine): the extension *registry* (`extension_provider`),
  `track_provider` + Mornye home search, and motion artwork.
- `83a02c4` — Phase 5c: explore home feed, weekly releases, artist concerts, motion artwork
  removed (`explore_provider` + featured section + `home_tab_explore` part; weekly-releases
  provider/service/screen; artist-concerts screens/button/model; motion-artwork download/proxy/
  store + motion header banner + player artwork video/motion providers + download motion source;
  `track_provider.artistConcerts`; motion-artwork rendering in now-playing / mini-player / album
  screens / cache management; motion+home-feed settings). Home tab keeps local recent/import
  sections and home search. Phase 5 complete.
- `f3ab83e` — Phase 6: download engine removed and player/queue re-pointed to the local library
  (D1). Deleted all `download_queue_provider*`/`download_queue_state`/
  `download_verification_retry_guard`, `download_history_provider*` (state moved to
  `models/download_history.dart`), `extension_provider*`, `track_provider`,
  `models/download_item(.g)`/`download_result`/`extension`; all `services/download_*`,
  `native_download_history`, `verification_notification`, `cover_download_service`,
  `album_replaygain_readiness`, `extension_storage_service`; `utils/download_error_type`/
  `extension_*`; screens `downloaded_album_screen`/`home_tab_import`/`album_screen`/`artist_screen`/
  `artist_screen_widgets`/`playlist_screen`; widgets `downloadable_cover`/`download_queue_feedback`;
  `settings/download_settings_page`; and the Android `DownloadService*`/`NativeDownloadFinalizer*`/
  `NativeFinalizationPolicy*`/`SafDownloadHandler.kt`/`DownloadQueueWidgetProvider.kt` + widget
  resources (added `SafFileOps.kt`). Re-pointed `music_player_provider`/`playback_provider`/
  `library_search_provider`/`library_browse_provider`/`queue_tab*`/`home_tab*`/`main_shell`/settings
  to the local library DB; purged all download/extension settings keys (kept `downloadDirectory`/
  `downloadDirectoryBookmark`/`storageMode`/`downloadTreeUri`). Per PD2 the Dart SQL layer is
  local-only but `history.db` stays ATTACHed (native-scan exclusion SQL + Rust refs re-homed in
  Phase 7). ~62 offline tests deleted, ~38 edited.
- `dfd7f43` — graphify: refreshed code graph after Phase 6 (57360 → 26443 nodes: deleted code plus
  generated `app_localizations*.dart` now ignored).

**Phase 5 summary:** the entire online extension/provider/search UI layer is gone; what remains
online-coupled (`extension_provider` registry, `track_provider`, Mornye home search) is consumed
only by the download engine and is removed with it in Phase 6. Two now-dead settings
(`homeFeedProvider`, explore-feed cache row) are deferred to the Phase 8 settings purge (V4).

**Phase 6 summary (historical; Phase 7 changes below supersede the native/history details):** the app is now a local-only player in Dart. The download engine, extension
registry, `track_provider`, Mornye home search and all download/verification UI are gone; the
player, queue and search read the local library DB. Per PD2 the Dart SQL layer no longer queries the
download history, but `history.db` remains ATTACHed and the native library scan still excludes it —
both re-homed to Rust in Phase 7. Two kept-but-dormant pieces (`downloaded_embedded_cover_resolver`,
the `history.db` attach) are slated for Phases 7-8. `flutter analyze` repo-wide is clean; full
`flutter test` passes (only the known-flaky perf test).

**Phase 7 implementation:**
- `a9f63b9` pruned core online-support modules; `fa2afff` completed the reduction.
- `7d54453` refreshed the graph from code commit `fa2afff0`.
- New `spotiflac-local` crate owns local scans, CUE handling, metadata/tag writes, artwork,
  lyrics and logging. Scoped file grants, cancellation, atomic file publication and shutdown
  draining remain; shutdown is idempotent and waits for active operations.
- Removed `providers`, `network` and `extensions`; workspace now contains `core`, `local`,
  `mobile` and `bindgen`. Removed 126 lockfile packages without upgrading retained packages.
  Kept vendored rustix/libusb sources unchanged.
- Replaced `ExtensionManager` with automatically initialized `LocalBackend`; removed native
  provider/auth/repository/download APIs and extension event dispatch. Local embedded/sidecar
  lyrics reading, editing and export remain, with no online fallback. Legacy request fields
  remain temporarily for caller compatibility.
- Native and Dart library imports no longer attach/filter against `history.db`.
- Build scripts generate Kotlin bindings only; removed iOS/Swift/podspec/staticlib wiring and
  moved the statx example to the local crate. The native FFmpeg command queue was used only by
  extensions and was removed; local Dart FFmpeg conversion/tag fallback remains.
- Updated Android callers and integration fixtures; removed obsolete extension/download tests.
  Replaced deleted SAF helper references and stale Phase 6 manifest service/widget entries;
  removed retired provider deep links. INTERNET/localhost policy stays pending the Phase 8 audit.

**Phase 7 validation:**
- `flutter analyze`: **No issues found**.
- Full `flutter test`: **1645 passed, 3 skipped**; paging performance test passed this run.
- `bash scripts/check_rust_backend.sh`: fmt/clippy clean; **215 passed, 1 existing ignored**.
- Python script tests: **12 passed**.
- `:app:compileDebugKotlin` and `:app:compileDebugAndroidTestKotlin` passed without APK
  packaging. `:app:testDebugUnitTest`: **63 passed, none skipped**, including six native
  data-job ABI/cancellation tests using the host Rust library. Fixed the fixture FFmpeg imports
  and removed a leftover test of the download-finalizer helper deleted in Phase 6.
- Host and Android ARM64/ARMv7 Rust builds passed. Checked 16 KB ELF segment alignment and
  absence of retired extension/repository exports.
- Kotlin-to-Rust host ABI smoke passed: local metadata, grant revocation, local lyrics/export,
  shutdown, native data jobs and cancellation.
- At the end of Phase 7, APK validation was **incomplete**: a stale Phase 6 widget manifest
  reference was fixed, then release CMake dependency population failed. The user stopped APK
  builds for Phase 7 and subsequently authorized a Phase 8 APK build; see the results below.
- No Android device or emulator is available; app playback, SAF/USB, statx and on-device
  integration tests have not run.
- Graphify was queried before removal and refreshed afterward (AST-only): **23223 nodes,
  44926 edges, 639 communities**. No nodes are attributed to the three deleted crates.
  Eight extractor syntax warnings are confined to unchanged vendored C/libusb sources.

**Phase 8 implementation:**
- `8609ad06` — final local-player cleanup; `929792e1` refreshed Graphify from that code commit. Removed direct dependencies on `http`,
  `connectivity_plus`, `cached_network_image`, `flutter_cache_manager`,
  `flutter_secure_storage`, `receive_sharing_intent`, `video_player`, `dynamic_color` and
  the video-player test interface; removed 19 resolved packages and regenerated the lockfile
  without upgrading retained packages.
  Kept archive/crypto for local backups and hashing, XML/HTML for local parsing, and
  url_launcher for explicit external browser links. Shared widget libraries remain in use.
- Removed Dart extension/provider/repository/search/network wrappers, lookup caches and
  best-effort native provider synchronization. Settings migration 12 clears retired feed and
  lookup preferences; serialization drops obsolete provider and download-only tag flags.
- Lyrics controls now cover local embedding/sidecar output and presentation. Local artwork
  renders from files; stale HTTP(S) artwork is ignored, including widget artwork. Cover export
  copies local artwork through staged publication and rejects remote URLs. Local metadata,
  tag/lyrics editing, backups, local profiles, playback, SAF and USB remain.
- Mornye is the sole production theme, with existing light/dark, accents, glass and font
  controls. Old Material preferences restore as Mornye. The old Material theme is retained
  only as a test harness for shared-widget fallback coverage.
- Removed the download tutorial simulation and provider deep-link actions; onboarding now
  describes local scanning, playback and folder access. Removed online diagnostic heuristics,
  empty provider settings, stale cache rows and history-exclusion UI. Legacy backup record
  import/export remains for local archive compatibility, explicitly labeled as legacy records.
- Localized message getters reduced from **1627 to 894** (obsolete keys removed or renamed,
  with new local-playback messages added). Rewritten offline copy uses English fallback in
  locales awaiting updated translations, avoiding stale instructions about removed features.
- Removed the release Internet/network-state permissions and obsolete network-security file
  after confirming no FFmpeg loopback/decryption tunnel remains. Debug tooling keeps its
  development Internet permission. Native source archive URLs now use direct codeload URLs
  with the same verified SHA-256 pins, avoiding the earlier redirect/download failure.
- README, changelog, contribution instructions, widget docs and agent guidance now describe
  the offline Android player. iOS launcher-icon generation is removed.

**Phase 8 validation:**
- Flutter analysis: **No issues found**. Focused artwork/theme migration, storage and metadata
  tests: **36 passed**.
- Rust fmt/clippy/workspace tests: **215 passed, 1 existing ignored**; host bindings and Android
  ARM64/ARMv7 Rust builds passed. Python script tests: **12 passed**.
- App and instrumentation Kotlin compilation passed. Android JVM tests: **63 passed, none
  skipped**, including all six host Rust data-job/cancellation ABI tests.
- Release APK built with `flutter build apk --release --target-platform android-arm,android-arm64
  --dart-define=GIT_COMMIT=8609ad06`; **119,269,488 bytes**, Android API 24+, ARM64 + ARMv7.
  Artifact: `build/app/outputs/flutter-apk/app-release.apk`, also copied to
  `/workspace/SpotiFLAC-offline.apk` for download.
- `check_backend_apk.py` passed for Rust and both ABIs. Signature verification passed (APK v2,
  development key); ZIP alignment passed at 16 KB. All **17 ARM64 native libraries** have
  16 KB-or-greater ELF LOAD alignment. Both app libraries contain build commit `8609ad06`.
  The merged release manifest is not debuggable and has no INTERNET/ACCESS_NETWORK_STATE
  permission. No production signing key was configured.
- APK SHA-256: `9ac081b9cd9e4d683077ce51a6eb72c7bb2656625e86f7d9b8e30915348ff683`.
- Graphify refreshed (AST-only): **22956 nodes, 44569 edges, 677 communities**; provenance
  `8609ad06`. No nodes are attributed to the removed share service or production Material theme.
  Vendored C/libusb extractor warnings remain confined to unchanged sources.
- Full `flutter test`: **1615 passed, 3 skipped**. Paging performance test passed; all
  album completeness/filter tests passed with the updated local-library wording.
- Physical-device playback, SAF/USB, statx and launcher-widget checks remain unrun: no Android
  device/emulator is attached. A packaged APK and host tests do not establish device playback.

**Post-Phase 8 Opus scan fix (2026-10-18, `6500a82`):**
- Device build 161 reported widespread SAF Opus tag failures. Reproduced a reader defect
  with a real FFmpeg/libopus silence fixture: valid encoder-only comments were rejected
  unless a title, artist or ReplayGain field existed. Accept structurally valid comments,
  including album/lyrics-only metadata; retain filename display defaults and quality probing.
- Preserve parser diagnostics as `metadataReadError` and forward them through SAF failures;
  malformed comments still fail. No file conversion or library reset is required.
- Build **5.1.1+162**. Regression coverage includes Arabic display names, album/lyrics-only
  tags, malformed comments, and repeated borrowed-descriptor reads with/without artwork.
- Rust fmt/clippy clean; **219 tests passed, 1 existing ignored**. Both Android native ABIs
  built. Kotlin app/instrumentation compilation and **63 JVM tests** passed; Flutter
  analysis clean and **6 metadata bridge tests** passed.
- Graphify refreshed: **22962 nodes, 44586 edges**, source provenance `6500a82`.
- Release APK built for ARM64/ARMv7 with source commit `6500a82`. Both split packages
  passed backend/CRC audits, APK signature verification (same certificate as build 161),
  16 KB ZIP alignment and offline/non-debuggable manifest checks. All **17 ARM64 native
  libraries** have at least 16 KB ELF LOAD alignment; fixed native-reader marker verified.
- Download branch: `apk-opus-fix-162` (artifact-only, separate from `main`), with independently
  installable ARM64/ARMv7 APKs, installation instructions and SHA256SUMS.
  ARM64 SHA-256: `2f462b2737af65adacb3c8c1859bfec1516b7ce0cace4f179ff3b34e2adadba6`.
  ARMv7 SHA-256: `d2ed3168621ff4e1cd5e0bbae0453f2587c247730dd76c818725924ee6d4780b`.
- The user's actual audio files and physical Android device are unavailable here; this
  fixes a confirmed failure case consistent with the log, not a verified diagnosis of
  every reported file. Device rescan remains to be checked after installing build 162.

**Follow-up Opus continuation fix (2026-10-18, `34133cc`):**
- The follow-up device log now reports `no Vorbis comments found`. Reproduced this exact
  error with a valid comment packet spanning more than 80 pages. The reader also silently
  discarded packets larger than 10 MiB, including large artwork/padding headers.
- Metadata/artwork now assemble the first two header packets within the writer's bounded
  1024-page / 64 MiB limits. They stop before scanning audio packets. Truncated, interrupted
  or over-budget headers produce specific failures instead of a misleading missing-tag error.
- Quality reads only the identification packet, so large comments do not suppress rate,
  duration and bitrate probing. Regression coverage includes >80-page comments, >10 MiB
  packets, continued artwork, bounded reads, truncated headers, and a real FFmpeg Opus
  stream rewritten with a 6 MiB tag and scanned through a borrowed descriptor.
- Fixed the hardcoded exported-log/about build number from 161 to 162 to match pubspec.
  The follow-up log's build 161 label alone does not identify the installed APK.
- Rust fmt/clippy clean; **223 tests passed, 1 existing ignored**. Flutter analysis:
  **No issues found**. No APK or Android release/native-library build was run for this fix.
- Actual user audio files are unavailable here; the precise on-device header layout remains
  unverified. This corrects reproduced parser failures that yield the reported error.
- Changes are committed locally; no GitHub push or artifact publication was performed.

**V3 detail-design correction (`0e6c88e`, 2026-10-18):**
- Recovered the former Mornye artist/album/playlist designs from Git history rather than
  retaining the generic local artist destination. `LocalArtistScreen` restores the portrait
  identity header, centered Play between Favorite and Shuffle, featured release card,
  five-song carousel, and separate Albums/Singles discography shelves.
- Artist links from metadata/now-playing, album subtitles, home/search, library and favorite
  artists now open the local detail page. Existing favorite entries are matched by local
  artist name; no provider lookup is needed. Local artist reads are paged, support retry
  and disposal, refresh after scans, and build a complete playback queue beyond the first page.
- Album/playlist headers reuse the original immersive artwork, Love / primary playback pill /
  Add-to-playlist composition and release/count/duration footer. Keep shuffle in the toolbar,
  album play/pause/resume, selection, metadata navigation, playlist rename/cover/export actions.
- The featured card follows release-date tags, with scan recency as a tie-breaker. Classification
  uses total-track/disc tags, not the number of files currently stored: explicit one-track,
  single-disc releases are Singles; larger totals, EPs, partial albums and unknown totals are
  Albums. SQLite regression coverage includes an old album added today and one stored track
  from a 12-track album. No EP classification is inferred from the local file count.
- FLAC/Opus readers now honor separate `TOTALTRACKS`/`TRACKTOTAL` and `TOTALDISCS`/`DISCTOTAL`
  comments independently of tag order, retaining valid number-pair totals when separate values
  are invalid. Previously scanned files require a full rescan to populate newly recognized tags.
- Validation: Flutter analysis **No issues found**; full `flutter test` **1623 passed, 3 skipped**;
  focused detail/paging/release/playback/metadata tests **12 passed**. Rust fmt/clippy clean;
  workspace tests **225 passed, 1 existing ignored**. Render checks used the same widget fixtures
  in light/dark and narrow screens with larger text. No Android APK/native release build or
  physical-device run was performed. Corrected the contradictory Phase 6 PD1 decision.

**Environment / toolchain:**
- In each shell run `source /workspace/toolchains/activate.sh`.
- Installed: Flutter **3.47.7**, Rust **1.99.0** with fmt/clippy, Java **25**, Android platform/
  build-tools **37**, NDK **30.0.16248370**, CMake **4.1.2**, Gradle **9.8.1**.
- Activation sets writable caches, libclang and Java proxy/CA trust. No app server is needed.
  Toolchains live outside the repository; fresh-task restoration has not been verified.

**Untracked (generated/artifacts):** covered by `.gitignore`: `.dart_tool/`,
`.flutter-plugins-dependencies`, `build/`, `lib/l10n/app_localizations*.dart`,
`graphify-out/cache/`, `android/.kotlin/`.

**Known flaky:** `test/library_browse_sqlite_paging_test.dart` has timed out at 30s in earlier
runs; it passed in the final Phase 7 suite.

**Next step:** validate local playback, scanning,
metadata/lyrics saving, backup/restore, SAF/USB, widgets and statx compatibility on an Android
device. Complete translations for newly rewritten offline messages as needed. Do not restore
online APIs to satisfy legacy callers.

**Resume instruction:** read this file, then `git log --oneline -10`; continue from "Next step".

---

## 1. Target architecture (what remains)

**Dart**
- Local library DB: `library_database`, `library_native_adapter`, `library_*`,
  `local_library_provider` (without `network://` branches).
- Playback: `music_player_service`/`_runtime`/`_automix`/`_autoplay`, `music_player_provider`,
  `playback_provider`, `playback_*`, `third_party/audio_service`, `third_party/audioplayers_android`.
- Queue, local album/artist/track browsing, playlists/collections, metadata + lyrics editing,
  replaygain, automix/audio analysis, history/stats, settings/theme/fonts, SAF/USB playback,
  Android home-screen widget.

**Rust** (reduced)
- `core` (pruned of online-support modules), `local` (file operations), `mobile` (local-only
  FFI bridge), `bindgen` tool, `vendor/rustix` and `vendor/libusb1-sys`.
- Keep: `core`'s `cover`, `cue`, `filename`, `isrc`, `media`(+`hires`), `native_audio_analysis`,
  `native_palette`, `tags`, `progress`, `cancellation`, `clock`, `matching`, `text`, local `lyrics`.
- Keep local `mobile` modules: `native_library`, `native_backup`, `native_cache`,
  `native_collections`, `native_id3`, `native_lyrics`, `native_playlists`, `native_playlist_write`,
  `native_xml`, `tags`, `hires`, `data_jobs`, `library_metadata`, `filename`, `local`,
  `lyrics`, `cancellation`, `usb_audio`, `logging`. The former extension-only `native_listing`,
  progress pump and FFmpeg command registry are removed.

---

## 2. Original findings (dependency-grounded; pre-migration baseline)

**Rust crate graph**
```
core        -> (none)                     [CLEAN: no edges to online crates]
network     -> (none)
providers   -> core, network
extensions  -> core, network, providers
mobile      -> core, network, extensions   (providers transitively)
bindgen     -> uniffi only (CLI)
```
- `core/src` has **zero** `use spotiflac_{network,extensions,providers}` hits → pruning core is
  safe if `lib.rs` `pub mod` lines + internal refs are removed.
- `mobile` is **7/… files online** (`extensions.rs`, `ffmpeg.rs`, `logging.rs`, `lyrics.rs`,
  `manager.rs`, `network_tags.rs`, `repository.rs`); the rest are local → **reduce, not delete**.
- Local FFI is bound to online structs: `impl ExtensionManager` methods in `mobile/src/tags.rs`,
  `data_jobs.rs`, `lyrics.rs`, `manager.rs`, `metadata.rs` delegate to `extensions::backend::Backend`.
- `extensions/src/backend/{library,tags}.rs` serve local scan/tag writes but sit on the same
  `Backend` struct that holds `NetworkService` + providers, reaching FS via `ExtensionEnvironment`
  (`cap-std`). Extracting them is a refactor.
- `rustix` must stay (kept `core/src/isrc/native_files.rs:55` + local `mobile` cache/tags use it).
  Dropping it would require replacing that one open-flag call site.
- Android build hardwires Rust: `android/app/build.gradle.kts` (`buildRustBackend` task, sourceSets),
  `proguard-rules.pro` keeps `com.spotiflac.backend.**`, Kotlin `SelectedCoreBackend.kt` /
  `NativeDataJobs.kt` import the generated bindings.

**Biggest product coupling**
- `download_history_provider` is imported by `music_player_provider` (`:5`, `:24-27`, `:148-262`)
  and `playback_provider` (`:3`, `:114-116`, `:362`) plus >28 other files. The player's
  "library identity / playable queue" currently derives from `DownloadHistoryItem`.
  → Removing downloads requires re-pointing the player to the local library DB.

**Platforms / assets**
- Platforms present: `android/`, `ios/` only (no macos/windows/linux/web).
- `third_party/`: keep `audio_service`, `audioplayers_android`; remove `discord/` (35 MB `.gpg`)
  and `spotiflac_discord/` (**pubspec path dep** → must edit `pubspec.yaml` + regenerate lock).
- Online dev tooling/docs to drop: `apps.json`, `NETWORK_STORAGE.md`, `crowdin.yml`, `cliff.toml`,
  `renovate.json`, `docs/artist_concerts.md`, iOS/Discord/SMB scripts.
- No `.github/` workflows in the working tree.

---

## 3. Decisions (RESOLVED)

- **D1 — Player data source: (a) re-point to the local library DB.** Delete download history
  entirely; `music_player_provider` / `playback_provider` read from the local library DB.
- **D2 — Home tab: (b) keep `home_tab` as a local "recent access" hub** (recently played/added,
  local albums). Drop Explore/online feed only.
- Minor defaults (accepted): remove `user_profile`/donate UI; remove `hires_check_service`
  (download-era fake-hi-res check) but keep `core`'s authenticity check; keep `automix`,
  `replaygain`, `palette`, `statistics`, `backup/restore`, USB bit-perfect.

### Vision refinements (user, 2026-10-16)

- **V1 — Mornye theme only.** Remove all other themes and the theme picker; Mornye is the sole
  look. Phase 8 retains light/dark, Mornye accents, glass and local font controls; the
  alternate Material theme and picker are removed.
- **V2 — Home feed → local.** Rewire the home feed provider off Apple Music to local content.
  Implemented (2026-10-18): original large editorial cards for latest locally available
  releases (release-date tags), followed by Recently Added songs, local Albums, saved Playlists
  and circular Artists shelves. Recent access/history remains beneath the feed. Each database
  shelf reads at most 12 entries and refreshes with the library index; playlist cards use saved
  collection summaries. All artwork and destinations are local. Search stays a separate mode.
- **V3 — Reuse Mornye "online" theming for local artist / album / playlist screens**, replacing
  the old local styling. Implemented by restoring the original detail composition over local
  data; artist navigation no longer opens a generic filtered album browser. Preserve local
  playback, selection, metadata, collection editing and export actions.
  User refinement (2026-10-18): center artist Play between Favorite and Shuffle; highlight
  the newest locally available album/single by release-date tags (scan recency breaks ties).
  Classify Singles only from an explicit total-track count of 1, excluding multi-disc releases.
  Larger totals, including EPs and partially stored albums, belong under Albums. Unknown totals
  stay under Albums rather than treating one stored song as proof of a single.
  User refinement (2026-10-18): Popular replaces Songs, capped at 20 tracks with five per
  page and at most four dots. Rank by all-time local play counts; unplayed tracks fill any
  remaining places randomly, with a stable order for the open page. Remove artist Show-more
  controls; album/single shelves fetch the next bounded page automatically near the end.
  The artist Play button continues to load the complete local artist queue.
- **V4 — Remove all online-service settings** (extensions/store, providers, downloads, network
  storage, Discord, updates/remote-config, profile, donate, plus online rows inside
  Music/Library settings).

Impact on phases: Phase 5 keeps a **localized** home feed (not dropped); adds a **theming
consolidation** workstream (Mornye-only + style port); Phase 8 settings purge = all online settings.

---

## 4. Phased plan (one commit per phase)

### Phase 1 — Platform & repo-hygiene trim (no Dart code impact)
Remove: `ios/`; `third_party/discord/`; `apps.json`, `NETWORK_STORAGE.md`, `crowdin.yml`,
`cliff.toml`, `renovate.json`, `docs/artist_concerts.md`; scripts `build_ios.sh`,
`check_backend_ios.py`, `test_check_backend_ios.py`, `ios_ffmpeg_capabilities.m`,
`README_ios_ffmpeg_capabilities.md`, `prepare_discord_sdk.py`, `test_prepare_discord_sdk.py`,
`setup_discord_sdk.sh`, `test_network_smb*_server.py`; `assets/readme/` (if README trimmed).
Edit: `analysis_options.yaml` excludes; `.gitattributes` (vendor rules) only if needed.
Verify: `flutter build apk` still succeeds; no Dart touched.
Note: do **not** touch `rust_backend/vendor/` — it is referenced by `[patch.crates-io]`.

### Phase 2 — Discord removal (Dart + pubspec + Gradle + manifest)
Remove: `third_party/spotiflac_discord/`; `lib/services/discord_presence_service.dart`,
`discord_artwork_resolver.dart`; `lib/widgets/discord_presence_settings.dart`; Discord refs in
`main_shell.dart`, `music_player_runtime.dart`, `settings/playback_settings_page.dart`;
`models/settings.dart` `discordRichPresenceEnabled`; l10n `discordPresence*` keys (all 20 arb);
`flutter_secure_storage` only if no other user (verify `secure_storage_options.dart`);
`integration_test/discord_sdk_test.dart`, `test/discord_*_test.dart`.
Edit: `pubspec.yaml` (drop `spotiflac_discord`), `pubspec.lock` (regen), `android/app/build.gradle.kts`
(Discord AAR block, `discordSdkEnabled`, `pickFirsts`), `AndroidManifest.xml` (Discord
`tools:node="remove"`), `scripts/build_android.sh` + `test_build_android.py` + `check_backend_apk.py`.

### Phase 3 — Updater / remote-config / announcements
Remove: `services/update_checker.dart`, `apk_downloader.dart`, `app_remote_config_service.dart`;
`screens/upgrade_intro_screen.dart`; `widgets/update_dialog.dart`, `app_announcement_dialog.dart`;
`settings/donate_page.dart`; `services/upgrade_intro_service.dart`.
Edit: `main_shell.dart` (remove `_checkUpgradeIntro`, `_checkForUpdates`, `_checkAppAnnouncement`,
imports), `settings/settings_tab.dart`, `settings/app_settings_page.dart`.
Manifest: drop `REQUEST_INSTALL_PACKAGES`, APK FileProvider.

### Phase 4 — Network storage (SMB/WebDAV) removal
Remove: `services/network_*` (storage_service, smb_client, certificate, download_staging,
audio_analysis_input, library_scanner, metadata_service, delete, upload, error),
`screens/network_storage_screen.dart`.
Edit: `local_library_provider.dart` (drop `network_library_scanner` import + `network://` branches),
`track_metadata_screen.dart` (network branches), `providers/settings_provider.dart`,
`files_settings_page.dart`, `pubspec.yaml` (drop `dart_smb2`), `assets/licenses/libsmb2.txt` +
`pubspec.yaml` assets list.
Caution: verify `network_security_config.xml` (localhost cleartext used by the FFmpeg decrypt
tunnel) before removing; likely keep localhost entry or drop the file only after confirming.

### Phase 5 — Extension system + online providers + online search (Dart)
Remove providers: `extension_provider*`, `repo_provider`, `explore_provider`,
`weekly_releases_provider`, `track_provider`, `preview_player_provider`; `download_fallback` wiring.
Remove services: `cross_extension_share_service`, `extension_storage_service`,
`metadata_autofill_service`, `batch_metadata_re_enrich`, `local_track_redownload_service`,
`weekly_releases`, `motion_artwork_download`, `motion_artwork_proxy` (verify), `hires_check_service`.
Remove screens: `repo_tab`, `screens/repo/*`, `weekly_releases_screen`, `artist_concerts_screen`,
`concert_detail_screen`, `home_tab_explore`, `home_tab_search_results`.
Remove widgets: `explore_featured_section`, `extension_row`, `extension_repo_card`,
`cross_extension_share_sheet`, `hires_check_card`, `open_on_platform_sheet`, `metadata_candidate_tile`,
`re_enrich_*`, `download_service_picker`.
Remove settings pages: `extensions_page`, `extension_detail_page`,
`lyrics_provider_priority_page`, `metadata_provider_priority_page`, `provider_priority_page`,
`provider_priority_list_page`, `profile_settings_page`; `models/extension.dart`, `artist_concert.dart`.
Edit: `home_tab*.dart`, `album_screen`, `artist_screen`, `playlist_screen`,
`library_tracks_folder_screen`, `mornye_library_screen`, `track_metadata_edit_sheet`,
`track_metadata_lyrics`, `queue_tab*`, `main_shell.dart`, `settings_search_catalog.dart`,
`settings_tab.dart`, `settings/lyrics_settings_page`, `settings/metadata_settings_page`,
`settings/cache_management_page.dart`.

### Phase 6 — Download engine removal + player re-point  (largest Dart phase; depends on D1) — DONE (`f3ab83e`, `dfd7f43`)
Remove providers: `download_queue_provider*` (10 files), `download_queue_state`,
`download_verification_retry_guard`; and per D1, `download_history_provider*` +
`models/download_item(.g)`, `download_result`, `download_history`.
Remove services: all `download_*`, `downloaded_embedded_cover_resolver`, `native_download_history`,
`verification_notification`; remove `screens/downloaded_album_screen.dart`; download widgets
(`downloadable_cover`, `download_queue_feedback`, `preview_button`, `download_service_picker`).
Edit (re-point to local library): `music_player_provider.dart`, `playback_provider.dart`,
`now_playing_screen.dart`, `library_*_provider`, `services/music_player_runtime.dart`,
`services/playback_metadata.dart`, `main.dart` (extension init, download wiring, verification
notifications), `main_shell.dart`, `queue_tab*`, settings download pages/rows.
Android: remove `DownloadService*`, `NativeDownloadFinalizer*`, `NativeFinalizationPolicy*`,
`SafDownloadHandler.kt`, `DownloadQueueWidgetProvider.kt`, `BackgroundWorkService` download path.

### Phase 7 — Rust backend reduction  (riskiest; itself sub-phased)
Suggested sub-order (mirrors the crate graph):
1. **Prune `core` online-support modules**: `metadata::{deezer,musicbrainz,share,reenrich,catalog}`,
   `resolver`, `downloads`, `app_version`, lyrics `{config,payloads,lrclib,errors}`; remove their
   `pub mod` lines in `core/src/lib.rs` and fix internal refs (`metadata/reenrich.rs:5`).
   Verify: `cargo test -p spotiflac-core`.
2. **Re-home local `extensions::backend` pieces** (library scan + tags) into `core` or a new
   `local` module, decoupled from `ExtensionEnvironment`/`NetworkService`.
3. **Reduce `mobile` to local-only**: drop `manager.rs`, `extensions.rs`, `repository.rs`,
   online `metadata.rs`/`lyrics.rs` methods, `network_tags.rs`, `tags.rs:243` cover download;
   re-point local `impl` methods onto the re-homed local type. Keep `bindgen` + regen bindings.
4. **Delete `providers`, then `network`, then `extensions`** once unreferenced.
5. **Update build config**: `rust_backend/Cargo.toml` (members, workspace deps, patch), `Cargo.lock`,
   `scripts/build_rust_backend.sh` (drop ios), `scripts/check_rust_backend.sh`,
   `scripts/check_android_statx.sh`, `android/app/build.gradle.kts` (sourceSets/build task),
   Kotlin `SelectedCoreBackend.kt` / `NativeDataJobs.kt` / `CoreBackend.kt`, `SpotiFLACBackend.podspec`,
   android tests for extensions/downloads (remove).
Verify: `cargo test`, `scripts/build_rust_backend.sh android`, full `flutter build apk`, run app.

### Phase 8 — Dependencies, l10n, docs, final polish — IMPLEMENTED (`8609ad06`)
- `pubspec.yaml`: drop now-unused online deps (`http`, `cached_network_image`, `connectivity_plus`,
  `url_launcher`, `receive_sharing_intent`, `xml`, `html`, `archive`, `crypto`, `flutter_cache_manager`,
  `flutter_secure_storage` if unused); drop `ios: true` from `flutter_launcher_icons`; regen
  `pubspec.lock`.
- l10n: prune online-only keys from `app_en.arb` + locales.
- Docs: trim `README.md`, `CHANGELOG.md`, `CONTRIBUTING.md`, `docs/player_widgets.md`, `AGENTS.md`.
- Final: `flutter analyze`, `flutter test`, `bash scripts/check_rust_backend.sh`,
  `flutter build apk`, `graphify update .`.

---

## 5. Risk resolution and remaining verification

- Rust/core/local/FFI coupling (R1) is resolved by Phases 7-8; native tests and both Android
  Rust ABI builds pass. Device storage/audio validation is still required.
- Player/download-history coupling (R2) was resolved in Phase 6; Phase 7 removed history
  attachment/exclusion. Legacy local backup records remain readable for archive compatibility.
- Discord dependency and asset cleanup (R3/R4) is complete; local native license assets remain.
- Secure-storage coupling (R5) ended with provider credentials; the unused plugin is removed.
- The old FFmpeg tunnel is absent (R6); release Internet permission is removed and the
  packaged manifest was audited. Debug builds retain Internet for Flutter tooling.
- External CI configuration (R7) is not present in this checkout and has not been inspected.
- Validate the APK on real hardware: local playback, background controls, scans, metadata and
  lyrics, backups, SAF/removable storage, USB routing, widgets and older-Android statx handling.
- New offline copy uses English fallback where translations need updating. The APK uses the
  development signing key; configure a production key before distributing official updates.
