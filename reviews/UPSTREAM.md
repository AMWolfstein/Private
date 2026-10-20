# Upstream port list

Upstream: **`mornyeapp/Mornye`** (renamed from `spotiflacapp/SpotiFLAC-Mobile` on 2026-10-20;
same git history). This fork started from **v5.1.1** (`78699a91`, 2026-10-11). The histories
are not shared with this fork, so `git merge` is impossible; port commits by hand in batches,
with the `AGENTS.md` code → graphify → docs commits and one analyze + full `flutter test` per
batch.

- Last upstream commit checked: `e0563ffa` (2026-10-20, v5.2.1). Next check: only commits
  after it (`git log e0563ffa..origin/main` in a Mornye clone).
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
4. NEXT — U-205, U-216, U-206, U-207
5. U-214, U-215, U-208, U-209
6. U-210, U-303, U-217, U-218
7. U-308 (duets + share cards), U-302 (+ `9acaa760`)
8. U-304, U-305, U-307, U-312
9. U-301 (equalizer, alone)
10-14. Mornye parity batches (`FIX_PLAN.md` Tier 2c: M1+M2, M3+M4, M5+M6, M7-M9 + HOME-007,
   M10+M11 + U-311)
15. Dependency updates from Mornye (`pubspec.*`, `rust_backend` Cargo, Gradle, toolchain pins)
16. Dead-code removal as one patch (`FIX_PLAN.md` Tier 3)

## New in Mornye (`21ee30c4..e0563ffa`)

| ID | Upstream | What | Batch |
|---|---|---|---|
| U-103b | `7600c169` (lyrics parts only: `player_lyrics.dart`, `player_lyrics_word_sweep.dart`, `utils/lyrics_timeline.dart`, their tests), `91add520` | Ported in `f10f45f6` (spring) and `81869c48` (timeline index, deferred measurement, hidden/background subscriptions and completed-word ticker limits). Kept monolithic widget; timed-vocal prerequisites from `78a5e078` included, U-308 partial below. Tested in batch 1b. | 1b |
| U-201b | `e58217c8` (local parts only: `local_library_provider*.dart`), `931b1091` (only if U-201 scan recovery needs `LibraryScanExitInfo`) | Evaluated: no applicable local production hunks. `e58217c8` only tracks/cancels NetworkLibraryScanner and frees network listings, including in the nominally local provider files. Native local ingestion/scan cancellation already exists. `931b1091` adds optional exit importance/process diagnostics; U-201 does not require them, so omitted with crash notices. | 2 DONE |
| U-212 | `9dc86e13` (drop `crates/extensions`) | Ported in `1d8e8f76`: shared aligned PIC/APIC parsing, recognized-image padding recovery and rejection/re-extraction of legacy NUL-prefixed cached JPEGs. Extension backend omitted. | 3 DONE |
| U-213 | `60d00191` | Ported in `d256e0c7`: local filesystem playback joins SAF artwork recovery; embedded art replaces missing/stale/remote references without fetching remote artwork. Existing generation guard and offline placeholders retained. | 3 DONE |
| U-214 | `d7798898` | Wait for the Activity before backend startup calls (`services/activity_attachment.dart`). | 5 |
| U-215 | `205e178e` | Apply renderer (Impeller) compatibility before shared engine creation, incl. the `third_party/audio_service` patch note. | 5 |
| U-216 | `9ded49f3` | Refresh late duration updates without reopening the player. | 4 |
| U-217 | `37162363` | Swipe up on the mini player opens Now Playing; mini-player dismissal must keep working (UI-101). | 6 |
| U-218 | `9eea6a1a` | Normalization pre-amp and track/album gain mode (ReplayGain stays). | 6 |
| U-312 | `7600c169` (Mornye/library parts: `mornye_artwork_contrast`, `mornye_selection_pill`, `mornye_artist_header`, `settings_group`, `pinned_section_sliver_list`, `animated_library_sliver_grid`, `playback_session_restore`, tests) | Mornye player/library smoothness. Skip Material files. `pinned_section_sliver_list` may belong with U-305. | 8 |

Skip from Mornye: branding (above), crash notices `00b7cf99`/`931b1091` (crash reports dropped,
U-306), Material-only `ba234d78`, `721a3fa7`, `5ecbb7ac`, Home listening/On Repeat `b946c373`,
`1829363d`, downloads `a3b14a28`, network `b279733a`, `19056edf` and the network parts of
`e58217c8`, iOS backup `27a45c04`.

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
| U-205 | `f426b2d1` | Report Android output failures without skipping tracks. |
| U-206 | `97d8ee36` | No overlapping titles during rapid skips. |
| U-207 | `186c66ae` | Refresh LRC sidecars in their actual SAF folder. |
| U-208 | `47ccf9c9` | Volume slider handle size. |
| U-209 | `acbc614f`, `ef5fa1cb`, `1b66bc46` | DateFormat/RegExp reuse, fewer history notifications. |
| U-210 | `d28e3f65` | Album header artwork fit (only the `album_detail_header` part). |

## Optional features (owner chose all of U-301..U-305, U-307, U-308 on 2026-10-20; U-306 and U-309 not ported)

| ID | Upstream | What |
|---|---|---|
| U-301 | `ecf594aa` (+`68c739df`) | Multiband EQ / native audio processing (~4.5k lines; adds DSP, does not replace the engine). |
| U-302 | `11c6cf99`, `2455cabc`, `9acaa760` | Music-synced haptics, incl. basic-motor pulses and tuning sliders. |
| U-303 | `40f65d3a` | Audio source/processing/output details; the quality badge becomes tappable and opens `audio_info_sheet.dart` (not in this fork). |
| U-304 | `08266c73`, `1d53bf93` | Rewind and listening-statistics highlights. |
| U-305 | `83a55fb8` | Sectioned library browsing and fast scroll. |
| U-307 | `75cd4c39` | Refreshed launcher widgets. |
| U-308 | `78a5e078`, `2782b1f7` | Lyric share cards, on-demand lyrics loading. The timed-vocal part of `78a5e078` is worth taking on its own: scroll holds an unfinished lead line during duets/overlaps (`_focusFor`, `lyricsWithDisplayEnds`), Enhanced LRC last-word end estimate, backing-vocal drop-in. **Partial in `81869c48`:** `_focusFor`, `lyricsWithDisplayEnds` and `LyricBackingTransition` plus overlap fixtures, needed by U-103b. Share cards/entry points, on-demand loading and glow styling remain pending; no online fetch imported. The share screen still needs a Mornye restyle. |
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
