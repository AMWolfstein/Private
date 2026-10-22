# Upstream port list

Upstream: **`mornyeapp/Mornye`** (renamed from `spotiflacapp/SpotiFLAC-Mobile` on 2026-10-20;
same git history). This fork started from **v5.1.1** (`78699a91`, 2026-10-11). The histories
are not shared with this fork, so `git merge` is impossible; port commits by hand in batches,
with the `AGENTS.md` code → graphify → docs commits and one analyze + full `flutter test` per
batch.

- Last upstream commit checked: `9bf4c000` (2026-10-22, v5.2.5). Next check: only commits
  after it (`git log 9bf4c000..origin/main` in a Mornye clone).
- **Skip all renaming/branding** (owner 2026-10-20): `37e21b57` (app + native backend rename,
  `package:mornye`), `51d34594`, `f72fe69e`, `ae728525`, `243fee8c`, the rebrand tour
  `8e4504e7`, release/AltStore bumps. Keep this fork's `spotiflac_android` package, names and
  `com.zarz.spotiflac` paths; read upstream code through the rename (`package:mornye/` =
  `package:spotiflac_android/`).
- Do the ports before any module/folder reorganisation; moved files make every patch fail.
- Before a `FIX_PLAN.md` batch, check this list for an upstream commit that fixes the same code.

## Port order (batches; test once per batch)

Done: batch 1 (U-001, U-101, U-102, U-103; pushed `3f8bbe7`) and batch 1b:
U-103b spring `f10f45f6`, lyric performance/prerequisites `81869c48`. U-104 (`913faaa`)
and U-201 (`e8cff13`, subtitle lint fix `f34ead84`) are also covered by batch 1b validation:
analysis clean; full Flutter suite 1,629 passed / 3 skipped; Android unit suite 59 passed /
1 skipped (both exit-info tests passed). No APK. U-308 timed-vocal prerequisites are partly
done; share cards, sharing UI and on-demand lyrics work remain pending.
Batch 2: U-202 ported in `0f51f5d0` (upstream `3dc2d690`), graph `6361145f`.
Saved WIP reviewed against upstream and reused without `pubspec.yaml.rej`; the license asset
entry was added manually. WIP removed in the batch 2 docs checkpoint. Validation below.

1b. DONE — U-103b (patch-1 follow-up), including U-104/U-201 validation
2. DONE — U-201b evaluated (no applicable local changes), U-202 ported
3. DONE — U-203, U-212, U-213, U-204
4. DONE — U-205, U-216, U-206 evaluated, U-207
5. DONE — U-214, U-215, U-208 evaluated, U-209 partial
6. DONE — U-210, U-303, U-217, U-218
7. DONE — U-308 (duets + share cards), U-302 (+ `9acaa760`)
8. DONE — U-304, U-305, U-307, U-312
9. DONE — U-301 (equalizer, alone)
10-14. DONE — Mornye parity batches (`FIX_PLAN.md` Tier 2c: M1+M2, M3+M4, M5+M6, M7-M9 + HOME-007,
   M10+M11 + U-311)
15. DONE — Dependency updates from Mornye (`pubspec.*`, `rust_backend` Cargo, Gradle, toolchain pins)
16. DONE — Dead-code removal as one patch (`FIX_PLAN.md` Tier 3)

## New in Mornye (`21ee30c4..e0563ffa`)

| ID | Upstream | What | Batch |
|---|---|---|---|
| U-103b | `7600c169` (lyrics parts only: `player_lyrics.dart`, `player_lyrics_word_sweep.dart`, `utils/lyrics_timeline.dart`, their tests), `91add520` | Ported in `f10f45f6` (spring) and `81869c48` (timeline index, deferred measurement, hidden/background subscriptions and completed-word ticker limits). Kept monolithic widget; timed-vocal prerequisites from `78a5e078` included, U-308 partial below. Tested in batch 1b. | 1b |
| U-201b | `e58217c8` (local parts only: `local_library_provider*.dart`), `931b1091` (only if U-201 scan recovery needs `LibraryScanExitInfo`) | Evaluated: no applicable local production hunks. `e58217c8` only tracks/cancels NetworkLibraryScanner and frees network listings, including in the nominally local provider files. Native local ingestion/scan cancellation already exists. `931b1091` adds optional exit importance/process diagnostics; U-201 does not require them, so omitted with crash notices. | 2 DONE |
| U-212 | `9dc86e13` (drop `crates/extensions`) | Ported in `1d8e8f76`: shared aligned PIC/APIC parsing, recognized-image padding recovery and rejection/re-extraction of legacy NUL-prefixed cached JPEGs. Extension backend omitted. | 3 DONE |
| U-213 | `60d00191` | Ported in `d256e0c7`: local filesystem playback joins SAF artwork recovery; embedded art replaces missing/stale/remote references without fetching remote artwork. Existing generation guard and offline placeholders retained. | 3 DONE |
| U-214 | `d7798898` | ADAPT, ported in `10c04f7a`: Android Activity attachment wait before existing local startup channels; upstream lifecycle tests retained. No extension/crash startup imported. | 5 DONE |
| U-215 | `205e178e` | ADAPT, ported in `fa838caa`: existing inline renderer rules verified equal and extracted to a shared helper; minimal Application plus manifest registration configures audio_service before engine creation. Scoped Android 15 Xiaomi workaround and policy tests retained; no crash reporter. Vendor patch documented. | 5 DONE |
| U-216 | `9ded49f3` | Ported in `95e2b158`: identity-based same-ID snapshots notify mounted consumers while ID selectors remain stable; retained Mornye light/dark regressions and test overrides adapted. | 4 DONE |
| U-217 | `37162363` | ADAPT, ported in `8a9f6091`: upward release opens Now Playing; slow, flick, reversed and downward gesture tests adapted to Mornye light/dark. Horizontal dismissal retained. | 6 |
| U-218 | `9eea6a1a` | ADAPT, ported in `0d126507`: bounded pre-amp, Track/Album gain with fallback, both tags cached, live re-leveling and settings persistence. Mornye chip/Slider controls and regressions; no removed player mode/settings restored. | 6 |
| U-312 | `7600c169` (Mornye/library parts: `mornye_artwork_contrast`, `mornye_selection_pill`, `mornye_artist_header`, `settings_group`, `pinned_section_sliver_list`, `animated_library_sliver_grid`, `playback_session_restore`, tests) | ADAPT, ported in `6052f9ea` (pinned lists) and `c49d7af9`: bounded concurrent restoration/cache, lazy Settings search, bounded artist-logo decoding, grid-only pinch listening, static contrast readback invalidation and selection foreground caching. Upstream restoration/contrast tests adapted; existing grid/search/widget suites cover retained integration. Lyric/timeline hunks already in batch 1b; REJECT Material files/benchmarks and split-engine prerequisites. | 8 |

Skip from Mornye: branding (above), crash notices `00b7cf99`/`931b1091` (crash reports dropped,
U-306), Material-only `ba234d78`, `721a3fa7`, `5ecbb7ac`, Home listening/On Repeat `b946c373`,
`1829363d`, downloads `a3b14a28`, network `b279733a`, `19056edf` and the network parts of
`e58217c8`, iOS backup `27a45c04`.

## New in Mornye 5.2.5 (`e0563ffa..9bf4c000`, checked 2026-10-22)

About 190 commits; nearly all are desktop, Material, extension, download, NAS, online-lyrics or
branding work. Owner approved both batches and the spectrogram export (2026-10-22).

| ID | Upstream | What | Batch |
|---|---|---|---|
| U-401 | `876d4a47` | DONE `aa4232f`: Kotlin stamps `scannedAt` on the DSD/WavPack row; native staging stamps a missing scan time and skips and reports a row that cannot be encoded (`invalid_rows`, `invalid_row_error`, `invalid_row_paths`); the adapter logs it and preserves missing entries. Rust tests ported. | A |
| U-402 | `c3cb950f`, `1d87a9fc` | DONE `c99d7cb`: synced lines and word sweeps keep running while the app is inactive (shade, overlay, split screen); same-visibility lifecycle changes no longer re-sync. | A |
| U-403 | `5f4bb7cc` | DONE `c632a9f`: a late line-boundary timer catches up to the playback clock. Speed scaling omitted (no playback speed in the fork). | A |
| U-404 | `82bda289` | DONE `f3b81e3`: M4A tag writes always mux mp4 (`-strict experimental`), retry mov only on "codec not currently supported". Test seam and 326-line test not ported. | A |
| U-405 | `cc12080a` | DONE `e4cf1b7`: Samsung SM-S711B on Android 16 uses Skia; Kotlin unit test ported. | A |
| U-406 | `a3767cfc` | DONE `4d41a3b`: artwork contrast readback follows TickerMode. | A |
| U-407 | `060d71a4` | DONE `a44a568`: fast scroller rebuilds only on change for long lists; one hide timer per gesture (plus a fallback after a jump outside a gesture). | A |
| U-408 | `a428b378` | DONE `75db2cb` + test fix `56f9e6d`: directional insets/positions/alignments in shared Mornye/local widgets, mirroring back/forward glyphs, duet voices start/end, timeline and transport kept LTR. Desktop/Material/extension parts and upstream `rtl_layout_test` not ported; our mini player has no progress bar. | B |
| U-409 | `44a5cd71` | DONE `be8eb43`: `DetailPage` marks local album routes (name + artist); Go to Album skips a push when that album is on top. | B |
| U-410 | `6af4e585` | DONE `0d04313`: `LyricsCoveredBottom` reports the controls' covered height; loading and no-lyrics states centre above it and scroll. | B |
| U-411 | `2f0f0b81` | DONE `20e586e`: one Mornye lyric style merged over `DefaultTextStyle` for measured, plain and word-timed lines. | B |
| U-412 | `0afdacae` | DONE `3880772`: Save Spectrogram renders a PNG with axes and legend and opens the system save dialog; three English strings. | B |

Not ported: mini-player horizontal swipe skips tracks (`37356e43`, conflicts with the AGENTS.md
dismissal rule; owner to decide). Not applicable: `ea854078` (playlist Shuffle exists),
`78fd9ce5` (no SmoothedProgress), `cba77c1f` (query not present), `e43b8adc`/`d16efddf`
(Material transport), `45339bf4`/`199024f5`/`d7d48ba2` (track details screen removed),
`be50a4db` (no App settings page), `b532cb5d` (online lyrics picker), `c7d22b05` (desktop
assert), `2cc27c9c` (perf test not present).

## Requested by the owner

### U-001: per-field tag separators (`ac8523d7` + `9495a6bf`)

Status: ported in `5393d1d` (Tag separators page under Local Library settings; applied on Edit Metadata saves; no download/extension parts).

Upstream adds separators for artist, album artist, composer and genre (empty = keep the tag as
is). Lists split on `,`/`;` only, never on `&`, `/` or `and` (AC/DC, R&B). Upstream applies them
to downloads only; this fork has no downloads, so they apply when **local tags are saved**.

Port:
- `lib/models/metadata_separators.dart` (new, as upstream) and an
  `AppSettings.metadataSeparators` field with `explicitToJson`, `settings.g.dart` regenerated
  with build_runner, `settings_provider` setter. Settings backups must round-trip it, and old
  imports without it keep the defaults.
- Pass the separators' `writerFields` (`artist_separator`, ...) into the editor save, next to
  `artist_tag_mode` (`metadata_editor_controller.saveMetadata`, `track_metadata_edit_sheet`
  `:328`, `local_song_menu:295`).
- Rust `crates/core/src/tags/separators.rs` and the `write.rs` changes (`artist_mode_fields`,
  `flac_header`, `edit_comments`); the fork's `write.rs:54/104` already route edits through
  `artist_mode_fields`. Writers must skip `*_separator` keys.
- `audio_metadata_mapper.dart`: skip `*_separator` keys in the M4A/ID3 maps and use joined mode
  when an artist separator is set (FFmpeg path).
- Settings page from `9495a6bf`, Mornye-styled, with its search entries and l10n keys.
- Tests: upstream `metadata_separators_test`, `metadata_separator_settings_test` and the Rust
  `artist_tag_mode` test, adapted to the edit path.

Drop: `download_queue_provider`, `download_metadata_embedding`, `download_request_payload`,
`downloads.rs`, the `extensions` crate, `NativeFinalization*` Kotlin (none exist here).

Placement (owner decision, 2026-10-20): a **Tag separators** entry under **Local Library
settings**, recorded in `AGENTS.md`. Do not restore the download-era Metadata page or the Artist
Tag Mode UI (`settings_search_test` asserts both are absent).

### U-311: Immersive view looks exactly like upstream full-screen cover (`05a56133`)

ADAPT completed in batch 14: `3dfa8b73`, ownership/clock correction `822a4656`. Normal default/retained PlayerView setting and landscape layout preserved; background palette state survives rotation. No Material backdrop, motion artwork or extra cover-style setting.

Owner request (2026-10-20). Keep this fork's Player view setting (`themeProvider.playerView`,
persisted, Mornye only, Normal in landscape); take only upstream's Mornye still-cover look:
- artwork ratio `(screen.width / (screen.height * 0.56)).clamp(0.5, 1.0)` (1.0 in landscape)
  instead of the fixed 0.66-height box (`mornye_player_background.dart:92-101`,
  `mornye_player_layout.dart:147-151`), so the cover reaches the title on every screen;
- `MornyePlayerBackground.fadeStart` parameter, 0.72 in Immersive, 0.58 otherwise;
- `HeroMode` enabled only when the full-bleed artwork is shown (`!_landscape && page 0`);
- backdrop saturation 0.12 → 0.2 if U-104 has not already brought it.
No `playerCoverStyle` setting, no Material backdrop, no motion artwork. Done with PLAY-001/002
in batch 12 (same files). Compare side by side with upstream on a device after.

## Clean ports

| ID | Upstream | What |
|---|---|---|
| U-101 | `65dbce27` | AutoMix waits for advancing audio before fades. Ported in `a5bc4a8`. |
| U-102 | `08bc4226` | Cache adjacent track titles during swipes (perf; stops the neighbour title rebuilding and its marquee restarting every drag frame). Ported in `051ff44`. |
| U-103 | `afab47ae` | Cache timed lyric segment geometry (perf). Ported in `940fd79`. |
| U-104 | `6debfccb` | Keep dominant cover colours in player backgrounds (`coverSourceColor` hue-bin dominant colour; dark covers stop reading as gray). Ported in `913faaa`; batch 1b analysis/full tests pass. |

## Manual ports: fixes and perf

| ID | Upstream | What |
|---|---|---|
| U-201 | `378c8f37` | Recover interrupted scans and stale notifications (may overlap KT-202). Ported in `e8cff13`; source subtitle lint fixed in `f34ead84`; batch 1b analysis/full Flutter and Kotlin unit tests pass. KT-202 remains OPEN: interrupted-scan recovery does not reconcile standalone audio rows after adding a CUE. Verified in batch 2; no SAF scanner hunk changed. |
| U-202 | `3dc2d690` | Ported in `0f51f5d0` (ADAPT): integer libFLAC 1.5.0 decoder shared by existing exact PCM output paths; output/source precision reported separately. Fork CMake URLs and branding retained; checksum-pinned dependency and license bundled. Host regression suite and Android fixture imported. Batch 2 verification below. |
| U-203 | `080df889` | Ported in `e70ae974`: missing/empty/stale scanned covers recover via the bounded embedded-cover cache in local album headers and library grids; async album/disposal guards and valid-cover preference retained. Mornye light/dark tests, no download/Material restoration. |
| U-204 | `161a216b` | Ported in `a41d3d4e`: wait for effect progress, verify/re-align its position while the live deck stays audible, and render enough source for faster effects. Existing engine, cancellation, fallback and temp ownership retained. |
| U-205 | `f426b2d1` | Ported in `6e44c6be`: report ordinary Android output errors, keep selected song/queue and allow retry; native errors handled instead of masquerading as completion. Existing notification controls and no-EQ fork retained. |
| U-206 | `97d8ee36` | Evaluated: upstream modifies legacy material_player_layout.dart fallback only; REJECT importing Material-specific UI changes. Retained Mornye track header uses a single current PlayerMetadataTitle via PlayerTrackSwipeTitles, not an outgoing-title AnimatedSwitcher. Equivalent non-stacking behavior already present; no source port required. |
| U-207 | `186c66ae` | Ported local parts in `d0818d7a`: provider-resolved/verified SAF parents and explicit requested LRC write failures. Import native opaque/nested provider fixtures and Dart sidecar regressions; omit removed reEnrichFile online handler and extension/download tests. |
| U-208 | `47ccf9c9` | REJECT: adds thumbLength to the removed AppSlider/PlayerVolumeControl Material Expressive branch. Retained MornyeVolumeControl uses MornyePlayerSlider with an intentionally thumb-free 6px track. No compatible source hunk; no UI change. |
| U-209 | `acbc614f`, `ef5fa1cb`, `1b66bc46` | ADOPT retained pattern/formatter reuse completed: lyrics `ba751b35`/`2c4ce3ff`; audio-info `bd8f88a6`; cached queue section DateFormat and Unicode-letter pattern `6052f9ea`. Removed online/download/history hunks rejected. |
| U-210 | `d28e3f65` | ADAPT, ported in `c2f38c86`: collection-header artwork yields to viewport height and metadata is centered. Only album_detail_header adapted; unrelated removed screens excluded. |

## Optional features (owner chose all of U-301..U-305, U-307, U-308 on 2026-10-20; U-306 and U-309 not ported)

| ID | Upstream | What |
|---|---|---|
| U-301 | `ecf594aa` (+`68c739df`) | ADAPT, ported in `8e05cbbf` with `892eb173`/`c7924c53`: optional Android per-player DynamicsProcessing, lifecycle/error handling, shared deck settings and native validation; headroom/limiter choices survive presets. Mornye-only editor replaces upstream Material/Expressive presentation, using accessible faders and grouped Settings. Import bytes capped before accumulation; no Darwin backend, dependency replacement or new playback engine. UI uses faders/value labels rather than upstream custom estimated-response chart/decorations. Runtime hardware DSP verification pending. |
| U-302 | `11c6cf99`, `2455cabc`, `9acaa760` | ADAPT, ported in `df164fb1`: optional Android/local music haptics, independently owned SAF decode input/cancellation and bounded cache, sensitivity/strength, basic-motor pulses. Import scheduler/analysis/cancellation and skips/completion/AutoMix transport regressions. No iOS code, player-mode choices or replacement engine. |
| U-303 | `40f65d3a` | ADAPT in `bd8f88a6` (batch 6), completed EQ facts/error/bypass reporting in `8e05cbbf` (batch 9). Retains local analysis card; no absent online hi-res wrapper, iOS or Material integration. |
| U-304 | `08266c73`, `1d53bf93` | ADAPT, ported in `f4fb6794`: local statistics queries, Rewind stories and seasonal Library banner. Mornye grouped controls/circular header replace Expressive shapes and renderer. Follow-ups `1c589407`, `c3d79e0d` adapt existing card/motion APIs and bound the close control; no online source or schema migration. |
| U-305 | `83a55fb8` | ADAPT, ported in `6052f9ea`: section headers, Unicode initials, cached locale month formatters and precise adaptive fast scroll. Dedicated Songs stays songs-only, collection layout/paging/selection preserved. No History/default-view preference or old download lists imported. |
| U-307 | `75cd4c39` | Partial ADAPT in `2c9c0305`: responsive compact/wide/standard player-widget sizing and boundary unit test. Existing controls, theme and engine bridge retained. REJECT Expressive shape morphs, dynamic theme-role redesign and download widget/service; upstream live configuration preview not imported because coupled to the rejected renderer. |
| U-308 | `78a5e078`, `2782b1f7` | ADAPT: timed-vocal prerequisites in `81869c48`; completed local lyric-card editor, on-demand metadata/parse wait, track-change guard, long-press/menu entry points and held-word glow in `d83068e6`. Mornye circular header/rounded artwork/Cupertino actions replace Expressive shapes/buttons. Reduced motion and settled-clock bounds retained; no online loading. Follow-ups `b02895b0`, `a9433d82`, `de546bd7` correct guard lint and Mornye/virtualized-list test assumptions. |
| U-309 | `67a346c1`, `4cee16e9` | Home greeting and listening shortcuts (differs from the Apple Music Home). |

## Do not port

Online lyrics (QQ, lrc.red, BetterLyrics, Apple fallback, online lyrics search), extensions,
downloads, network/NAS, extension country settings, Material Expressive/Symbols/spring motion,
the 5.2 release tour, the `playerCoverStyle` setting and Material backdrop from `05a56133` (U-311 takes only its Mornye look), About links, crash reports on Home (`cb51d089`, `36694c6e`; owner
2026-10-20), the On Repeat shelf (`home_tab_intro.dart`; owner 2026-10-20), and `75907951` (bit-depth default badge conflicts with the
`AGENTS.md` badge policy).

## Batch 2 evidence (2026-10-20)

| Item / source | Decision | Local evidence / dependency impact | Benefit / risk / effort / verification |
|---|---|---|---|
| U-201b `e58217c8cdfe36091a6a7465424b0fb15842e453` | REJECT removed-network hunks; ALREADY IMPLEMENTED local cancellation | All production additions in `local_library_provider*.dart` refer to NetworkLibraryScanner; the other production path is network_library_scanner.dart. This fork has no network scanner. Local provider `build`/`cancelScan` already cancel native data jobs/scans; `startScan` finally clears request/completion ownership. No dependency added. | No supported local memory improvement to port or claim. No source mutation/test copied from network/history infrastructure. Low implementation complexity/risk; recommended MEDIUM review. Existing full local library regression suite retained. |
| Optional `931b10918f1a8a269cbb2bca36487d531b25b5db` | REJECT unnecessary diagnostics / excluded crash notices | LibraryScanExitInfo changes only add importance labels and process_name; current process/time matching and reason diagnostics already support U-201. They do not fix memory handling. | No required U-201 correctness benefit. No dependencies or source changes. MEDIUM review; existing exit-info tests retained. |
| U-202 `3dc2d69051ff6a61acc1fc0767cc8c6dc42e993f` | ADAPT, code `0f51f5d0` | Android C++ FlacPcmSource, JNI/map/CMake; NativeAudio, UsbPcmSource, UsbBitPerfectPlugin, HiResPlayback, UsbDirectPlayback; Android fixture/test; lib/main.dart, pubspec.yaml, flac license. WIP source matches upstream except retained fork CMake URLs/main setup and manually repaired asset registration. libFLAC is statically linked, pinned by SHA256; no pub/Cargo version change. Existing outputs/worker ownership retained; no engine migration. | Prevent vendor MediaExtractor/MediaCodec from silently truncating FLAC to 16-bit. Integer widening pads only; precision reduction rejects; source handles use existing shared ownership and worker serialization. Medium complexity, medium native/build regression risk; recommended HIGH. Host test verifies 16/24/32-bit mono/stereo precision, multiple output depths, block-boundary seeks, EOF, truncated data and retained descriptor; Android unit/native compilation and full Flutter checks required. |
| KT-202 / U-201 overlap | NOT FIXED, finding stays OPEN | MainActivitySafScan.kt still removes only existing URIs absent from currentUris; no intersection with cueReferencedAudioUris. U-201 changes recovery/notifications, not incremental CUE reconciliation. | Separate future fix from FIX_PLAN; no unrelated SAF change in this batch. |

Batch 2 verification: PASS: analysis clean; full Flutter 1,629 passed / 3 skipped / zero failures (4m02s); Android unit 59 passed / 1 skipped; native host CTest 1/1 passed; ARM64 JNI/library build passed.
No APK packaging or instrumentation installation is authorized in this port workflow.

## Batch 3 evidence (2026-10-20)

| Item / upstream source | Classification / local commit | Source and existing implementation / dependencies | Benefit, complexity, risk and effort / tests |
|---|---|---|---|
| U-203 `080df889d05f70abd390a25d2c6c89f9321a82c3` | ADAPT `e70ae974` | New `widgets/local_library_artwork_builder.dart`; existing local_album_screen, mornye_library_screen, queue_tab/filter/helpers. Existing grids trusted nonempty scan paths; existing bounded DownloadedEmbeddedCoverResolver now supplies fallback. sample_file_path already exists in DB queries, no schema/dependency change. | Missing/empty scan thumbnails no longer hide recoverable art. Keep valid scanned art, async generation/mounted guards, local-only images and current collection controls. Medium complexity/risk; MEDIUM recommended. Eleven adapted upstream widget cases cover missing/empty/file-URI covers, late validation/disposal, album headers and stale grid paths in retained Mornye light/dark. |
| U-212 `9dc86e13f5190fec410e2f603939a4d1ef2531af` | ADAPT `1d8e8f76`; REJECT extension backend hunks | Rust core tags/id3.rs and tags/write/id3.rs now share picture_frame; aligned existing separator replaces sliding UTF-16 detection. Existing image crate recognizes signatures; only redundant leading NULs before recognized images are stripped. Dart resolver checks first four preview bytes after existing source-sidecar verification. No Cargo/pub dependency or metadata format migration. | Prevent corrupt cover bytes in extraction/preservation; app-owned bad previews are re-extracted, user audio remains read-only. Low implementation complexity, medium metadata/cache risk; HIGH recommended. Two upstream Rust integration tests span PIC/APIC in MP3/WAV/AIFF, padding and UTF-16 descriptions, plus unknown-data preservation; Dart cached-preview repair case. |
| U-213 `60d00191d9ad25369ac684da0924e02e119d232b` | ADAPT `d256e0c7` | music_player_service.dart / utils/playback_artwork.dart; prior recovery ran for content:// only. All playback requests now enter the helper, which restricts extraction to absolute local paths or content://; stale HTTP artwork references trigger local extraction only. No network branch, fetcher or new dependency added. | Recover embedded art during ordinary local playback too. Valid local art avoids extraction; failures keep existing placeholder behavior. Queue/session updates retain stale-request checks. Low complexity, medium async regression risk; MEDIUM recommended. Adapted playback_artwork tests cover local/SAF missing or remote art, valid local/file URIs, provider failure and rejection of nonlocal sources; existing offline image tests retained. |
| U-204 `161a216bea552541781c30fc11fff6cd921bad74` | ADOPT production `a41d3d4e` | automix_effect_renderer.dart / music_player_automix.dart; prior resume acknowledgement could fade live audio before wet decoder advanced. Silent effect now waits for progress and checks alignment with 50ms tolerance and at most three corrections. Faster input window is overlap × max(1,speed), output duration remains bounded. No playback engine/dependency change. | Avoid early silence or doubled/misaligned effects, retain dry audio on stalled-effect fallback. Medium complexity/risk; HIGH recommended. Upstream source-window and stalled-effect regressions added; test waits up to 4s for the existing production 2s deadline rather than racing a 2s polling helper. Existing effect pause/cancel/temporary-file tests retained. |

Code/graph pairs: `e70ae974` → `b680bdd4`; `1d8e8f76` → `c5086af3`;
`d256e0c7` → `a7cc1b9f`; `a41d3d4e` → `de32a041`.
Graph validated at final code `a41d3d4e`: 23,093 unique nodes / 44,593 valid links.
No online/Material/branding/extension restoration, user-file rewrite or APK build.
Batch 3 verification: PASS: analysis clean; full Flutter 1,644 passed / 3 skipped / zero failures (3m55s); Rust fmt/Clippy clean, 231 passed / 1 ignored.

## Batch 4 evidence (2026-10-20; requested effort MEDIUM)

| Item / upstream source | Decision / code | Existing implementation and affected files | Dependency, benefit, risk/complexity and verification |
|---|---|---|---|
| U-205 `f426b2d1f0cc256d34267b511665c0e8de6d16c8` | ADAPT `6e44c6be` | MusicPlaybackDeck handles ordinary event errors; MusicPlayerHandler publishes error state, suppresses completion and serializes stop/retry; PlaybackFeedback shows foreground feedback once. Vendored audioplayers_android MediaPlayerWrapper/WrappedPlayer handle output error and rate startup. Prior platform failure could deliver completion and skip the current song. | No dependencies/EQ imported, no engine rewrite. Preserve current controls, SAF fallback, queue and USB paths. Medium complexity/risk. Tests: five native-channel failure/retry cases and Mornye light/dark feedback; existing Android compilation/unit task. Vendor patch documented in SPOTIFLAC_PATCHES.md. |
| U-216 `9ded49f31e2d8dd341bba528b7fb3dfe7060a03a` | ADAPT `95e2b158` | currentMediaItemProvider becomes StreamNotifierProvider with identity notification; MediaItem equality compares IDs only. Existing consumers can now see late duration/artwork/metadata; ID-only selectors retain their semantics. Tests/integration fixtures adapt overrideWithBuild. | No dependency change; small provider implementation/API adaptation. Medium regression risk across consumers. New provider lifecycle/selector test and two retained Mornye open-player duration tests; no Material progress widgets imported. Existing UI state and metadata-read count checked. |
| U-206 `97d8ee3695384cf3f32b89d610f761c90c601f8f` | REJECT Material-only fallback patch; equivalent production behavior ALREADY IMPLEMENTED | Upstream only changes material_player_layout.dart and its Material title test. The legacy fallback file remains, but AppThemeStyle has only mornye and production themes use MornyeTheme. MornyePlayerLayout._trackHeader → PlayerTrackSwipeTitles builds the current title directly, without outgoing-title switcher history. Neighbors are clipped horizontal swipe previews, not overlapping title transitions. | No source/dependency change or claim of an implemented port. Keep Mornye title/swipe/marquee code; full existing player/swipe tests remain the applicable regression coverage. Low review complexity/risk; do not alter legacy fallback styling for a production-inapplicable fix. |
| U-207 `186c66aeb8c07025402afe78e58a76e4578f6cfa` | ADAPT local parts `d0818d7a` | MainActivitySafIo.safParentDir/writeSafSidecarLrc become Context helpers; ask DocumentsContract.findDocumentPath for opaque IDs, validate tree/end IDs and verify fallback parent lists the child. lyrics_metadata_helper propagates requested filesystem/SAF write failures. Existing channel already reports false as error; removed reEnrichFile handler is not restored. Native fixtures and Dart tests imported. | No Rust/dependency/schema/UI-mode change. Existing user-requested writes now target verified adjacent directory; missing ancestry fails closed. AndroidX DocumentFile 1.1.0 cached bytecode confirms fromTreeUri preserves a document URI's ID. Medium complexity; user-file placement regression risk requires device/provider validation. Three Dart cases check word timestamps, unchanged audio, shorter sidecar replacement and failures. Two instrumentation cases cover opaque root/nested/legacy ancestry and no root fallback; compile separately, execution needs device. Extension/download Rust tests excluded. |

Code → graph: `6e44c6be` → `a95ffcf6`; `95e2b158` → `4c66e5e7`;
`d0818d7a` → `a85b4965`. Final graph: 23,112 unique nodes / 44,630 valid links,
built from `d0818d7a`. Existing vendored parser warnings remain.
No online, Material, EQ or conversion restoration; no APK. No Rust source changes.
Batch 4 verification: PASS: analysis clean; full Flutter 1,657 passed / 3 skipped / zero failures (4m10s); Android unit 59 passed / 1 skipped; changed plugin and instrumentation Kotlin/Java compiled (1m58s).
