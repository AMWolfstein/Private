# Port plan for Codex

Planned 2026-10-20 by Claude Code; implementation is done by Codex. Specs per item are in
`reviews/UPSTREAM.md` (U-IDs) and `reviews/FINDINGS.md` (MORN/HOME/PLAY/DEAD IDs). Obey
`AGENTS.md` throughout.

## Setup (once)

```sh
git clone --filter=blob:none https://github.com/mornyeapp/Mornye.git ../mornye-upstream
git -C ../mornye-upstream log -1 --oneline   # expect e0563ffa or newer
```

The clone is read-only reference data: never build it or run its scripts. Read commits with
`git -C ../mornye-upstream show <sha>` and `show <sha>:<path>`. Mornye is SpotiFLAC-Mobile
renamed (same history), so every SHA in `UPSTREAM.md` exists there. Histories are not shared
with this repo: port by hand. Use `git apply` only when
`git -C ../mornye-upstream format-patch -1 --stdout <sha> | git apply --check` passes.

## Rules for every port

- **No renaming or branding.** Mornye renamed `package:spotiflac_android` to `package:mornye`,
  the app to Mornye and the native backend crates. Read `package:mornye/` as
  `package:spotiflac_android/`; keep this repo's names, ids, `com.zarz.spotiflac` paths,
  strings and assets. Skip the commits listed under "Skip all renaming/branding".
- Port only what fits `AGENTS.md`: drop download, extension, provider, network/NAS/SMB/WebDAV,
  online lyrics, remote artwork, iOS, Discord, crash-notice and Material-only parts. The lyric
  spring scroll (`91add520`) is wanted; Material Expressive spring motion is not.
- New UI is Mornye-styled: existing Mornye widgets (`HeaderCircleButton`, `SettingsGroup`,
  `SettingsItem`, `MornyeSettingsTheme`, `showAppBottomSheet`), Cupertino icons, light/dark.
- Never replace the audio engine; DSP sits on the existing player.
- When a commit depends on an earlier upstream refactor, port the minimum pieces, not the
  refactor.
- Before editing, use graphify for links and blast radius: `graphify query "<question>"`,
  `graphify explain "<Symbol>"`, `graphify path "<A>" "<B>"`.
- l10n: add new keys to `lib/l10n/arb/app_en.arb` (other locales fall back to English).
- Code generation is allowed when needed (`dart run build_runner build
  --delete-conflicting-outputs`, `flutter gen-l10n`, uniffi bindings through the repo scripts).
- Do not build APKs.

## Commits

Per port (one upstream commit or one logical piece):
1. Code commit, explicit paths only (never `git add -A`; no `graphify-out/`, no
   `LOCAL_OFFLINE_MIGRATION_PLAN.md`): `feat(port)|fix(port)|perf(port): <what> (upstream <sha>)`.
2. `graphify update .`, then commit only tracked `graphify-out/` files:
   `chore(graphify): refresh code graph after <ID>`.

No tests between ports. Testing happens once at the end of each batch.

## End of every batch

1. `flutter analyze`: `No issues found!`
2. Full `flutter test`. Accepted failures only: the known-flaky
   `test/library_browse_sqlite_paging_test.dart` and the `file_stat_boundary_test`
   permission case when running as root. Port upstream tests that cover ported behaviour.
3. Rust changed: `bash scripts/check_rust_backend.sh` (fmt, clippy `-D warnings`, tests).
4. Kotlin changed: run Kotlin unit tests only if a Gradle unit-test task works without
   building an APK; otherwise note it.
5. Fix failures in `fix(port)` commits, each followed by a graphify commit.
6. Docs commit `docs: record upstream port batch <n>`: mark each ID in `UPSTREAM.md`
   (`ported in <sha>` / `partial: <why>`) or `FINDINGS.md` (move to Resolved with the SHA), add
   a `## Progress` entry in `LOCAL_OFFLINE_MIGRATION_PLAN.md`, and one `AGENTS.md` line only for
   a lasting product rule.
7. `git push -u origin ccr-2fb644cd-nmesyt`, then fetch and confirm HEAD equals the remote.

## State at hand-over

- Initial hand-over: batch 1 (U-001 `5393d1d`, U-101 `a5bc4a8`, U-102 `051ff44`, U-103
  `940fd79`; tested). Batch 2 part: U-104 `913faaa`, U-201 `e8cff13`, now tested by batch 1b (see completed checkpoint below).
- Historical U-202 WIP was reviewed/reused in batch 2 and removed in `3e4be675`; no pending
  patch remains. The rejected `.rej` was never applied.
- Dependencies were compared with Mornye `e0563ffa`: every shared pub package, Cargo crate,
  the Flutter pin (`.fvmrc` 3.47.7), NDK `30.0.16248370` and Gradle plugin versions are
  identical. Mornye's extra dependencies are online/iOS/Discord only (`cached_network_image`,
  `connectivity_plus`, `dart_smb2`, `flutter_secure_storage`, `http`, `url_launcher`,
  `video_player`, `receive_sharing_intent`, `material_symbols_icons`, `dynamic_color`,
  tokio/hyper/rustls/rquickjs crates): do not add them.

## Completed batch 1b (2026-10-20)

- `f10f45f6`: U-103b spring scroll (`91add520`), fast scrubbing and reduced-motion behavior retained.
- `81869c48`: U-103b lyric-only performance (`7600c169`): indexed active voices, deferred/bounded row measurement and prefix geometry, lifecycle/TickerMode subscription suspension, completed-word clock settling. The current single-file widget is retained. U-308 prerequisites from `78a5e078` (overlap focus, display ends and backing drop-in) included; sharing/glow/provider/Material-only code omitted.
- U-104 `913faaa` and U-201 `e8cff13` validated; `f34ead84` fixes the U-201 nullable-element lint. Graph checkpoints `dd04bf17`, `1bc2b9e3`, `ec2f8bf3` (no topology change) and `11456f4f` (extraction hash).
- Generated ignored l10n files refreshed after the branch switch. Final `flutter analyze`: No issues found; full `flutter test`: **1,629 passed, 3 skipped, no failures**. Android `:app:testDebugUnitTest --offline`: **59 passed, 1 skipped**, including 2/2 LibraryScanExitInfo tests. The skipped class is NativeDataJobsTest. No APK packaging task ran. Rust check script not required/run (no Rust source changed in this batch); Gradle rebuilt native dependencies for unit checks.
- Graph JSON validated: 23,003 unique nodes and 44,612 valid links. Existing vendored C/preprocessor extraction warnings remain; no new application extraction errors. Tests ran at batch end; no tests between the two ports. Source/graph/docs commits remain separate.
- Historical next step was batch 2 (U-201b/U-202), now recorded below. No APK.

## Completed batch 2 (2026-10-20)

- U-201b evaluated against complete `e58217c8`: its changes in nominally local provider files
  own/cancel only NetworkLibraryScanner; this fork removed that subsystem. Existing native
  local scanner/ingestion cancellation and finally cleanup are already present. No applicable
  local hunk; no network code restored and no local memory gain claimed.
- `931b1091` LibraryScanExitInfo adds optional process-importance diagnostics, which existing
  U-201 recovery does not need. Crash-notice changes stay excluded; no port required.
- U-201 does **not** fix KT-202 (incremental CUE duplicate standalone row); finding stays OPEN.
- U-202 `0f51f5d0` ports `3dc2d690`: native integer libFLAC with existing output ownership,
  source/output depth separation, precision/seek/truncation tests and license. WIP reviewed
  against upstream; rejected `.rej` omitted and pubspec asset registered manually. Fork build
  URLs/identity retained. Graph `6361145f`: 23,056 nodes / 44,447 valid links.
- Verification: PASS: analysis clean; full Flutter 1,629 passed / 3 skipped / zero failures (4m02s); Android unit 59 passed / 1 skipped; native host CTest 1/1 passed; ARM64 JNI/library build passed. No APK. Rust source unchanged; Rust check script not required.
- Historical next step was batch 3, now completed below.

## Completed batch 3 (2026-10-20)

- U-203 `e70ae974` adapts `080df889`: recover missing scan artwork in local album headers
  and grids through the existing embedded-cover cache, retain current controls/local images.
- U-212 `1d8e8f76` adapts `9dc86e13` without crates/extensions: aligned ID3 picture parsing,
  signature-checked NUL padding recovery and re-extraction of bad app-owned JPEG previews.
- U-213 `d256e0c7` adapts `60d00191`: embedded art recovery covers local paths as well as SAF;
  legacy remote art references cause local extraction only; offline image policy unchanged.
- U-204 `a41d3d4e` adopts `161a216b` source: align advancing effect deck before handoff;
  faster effects render sufficient source. Existing engine and dry-audio fallback retained.
- Per-port graph checkpoints: `b680bdd4`, `c5086af3`, `a7cc1b9f`, `de32a041`.
  Final graph validated: 23,093 unique nodes / 44,593 valid links.
- Batch 3 verification: PASS: analysis clean; full Flutter 1,644 passed / 3 skipped / zero failures (3m55s); Rust fmt/Clippy clean, 231 passed / 1 ignored. No Kotlin changes, no APK; physical audio/SAF tests not run.
- Historical next step was batch 4, now recorded below.

## Completed batch 4 (2026-10-20; user-requested MEDIUM)

- U-205 `6e44c6be` adapts `f426b2d1`: output errors keep the current song selected,
  report failure and allow retry. Retains SAF fallback, current notification controls,
  vendored descriptor patch and existing engine. No equalizer imports.
- U-216 `95e2b158` adapts `9ded49f3`: identity-based same-ID media snapshots reach mounted
  consumers; tests use notifier build overrides, including Mornye late-duration regressions.
- U-206 `97d8ee36`: legacy Material fallback remains, but production is Mornye-only.
  Do not import the Material-specific patch.
  The retained Mornye single-current-title/swipe path already has no outgoing-title stack.
- U-207 `d0818d7a` adapts local `186c66ae` parts: validated SAF ancestry and requested local
  sidecar error propagation; no reEnrichFile online handler or extension tests restored.
  Native provider fixtures and three Dart sidecar regressions imported.
- Graph pairs: `a95ffcf6`, `4c66e5e7`, `a85b4965`; final code `d0818d7a`, validated
  23,112 unique nodes / 44,630 valid links. Vendor patch note updated with U-205 source.
- Batch 4 verification: PASS: analysis clean; full Flutter 1,657 passed / 3 skipped / zero failures (4m10s); Android unit 59 passed / 1 skipped; changed plugin and instrumentation Kotlin/Java compiled (1m58s). No Rust source change; no APK or device test execution.
- Historical next unit was batch 5, now recorded below.

## Completed batch 5 (2026-10-20; continued MEDIUM preference)

- U-214 `10c04f7a` adapts `d7798898`: wait for Android Activity attachment before
  existing local startup channels, with upstream lifecycle tests.
- U-215 `fa838caa` adapts `205e178e`: existing renderer policy extracted unchanged
  (verified against upstream), shared by the fragment and a minimal Application.
  Manifest registers that Application; audio_service copies arguments before cached
  engine creation and rejects late configuration. Scoped Android 15 Xiaomi workaround
  and its two unit tests retained. No crash-reporting startup imported.
- U-208 `47ccf9c9`: REJECT Material-only thumb sizing. Mornye uses its existing
  intentionally thumb-free player slider; removed AppSlider is not restored.
- U-209 `ba751b35` adopts retained `acbc614f` lyric alignment regex reuse;
  `2c4ce3ff` adopts `ef5fa1cb` native local lyric credit regex reuse. Identical patterns,
  existing pronunciation tests and shared native/Dart credit goldens cover behavior.
  REJECT removed online album/metadata, download/extension and history-notifier hunks.
  DEFER number-pattern hunk to U-303 (batch 6) and queue-section locale DateFormat/letter
  patterns to U-305 (batch 8); those modules do not exist locally yet.
- Source → graph pairs: `10c04f7a` → `3a5cca2a`, `fa838caa` → `a88e3696`,
  `ba751b35` → `ffbafbe1`, `2c4ce3ff` → `11d8f750`.
  Final graph: 23,147 unique nodes / 44,693 valid links. Existing vendor warnings only.
- Verification: PASS: analysis clean; full Flutter 1,659 passed / 3 skipped / zero failures (4m02s); Rust fmt/Clippy clean, 231 passed / 1 ignored; Android unit 61 passed / 1 skipped (1m06s).
- No dependencies/schema changes, branding, removed features, replacement player or APK.
  Physical startup/renderer behavior NOT RUN; no runtime speedup measured. KT-202 remains OPEN.
- Next exact unit: **batch 6 only** (U-210, U-303, U-217, U-218), when requested.
  Include U-209 deferred audio_info_sheet number pattern when U-303 introduces that file.

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

## Batches

| # | Items | Notes |
|---|---|---|
| 1b DONE | U-103b | `7600c169` lyrics parts only (`player_lyrics.dart`, `player_lyrics_word_sweep.dart`, `utils/lyrics_timeline.dart`, `lyrics_timeline_test`, `player_lyrics_repaint_test`, lyrics bits of `now_playing_lyrics_transition_test`) + `91add520`. Upstream split `player_lyrics.dart` in `77c8639d`; port behaviour, not the split. If it needs `78a5e078` timed-vocal code (`_focusFor`, `lyricsWithDisplayEnds`, `LyricBackingTransition`), port those pieces here and mark U-308 partly done. Also fix any failures from U-104/U-201. |
| 2 DONE | U-201b, U-202 | U-201b: local parts of `e58217c8` (`local_library_provider*.dart`), plus `931b1091` `LibraryScanExitInfo` only if U-201 needs it. U-202 ported from reviewed WIP; WIP removed. KT-202 remains open. |
| 3 DONE | U-203, U-212, U-213, U-204 | U-212 `9dc86e13` without `crates/extensions`. |
| 4 DONE | U-205, U-216, U-206, U-207 | U-206 legacy Material fallback patch rejected; production Mornye title behavior already equivalent. |
| 5 DONE | U-214, U-215, U-208, U-209 | U-215 touches `third_party/audio_service`; record the patch in its patches note. U-209: skip download/iOS hunks. |
| 6 DONE | U-210, U-303, U-217, U-218 | U-210: only the `album_detail_header` part of `d28e3f65`. U-303 brings `audio_info_sheet.dart` (not in this repo). U-217: mini-player dismissal must keep working (UI-101). |
| 7 DONE | U-308, U-302 | U-308: timed-vocal parts (if not done in 1b) and the lyric share screen restyled for Mornye. U-302: `11c6cf99`, `2455cabc`, `9acaa760`. |
| 8 DONE | U-304, U-305, U-307, U-312 | U-312: Mornye/library parts of `7600c169` (skip Material files); `pinned_section_sliver_list` goes with U-305. |
| 9 DONE | U-301 | Equalizer, alone: `ecf594aa` + `68c739df`, Kotlin/native DSP on the existing player. |
| 10 DONE | MORN-001..005, MORN-017 | `FIX_PLAN.md` M1+M2. |
| 11 DONE | MORN-006..012 | M3+M4. |
| 12 DONE | MORN-013..016 | M5+M6; MORN-013 uses the tonal style (owner decision). |
| 13 DONE | HOME-001..008 | M7-M9 + HOME-007 cleanup. |
| 14 DONE | PLAY-001..004, U-311 | M10+M11 + the upstream full-screen look for the Immersive view (`UPSTREAM.md` U-311). |
| 15 | Dependencies | Re-run the comparison above against the then-current Mornye `main` and against anything the ports added. Apply version bumps only for packages/crates this repo uses. Expected: no change. |
| 16 | Dead code, one patch | `FIX_PLAN.md` Tier 3 (rows 22-27, 25a-d) and HOME-007 leftovers if still present. First re-run the dead-code checks with graphify and grep, because ports may now use code that was dead (e.g. widgets, l10n keys). Keep `NativeReplayGainPolicy` (owner decision) and `MANAGE_EXTERNAL_STORAGE`. Follow the `AGENTS.md` feature-removal workflow; delete the l10n keys last and re-scan. |

Batches 10-14 come after the ports because the ports touch the same screens.

## Owner decisions that apply

- Tag separators under Local Library settings (done).
- Optional ports chosen: U-301, U-302, U-303, U-304, U-305, U-307, U-308 (duets and share
  cards). Not ported: U-306 crash reports on Home, U-309 Home greeting, the On Repeat shelf.
- MORN-013 tonal style. U-311: Immersive keeps this repo's Player view setting and takes only
  upstream's Mornye full-screen look.
- About credits/links and the Search Recent list stay removed; keep `MANAGE_EXTERNAL_STORAGE`
  and `NativeReplayGainPolicy`.
