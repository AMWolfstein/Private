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

Done: batch 1 (U-001, U-101, U-102, U-103; pushed `3f8bbe7`). Batch 2 so far: U-104 `913faaa`,
U-201 `e8cff13` (committed, not yet tested). Unfinished U-202 work from the old upstream is in
`git stash` ("WIP U-202 FLAC precision"); `3dc2d690` is unchanged in Mornye, so it may be
reused after review.

1b. U-103b (patch-1 follow-up)
2. U-201b, U-202 (then test with U-104, U-201)
3. U-203, U-212, U-213, U-204
4. U-205, U-216, U-206, U-207
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
| U-103b | `7600c169` (lyrics parts only: `player_lyrics.dart`, `player_lyrics_word_sweep.dart`, `utils/lyrics_timeline.dart`, their tests), `91add520` | Follow-up to U-103: lyric timeline index, deferred row measurement, pause lyrics ticking when hidden/backgrounded, spring scroll on synced line changes. If it needs `78a5e078` timed-vocal code, port those pieces here and mark them in U-308. | 1b |
| U-201b | `e58217c8` (local parts only: `local_library_provider*.dart`), `931b1091` (only if U-201 scan recovery needs `LibraryScanExitInfo`) | Release scan memory and cancel active metadata reads; skip network/SMB/WebDAV parts and crash notices. | 2 |
| U-212 | `9dc86e13` (drop `crates/extensions`) | Read padded ID3 covers (Rust core `tags/id3.rs`, `write/id3.rs`) and repair cached previews. | 3 |
| U-213 | `60d00191` | Prefer embedded art for local files (`utils/playback_artwork.dart`). | 3 |
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
| U-104 | `6debfccb` | Keep dominant cover colours in player backgrounds (`coverSourceColor` hue-bin dominant colour; dark covers stop reading as gray). |

## Manual ports: fixes and perf

| ID | Upstream | What |
|---|---|---|
| U-201 | `378c8f37` | Recover interrupted scans and stale notifications (may overlap KT-202). |
| U-202 | `3dc2d690` | Keep FLAC precision in bit-perfect playback. |
| U-203 | `080df889` | Recover missing local album artwork from audio. |
| U-204 | `161a216b` | AutoMix effect handoffs and source-audio rendering. |
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
| U-308 | `78a5e078`, `2782b1f7` | Lyric share cards, on-demand lyrics loading. The timed-vocal part of `78a5e078` is worth taking on its own: scroll holds an unfinished lead line during duets/overlaps (`_focusFor`, `lyricsWithDisplayEnds`), Enhanced LRC last-word end estimate, backing-vocal drop-in. The share screen needs a Mornye restyle. |
| U-309 | `67a346c1`, `4cee16e9` | Home greeting and listening shortcuts (differs from the Apple Music Home). |

## Do not port

Online lyrics (QQ, lrc.red, BetterLyrics, Apple fallback, online lyrics search), extensions,
downloads, network/NAS, extension country settings, Material Expressive/Symbols/spring motion,
the 5.2 release tour, the `playerCoverStyle` setting and Material backdrop from `05a56133` (U-311 takes only its Mornye look), About links, crash reports on Home (`cb51d089`, `36694c6e`; owner
2026-10-20), the On Repeat shelf (`home_tab_intro.dart`; owner 2026-10-20), and `75907951` (bit-depth default badge conflicts with the
`AGENTS.md` badge policy).
