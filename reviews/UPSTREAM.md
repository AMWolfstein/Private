# Upstream port list

Upstream: `spotiflacapp/SpotiFLAC-Mobile`. This fork started from **v5.1.1** (`78699a91`,
2026-10-11), the closest match of the fork's first commit's blobs. The histories are not shared,
so `git merge` is impossible; port one upstream commit per batch, with the `AGENTS.md`
code → graphify → docs commits, analyze, full `flutter test` and a `/review`.

- Last upstream commit checked: `21ee30c4` (2026-10-19, after v5.2.0). Next check: only commits
  after it (`git log 21ee30c4..origin/main`).
- Do the ports before any module/folder reorganisation; moved files make every patch fail.
- Before a `FIX_PLAN.md` batch, check this list for an upstream commit that fixes the same code.
- "Clean" = `git apply --check` passed against `57601c3`. Everything else needs a manual port;
  some fail only because an earlier upstream commit is missing.

## Requested by the owner

### U-001: per-field tag separators (`ac8523d7` + `9495a6bf`)

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

Owner decision needed: where the page lives. `AGENTS.md` bans the download-era Metadata
page, so suggest **Local Library settings → Tag separators**, and add one `AGENTS.md` line that
allows it. Do not restore Artist Tag Mode UI (`settings_search_test` asserts it is absent).

## Clean ports

| ID | Upstream | What |
|---|---|---|
| U-101 | `65dbce27` | AutoMix waits for advancing audio before fades. |
| U-102 | `08bc4226` | Cache adjacent track titles during swipes (perf). |
| U-103 | `afab47ae` | Cache timed lyric segment geometry (perf). |
| U-104 | `6debfccb` | Keep dominant cover colours in player backgrounds. |

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

## Optional features (owner chooses)

| ID | Upstream | What |
|---|---|---|
| U-301 | `ecf594aa` (+`68c739df`) | Multiband EQ / native audio processing (~4.5k lines; adds DSP, does not replace the engine). |
| U-302 | `11c6cf99`, `2455cabc` | Music-synced haptics. |
| U-303 | `40f65d3a` | Audio source/processing/output details. |
| U-304 | `08266c73`, `1d53bf93` | Rewind and listening-statistics highlights. |
| U-305 | `83a55fb8` | Sectioned library browsing and fast scroll. |
| U-306 | `cb51d089`, `36694c6e` | Persistent crash reports on Home. |
| U-307 | `75cd4c39` | Refreshed launcher widgets. |
| U-308 | `78a5e078`, `2782b1f7` | Lyric share cards, on-demand lyrics loading. |
| U-309 | `67a346c1`, `4cee16e9` | Home greeting and listening shortcuts (differs from the Apple Music Home). |

## Do not port

Online lyrics (QQ, lrc.red, BetterLyrics, Apple fallback, online lyrics search), extensions,
downloads, network/NAS, extension country settings, Material Expressive/Symbols/spring motion,
the 5.2 release tour, About links, and `75907951` (bit-depth default badge conflicts with the
`AGENTS.md` badge policy).
