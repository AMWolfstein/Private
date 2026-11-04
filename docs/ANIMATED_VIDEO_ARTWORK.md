# Animated video artwork: implementation report

Status: implemented and unit/widget tested. Not verified on a device, and not verified
against the live Apple Music catalog (see "Verification limits").

## What was added

Album and artist covers can show a saved, looping, silent Apple Music video. The
feature has four parts:

1. **Apple Music lookup** (`lib/services/animated_artwork/apple_artwork_client.dart`,
   `apple_artwork_parse.dart`). Catalog search, direct album/artist link resolution,
   editorial motion-video selection, developer-token acquisition and expiry, retry and
   bounds. Parsing and matching are pure functions.
2. **Download** (`animated_artwork_download.dart`). A single-file fMP4 HLS fetch into
   owned storage, MP4 container validation, and a local-file import that reads a byte
   stream (SAF-safe).
3. **Store and background pass** (`animated_artwork_store.dart`,
   `animated_artwork_auto_pass.dart`). Records, ownership rules, safe publication, and
   the bounded background lookup with progress.
4. **Presentation and UI**: the video widget (`lib/widgets/animated_artwork/`), the
   Find animated artwork sheet and menu, album and artist header integration, Now
   Playing integration, the Download video artwork settings page, and Cache settings.

No Extension system, plugin host, JavaScript runtime, music download, catalog
replacement, or metadata replacement was added. No native (Kotlin/Rust/C++) code
changed. The only new dependency is `video_player` (Flutter's maintained plugin, which
uses ExoPlayer on Android); `video_player_platform_interface` is a dev dependency for
the test fake.

## Data flow and ownership

- **Keys.** An album is keyed by its normalized title and album artist
  (`animatedAlbumKey`). The album detail page and Now Playing both use
  `animatedAlbumRefForItem`, so one album has one video. An artist is keyed by its
  normalized name (`animatedArtistKey`). Album and artist records never collide.
- **Records.** `animated_artwork.db`, table `animated_artwork`, primary key
  `(kind, artwork_key)`. A record holds a status, the relative file name, an optional
  Apple remote id, the check time, and the frame size and byte count. The remote id is
  provenance and dedup only; playback never uses an expiring Apple URL.
- **Files.** `<app support>/animated_artwork/<kind>_<digest>_<stamp>.mp4`. Downloads go
  to `.staging/` in the same folder, and publication is a rename.
- **Publication order.** Download, validate, rename into place, write the record, then
  delete the previous file only if no record references it. A failed database write
  removes only the file this attempt just created; the previous video keeps working.
- **Tickets.** Each entity has a revision and the store a generation. A manual choice,
  Reset or Clear advances them, so older in-flight work is refused at commit time.
- **Locks.** While a manual choice is being saved, `AnimatedArtworkLocks` makes the
  background pass skip that entity.

## Automatic / manual / Reset / Clear semantics

| Action | Effect on the video | Effect on automatic work |
| --- | --- | --- |
| Background pass (setting on) | Fills an entity with no record, or with a miss older than 14 days | Never replaces a manual video, an automatic video, or a Reset |
| Download video artwork switch off | **Nothing is deleted or hidden.** Saved videos keep playing | Stops new lookups only |
| Find animated artwork, then Use | Replaces any video with the chosen one | Supersedes any in-flight automatic result for that entity |
| Find animated artwork, pick a file | Same as above, with the file copied into owned storage | Same as above |
| Reset animated artwork | Removes the video file; static artwork returns | Blocks automatic replacement until a new manual choice |
| Cache > Video artwork > Clear | Removes every video and record; in-flight work is superseded | Future passes may fetch again while the switch is on |

Reset does not touch the artist photo (`artist_images/`), the album cover, or music
files. Clear touches only `animated_artwork/` and `animated_artwork.db`.

Misses and failures are kept apart. A catalog outage, a malformed response, or a
network failure records nothing and is retried later. Three consecutive network
failures end the pass as an outage. A legitimate miss (no match, ambiguous, no video,
or a video the bounds reject) is recorded as not found and retried after 14 days.

## Matching

Only an identical normalized title and album artist match an album. Normalization
lowercases and replaces punctuation and spacing with single spaces. It keeps letters
from every script, so Arabic names match exactly. A match also needs a compatible
track count and UPC when both sides know them, so deluxe and other editions never
match the standard release. Two exact catalog releases are ambiguous, unless a UPC
settles the choice; ambiguous results are recorded as not found. An artist matches
only the same normalized name, never a first name or a loose shared word. Collaboration
credits match when the members are the same and only the separators differ; a different
member set does not match. Local tags are never overwritten with catalog metadata.

## Download and storage bounds

- Only a single-file fMP4 HLS playlist is accepted: an init map and byte-ranged fragments
  of one URI, with no encryption and no discontinuities. Segmented playlists are reported
  as unsupported and are not concatenated.
- The AVC variant is chosen; its declared frame may be at most 3840 pixels on its longest
  side.
- Limits: 24 MiB of video, 60 seconds for the whole download, 15 seconds per stall, and a
  512 KiB playlist. The file must end with a complete `ftyp` and a `moov` box.
- The declared length must match the bytes written. A short body is "incomplete" and is
  not recorded.
- Local imports are limited to `.mp4`, `.m4v` and `.mov` (picker filter), read as a
  stream, and checked the same way.

## Playback and presentation

- The video is created with `VideoPlayerOptions(mixWithOthers: true)` and muted. The
  platform receives `setMixWithOthers`, so audio focus is not taken, music volume is not
  changed, and no media notification is created.
- The static cover stays visible until the first frame. The video fades in over 240 ms
  and never shows a black start frame.
- It plays only while the app is resumed, the route is not covered by another route
  (`secondaryAnimation`), the ticker is enabled, and reduced motion is off. Otherwise it is paused. Lyrics pause it in Now Playing, as they
  pause the drift.
- Initialization or decode errors leave the static cover in place. A load for a new file
  disposes the previous player at once; a late initialization for a superseded file
  disposes itself.
- Album headers show the video only while Appearance > Animated artwork is on; the
  Ken Burns drift is applied only to the static fallback. Now Playing shows the album's
  video in both Normal and Immersive views and drops the drift while a video plays.
- Thumbnails in library lists and Home shelves are unchanged and stay static.

## Settings and localization

- `videoArtworkAutoDownload` (default off) and `videoArtworkNetwork` (default `wifi`,
  unknown values read as Wi-Fi) are persisted with the other settings. The network kind
  is read through the existing `getNetworkKind` channel, shared with artist photos.
- Appearance > Download video artwork: the switch, the network choice, and a progress row
  (checked of total, and saved / not found / failed counts).
- Cache > Video artwork shows the folder size and a confirmed Clear.
- English and Arabic strings are added. Other locales fall back to English until they are
  translated. The Animated artwork subtitle now says it also plays saved video covers.

## Licensing and attribution

The single-file HLS rules and the Apple Music token and key-priority logic follow
Mornye (`mornyeapp/Mornye`) and Mornye-Extension (`mornyeapp/Mornye-Extension`), both
LGPL-3.0-only, Copyright 2026 zarzet and contributors. The Dart code is rewritten for
Sistrum's architecture. The adapted files carry a header comment, and the notice is in
`assets/licenses/animated_artwork.txt`, registered in the app's license list next to the
existing Mornye adaptations.

## Verification limits

- **The Apple Music catalog was not reached from this environment.** Every request
  shape, token extraction and motion-key choice is covered by fixtures that follow the
  reference extension. The live endpoints, the token pages, and the video CDN may differ.
  Nothing here is an official or stable API, and Apple can change or block it at any time.
- **No device testing.** Playback on Android (first frame, decoder release, audio focus
  with music playing, rotation, Hero transitions) and background passes across real
  network switches are not verified.
- **Local storage on Android** (the SAF picker and the staging rename across providers)
  is verified only by stream-based tests.
- The Android build and the `video_player` plugin registration were not built here; no
  APK was produced.

## Test results

- `flutter analyze`: **No issues found.**
- Full `flutter test`: **2669 passed, 4 skipped, no failures** (the run completed; it was executed serially, after clearing the regenerable test compile cache to free disk space).
- Focused suites included: `test/services/animated_artwork/` (Apple parsing, matching, client token/expiry/retry/malformed cases, HLS download and import rules, store ownership and failure cases, background-pass rules and retention), `test/providers/animated_artwork/` (album identity shared by tracks, target listing, Various Artists skipping), and `test/widgets/animated_artwork/` (fallback on failed creation, muting and mixing, looping, reduced motion, inactive gating, release on removal, no frame before the first frame).
- Not run: any device or live-network check (see Verification limits).
