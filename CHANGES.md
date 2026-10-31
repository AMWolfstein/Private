# Sistrum: complete record of changes

This file brings together, in one place, everything changed in this repository on top of the original project at
version 5.1.1. It is a summary. The detailed evidence for each entry stays in the files listed at the end.

- Starting point: the original project 5.1.1 (upstream `5a895265`), an online, extension-driven music downloader
  for Android and iOS.
- End point: branch `desloppify/code-health`, commit `7cacbc4` (2026-10-31). The app is Sistrum, a local, offline,
  Android-only music player, version 1.0.0+1.
- Period: 2026-10-16 to 2026-10-31.
- The clone is shallow: git history here starts on 2026-10-29. Earlier commit IDs come from
  `LOCAL_OFFLINE_MIGRATION_PLAN.md` and cannot be checked in this clone.
- Test counts are the results recorded at each step. Nothing listed here was tested on an Android device unless it
  says so.

## 1. Summary

| | Before (5.1.1) | Now |
|---|---|---|
| Purpose | Download music from online providers through extensions | Play the music files already on the device |
| Platforms | Android and iOS | Android only |
| Network use | Providers, extensions, SMB/WebDAV, Discord, updater, remote config | Only the GitHub release updater |
| Rust workspace | `core`, `network`, `providers`, `extensions`, `mobile`, `bindgen` | `core`, `local`, `mobile`, `bindgen` |
| Look | Several themes and a theme picker | Sistrum theme only, light and dark, liquid glass |
| Name and ID | Original name and package | Sistrum, `com.amwolfstein.sistrum` (side-by-side build: Sistrum Local, `.local`) |
| Flutter tests | not recorded here | 2,281 passed (2026-10-31), `flutter analyze` clean |
| Rust tests | not recorded here | core 7 and mobile 91 passing; clippy clean with `-D warnings` |

## 2. Owner decisions that shaped the work

- **D1:** the player reads the local library database. Download history is deleted.
- **D2:** Home stays, rebuilt from local data.
- **V1:** Sistrum is the only theme. Light and dark modes, accents, glass and fonts stay.
- **V2:** the Home feed keeps its editorial card and shelf layout, filled from local data.
- **V3:** the original artist, album and playlist designs are restored over local data. Artist links open
  `local_artist_screen.dart`.
- **V4:** every online setting is removed.
- **PD1 to PD7** (`PHASE6_DECISIONS.md`): choices made during the download-engine removal, with their later
  corrections.
- **Engine plan** (`docs/AUDIO_ENGINE_MIGRATION.md`): D1–D6 decided (GPL-3.0, minSdk 31, drop Direct USB, drop
  AAudio, CUE plays through Media3, playback moves to Kotlin). D7 (formats with no decoder) is a recommendation, not
  decided. **None of this plan is implemented yet.**

## 3. Online features removed (phases 1–8)

| Phase | Commit | Removed |
|---|---|---|
| 1 | `159a9c2` | `ios/`, `third_party/discord/`, online release tooling, docs and scripts |
| 2 | `91240e2` | Discord rich presence (Dart, settings, translations, Gradle, manifest, scripts) |
| 3 | `757ebcc` | Updater, remote config, announcements, donations (the updater came back later, see section 5) |
| 4 | Phase 4 commit | Network storage: SMB, WebDAV and NAS, the `network://` scheme, `dart_smb2` |
| 5 | `05bf2fe`, `0567a80`, `83a02c4` | Extension store, repository tab, provider priorities, online metadata autofill and re-enrich, re-download, cross-extension share, hi-res check, previews, Explore feed, weekly releases, artist concerts, motion artwork |
| 6 | `f3ab83e`, `dfd7f43` | The download engine, the extension registry and track provider. Player and queue re-pointed to the local library |
| 7 | `a9f63b9`, `fa2afff` | Rust crates `providers`, `network` and `extensions` (126 lockfile packages). New `sistrum-local` crate for scans, CUE, tags, artwork and lyrics. `ExtensionManager` replaced by `LocalBackend`. iOS and Swift build wiring removed |
| 8 | `8609ad06` | Online Dart dependencies (`http`, `connectivity_plus`, `cached_network_image`, `flutter_cache_manager`, `flutter_secure_storage`, `receive_sharing_intent`, `video_player`, `dynamic_color` and others), online translations, release Internet permission |

Phase 7 validation: 1,645 Flutter tests passed with 3 skipped, Rust 215 passed, Kotlin unit tests 63 passed, and
Android ARM64 and ARMv7 Rust builds passed.

## 4. Features removed later

- **Format conversion** (`19a28b3`): single and batch Convert, quality sheets, encoders, converted-file publishing.
- **Wishlist** (`d44a273`): Library, menus, models, backups. Collections schema v3 drops its table.
- **Separate track details page** (`26f8e71`): song taps play; its actions moved to the song menu.
- **Settings pages:** Files & Folders output folder, download-era Metadata, App settings, Embed lyrics, Default
  view, Audio quality label, History View, Artist Tag Mode, the "Always use blur effects" switch, the local-library
  on/off switch.
- **Home Recent access section**, and search inside Library pages (search lives in the bottom tab).
- **Legacy code** (2026-10-28): download-history database and model, history and extension payloads in backups
  (backups are now `.sbk`, format v3 only), old-install preference migrations, the library v20 and collections v4
  schema upgraders, single-folder library settings, iOS code paths, and two dead-code passes over Dart, Kotlin and
  Rust.

## 5. Features added or changed

**Identity and builds**
- Renamed to Sistrum, `com.amwolfstein.sistrum`, across Android source sets, JNI, channels, manifests and copy
  (T15). Persisted keys and backups keep working through encoded legacy identifiers (T16).
- Version reset to 1.0.0+1.
- `SISTRUM_SIDE_BY_SIDE=true` builds Sistrum Local, which installs next to the main app.
- New launcher icon on a cream background.

**Home and Library**
- Local Home feed: editorial cards for the latest releases by release-date tag, Recently Added, Albums, Playlists,
  Artists. Bounded queries, local artwork.
- Library overview rows: Songs, Genres, Loved Songs, Favorite Artists, Playlists, Artists and a new Album Artists
  list.
- Genres from local tags with exact matching.
- Tag separators (Artists, Genre, Keep together) under Local Library settings. A derived
  `library_tag_credits` table keeps artist and genre pages, search and shelves consistent.
- Appears On section on artist pages. Go to Artist and Go to Composer with a picker for split credits.
- Sorting by file size.

**Detail pages**
- Artist page: portrait header, centered Play, featured release, Popular (20 songs ranked by play count, 5 per page,
  at most 4 dots), discography shelves that page automatically, Singles only from an explicit total-track count of 1.
- Album, playlist and Loved headers: one centered row of Loved, Play, Shuffle and Add to playlist.
- Song menus: Play or Share, Play next, Add to queue, Go to album or artist, Copy file path, Edit Metadata,
  ReplayGain, Audio Quality Analysis, confirmed delete. CUE rows also have Split into Tracks.

**Player**
- Normal and Immersive player views, saved across restarts.
- Ken Burns drift on album headers and the player cover, with an Appearance switch and automatic pauses.
- Optional lyric line above the seek bar. Lyrics follow the direction of each line.
- Heart for favorites, a quality badge, normalization pre-amp and track/album gain.
- An optional equalizer: 5, 10, 15 or 31 bands, preamp, balance, limiter and compressor, presets, JSON import and
  share.
- AutoMix: lands on the beat and falls back to a plain crossfade.
- Playback errors keep the song selected so it can be retried.

**Look and feel**
- Liquid glass: quality setting (auto, lite, full, off) and clarity levels 1–5, glass thumbs only while touched,
  floating headers, one shared backdrop read for persistent chrome, a pre-blurred ground image over artwork, and a
  hidden performance HUD.
- Cover colours come from one analysis per cover, stored in the library database.
- Accessibility: 48dp touch targets, labels, named sliders, live selection counts, large text.

**Other**
- First-run setup and the local guide form one flow, with permission checks and no output-folder step.
- Insights (listening statistics) tab, always recording, with Rewind highlights.
- Languages: English only on 2026-10-23, then the 19 translations restored on 2026-10-27.
- Updater restored on 2026-10-28: Settings > Updates, GitHub releases, resumable HTTPS download with a SHA-256
  check, install through the system installer.

## 6. Upstream ports

- Upstream 5.1.1 to 5.2.6 (`5a895265..c90ec647`): all 533 commits checked one by one in
  `reviews/upstream-v5.1.1-v5.2.6-ledger.md`. Verdicts: 12 ported in the final pass, 144 handled earlier (ported,
  already present, or declined with a reason, as recorded in `reviews/UPSTREAM.md`), 339 not applicable, 38
  translations.
- Port batches 1–17C (2026-10-20 to 2026-10-27) and the 5.2.5 ports (U-401..U-412). Highlights: exact FLAC
  output with libFLAC 1.5.0, tag separators, lyric spring scrolling, Rewind, equalizer, media controls that follow
  late metadata, AutoMix beat landing, scans that index untagged MP3/MP4, raw AAC and ID3-prefixed FLAC.

## 7. Audits and safety fixes (T1–T14)

| Audit | Main fixes |
|---|---|
| T1 SAF scanning | A provider error is no longer read as an empty folder; an empty listing cannot wipe indexed rows |
| T2 CUE delete and split | Deleting a CUE row removes only the database row, never the backing audio |
| T3 Tag writing | Only edited fields are written; failed writes keep the original; SAF replacement verifies backup and rollback |
| T4 CUE and library identity | Stricter CUE parsing; incremental scans re-read backing metadata; cover cache safety |
| T5 Backup and startup | Crafted backups cannot write outside the private cover folder; covers commit with their rows |
| T6 Lyrics parsing | Untimed TTML shows plain lyrics instead of raw XML |
| T7 Playback | Seeks after a restored session and previous-track restarts are no longer lost |
| T8 Library correctness | Keyed album queries, Singles from explicit totals, NFC search schema 18, safer deletion |
| T9 Query cost | Schema 19 index for album artists, per-connection genre cache |
| T10 Scan and cover cost | Shared thumbnail names, cache expiry, fewer whole-file copies |
| T11 Visible UI defects | Partial album deletes, safe metadata saves, stale debounces, damaged spectrograms |
| T12 Accessibility | 48dp targets, semantics, named sliders, large text |
| T13 Build and dependencies | Release signing fallback warns; unused dependencies removed |
| T14 Dead code | Unused SAF writer, wrappers and policy code removed |

Also: two Opus scan fixes for real device libraries (`6500a82`, `34133cc`).

## 8. Code health and structure (2026-10-28 to 2026-10-31)

- `desloppify` queue worked through: no open items in code quality, duplication, test health and file health.
  Strict score 87.4; the remaining findings are skipped with a reason.
- Folders regrouped by feature (`lib/services/library/*`, `lib/services/playback/*`, `lib/widgets/player/*`,
  domain folders for providers and screens, `test/` mirrors `lib/`).
- Large files split under about 500 lines with `part` files, then renamed to descriptive names.
- FFmpeg moved to the minimal package, then reverted to `ffmpeg_kit_flutter_new_audio` 2.5.7 (`95778bf`).

## 9. Review fixes (2026-10-31)

**Architecture review** (`reviews/ARCHITECTURE_API_INITIALIZATION_REVIEW.md`, five findings, all fixed)
- Native progress payloads must be JSON objects; malformed ones throw instead of reading as empty.
- Playback restore returns a typed outcome (`restored`, `nothingSaved`, `failed`) and retries after a failure.
- The player widget binding and AutoMix status are injected per runtime.
- Audio analysis state moved into `AudioAnalysisController`, with tests.
- SAF read probes and audio route reads return typed results.

**Bridge deep review** (`reviews/BRIDGE_DEEP_REVIEW.md`, F1–F13)
- A panic in the USB worker becomes a playback error instead of crashing.
- Non-ASCII audio paths reach native code as UTF-8 bytes.
- Playback leases are no longer evicted (at most 8; when full, playback falls back).
- Logcat reads have a deadline; a MIME lookup moved off the main thread.
- Cancellation lost its unused wake-up path; pre-cancels are bounded (256).
- SAF timestamp lookups run in chunks of 50 and can be cancelled.
- Small data jobs and lyrics (under 64 KiB) encode on the calling isolate. Measured on the host only.
- Open: a Kotlin watchdog for a stuck USB pump (F1), and device measurements.

## 10. This session's last changes (2026-10-31)

- **Setup folder step** (`8464cef`): choosing a music folder or tapping Skip for now goes straight to the next
  page. Cause: the resume check after the folder picker reset the step to "not granted", so Next stayed disabled.
  Also fixed: reopening setup jumped past the folder page because current drafts were shifted as old ones. A new
  test fails without the fix (shown with `work.py prove`). The full `flutter test` run did not finish in the cloud
  container (the runner stalled between files); every folder passed when run on its own.
- **New workflow** (`95d2d94`, `7cacbc4`): `sistrum-workflow/`, a repo-local workflow for the next repository.
  See section 12.
- **Release APKs:** arm64 from `fd4b5dd` and from `a007921`. Neither was tested on a device.

## 11. Not verified

- No change in this file was tested on an Android device by the agent. Playback, scanning, SAF and USB, widgets,
  background behaviour and statx compatibility need device checks.
- Kotlin unit and instrumentation tests were not run for the 2026-10-31 native changes.
- The full `flutter test` run after the setup fix did not complete in the cloud container.
- In `scripts/`, `test_find_dead_code` needs `tree-sitter` installed, and `test_generate_sistrum_branding` fails
  (`'16%' != '0%'`).
- Release builds use a development key; a production key is needed before official distribution.

## 12. Workflow and tooling history

- **2026-10-19:** review agents, `reviews/PROTOCOL.md`, `/review` and `/audit` skills.
- **2026-10-28 onward:** `desloppify` and `graphify` drove the code-health work.
- **2026-10-31:** `new workflow/` (owner commit `3c780a6`), followed by `sistrum-workflow/`. The second one is a
  self-contained package for the next repository: 7 skills, 3 read-only reviewer agents, a constitution,
  change-record templates, and `scripts/work/work.py` (evidence, gates, `prove`, a Bash guard). Nothing needs
  installing, and it has 45 tests. It was built from spec-kit, elephant-goldfish-model, deepseek-stack, ponytail and
  desloppify.

## 13. Where the details are

| File | Content |
|---|---|
| `LOCAL_OFFLINE_MIGRATION_PLAN.md` | Every step with commits and test results (the main source of this file) |
| `PHASE6_DECISIONS.md` | Decisions made during the download-engine removal |
| `AGENTS.md` | Current product rules |
| `docs/AUDIO_ENGINE_MIGRATION.md` | The Media3 plan and decisions D1–D7 |
| `reviews/` | Audits, findings, upstream ledgers, review reports |
| `sistrum-workflow/README.md` | The new workflow |
