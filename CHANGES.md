# Sistrum: complete record of changes, decisions and working rules

This file is the single record of what was done to this project, from the original 5.1.1 release to today
(2026-10-31). It covers three things: what changed, the decisions behind it, and the rules the work follows.

- Starting point: the original project 5.1.1, an online, extension-driven music downloader for Android and iOS.
- Today: **Sistrum 1.0.0**, a local, offline, Android-only music player.
- Period: 2026-10-16 to 2026-10-31.
- Unless a section says otherwise, nothing here was tested on an Android device; host checks never count as
  device checks.

## 1. Summary

| | Before (5.1.1) | Now |
|---|---|---|
| Purpose | Download music from online providers through extensions | Play the music files already on the device |
| Platforms | Android and iOS | Android only |
| Network use | Providers, extensions, SMB/WebDAV, Discord, updater, remote config | Only the GitHub release updater |
| Native backend | Rust with online crates (network, providers, extensions) | Rust with local crates only (core, local, mobile, bindgen) |
| Look | Several themes and a theme picker | Sistrum theme only, light and dark, liquid glass |
| Name | The original name and package | Sistrum, `com.amwolfstein.sistrum` (side-by-side build: Sistrum Local) |
| Tests | — | 2,281 Flutter tests pass, analyzer clean; Rust core and mobile tests pass, clippy clean |

## 2. Decisions

### Direction
- The app becomes a local, offline, Android-only music player.
- The player and queue read the local library database. Download history is deleted.
- Home stays, rebuilt from local data.
- Sistrum is the only theme. Light and dark modes, accents, glass and font controls stay.
- The original artist, album and playlist designs are restored over local data.
- Every online setting is removed: extensions, providers, downloads, network storage, Discord, remote config,
  profile, donations.
- Kept: local storage, playback, lyrics, metadata editing, backup and restore, USB and output-device controls,
  DSP, AutoMix, ReplayGain, CUE, statistics, widgets.

### Things that must not come back
Providers, downloads, extension credentials, remote artwork loading, iOS code, format conversion, Wishlist, the
separate track details page, player-mode choices and external players, Artist Tag Mode, Embed lyrics, the
output-folder and download-era Metadata pages, App settings page, Default view and Audio quality label options,
History View, "Always use blur effects", the Library preview card, search fields inside Library pages, the Home
Recent access section, and the old download/output-folder setup step.

### Product rules (from AGENTS.md)

**Home**
- Apple Music style editorial cards and shelves over local data, with bounded queries and local artwork.
- Latest Releases uses valid release-date tags only, in chronological order, with no scan-date fallback.
- Recently Added stays. There is no Recent access section, and the feed is never replaced by history.

**Library**
- The overview order is Songs, Genres, Loved Songs, Favorite Artists, then Playlists in its own category.
- Artists and Album Artists are separate lists, with Album Artists directly under Artists.
- Songs holds only tracks. Genres use exact tag matching against the visible library.
- Badges use the measured or stored bitrate, with a codec fallback for old lossy files.
- Library pages have no search field; search lives in the bottom Search tab.

**Artist page**
- Opens `local_artist_screen.dart`, with Play centered.
- Releases are featured by their release-date tags.
- Singles come only from an explicit total-track tag of 1. EPs stay under Albums.
- Popular shows at most 20 songs ranked by all-time play counts, with a random but stable order for unplayed
  songs. It shows five per page with at most four dots.
- There are no Show-more buttons; discography shelves load more when swiped near their end.
- Playing the whole artist is not limited by the Popular cap.
- Appears On sits under Singles.

**Album, playlist and Loved**
- One centered row: Loved, Play/Pause, Shuffle, Add to playlist. It keeps its order in RTL, and Shuffle never
  moves to the toolbar.
- Albums show track numbers. Songs, playlists and Loved show artwork, title with an explicit E, artist, Play and a
  menu.
- "Loved Songs" is a display rename only: stored keys and backups keep the old names.

**Song menu**
- Tapping a song plays it.
- The menu has Play or Share, Play next, Add to queue, Go to album or artist, Copy file path, Edit Metadata,
  ReplayGain apply or remove, Audio Quality Analysis and confirmed deletion.
- CUE rows also have Split into Tracks. Deleting a CUE row keeps the backing audio.
- The menu is positioned from the tapped button and scrolls when it is long.

**Tag separators**
- Under Local Library: Artists, Genre and Keep together. Each opens a sheet of chips with defaults, an All option
  and an Add field.
- Edit Metadata saves names exactly as typed. Keep together protects names like AC/DC.
- A derived credits table keeps artist and genre pages, search and shelves consistent with these settings.

**Player**
- Normal or Immersive view, saved across restarts. Lyrics, queue, track changes and mini-player dismissal work in
  both, and landscape keeps two columns.
- Ken Burns drift on album headers and on the player cover, switched off from Appearance. It also pauses for
  lyrics, reduced motion, glass off, low-end devices, covered routes and a scrolled-away cover.
- A playback error keeps the song selected for retry. Duration and artwork updates reach open players.
- Each lyric line takes its direction from its first strong letter.

**Audio**
- Only the built-in player, even when importing old settings.
- Exact PCM output decodes FLAC through the integer native source.

**Glass**
- Quality setting: auto, lite, full or off. Clarity levels 1–5, all values in one table.
- Blur never goes below sigma 6.
- Auto measures frame time and steps down; explicit qualities are never measured.
- Switch and slider thumbs turn to glass only while touched.
- Headers float with a glass back circle and one capsule for actions. Controls are 48dp; the profile photo ends
  every header except Settings.
- One shared backdrop read for persistent chrome. Glass over artwork draws a pre-blurred ground image instead of
  sampling.
- Cover colours come from one analysis per cover, stored in the library database.

**Other**
- Setup and the local guide are one flow that ends in Home from the final permission page.
- Insights (listening statistics) is the tab after Home and always records.
- Logging is always detailed; Logs filters by level.
- Every language with a translation file is supported, falling back to English, and the language picker is in
  setup and Appearance.
- The updater reads GitHub releases. Its HTTPS download is resumable and checked with SHA-256, and it is the only
  feature allowed to use the network.

### Audio engine plan (decided, not started)
The next project replaces the engine with Media3/ExoPlayer:
- **Licence:** the licence becomes GPL-3.0, keeping the MIT notice for the original code.
- **minSdk:** raised to 31.
- **USB and output:**
  - Direct USB (libusb) is dropped.
  - The AAudio/Oboe exact-rate output is dropped.
  - Android 14+ bit-perfect output and DoP stay.
- **CUE:** tracks play directly, and Split into Tracks goes in the same step.
- **Playback ownership:** playback, queue, notification, Android Auto and the widget move to a Kotlin service, and
  Flutter becomes the interface.
- **Still open:** formats with no decoder after FFmpeg is removed have a recommendation but no decision yet.

## 3. Changes

### Online features removed (eight phases)
1. iOS, Discord sources, and online release tooling and scripts.
2. Discord rich presence.
3. Updater, remote config, announcements and donations. The updater came back later.
4. Network storage: SMB, WebDAV and NAS.
5. Extension store, provider priorities, online metadata autofill and re-enrichment, re-download, sharing between
   extensions, hi-res check, previews, Explore feed, weekly releases, artist concerts and motion artwork.
6. The download engine and extension registry. Player and queue now read the local library.
7. The Rust online crates (network, providers, extensions). A new local crate handles scans, CUE, tags, artwork and
   lyrics, and iOS build wiring was removed.
8. Online Dart dependencies, online translations and the release Internet permission. The permission came back
   with the updater.

### Features removed later
- Format conversion: single and batch, quality sheets and encoders.
- Wishlist: from the Library, menus, models and backups.
- The separate track details page. Its actions moved to the song menu.
- Obsolete settings pages and options (see "Things that must not come back").
- Legacy code:
  - download history;
  - old backup formats (backups are now `.sbk` version 3 only);
  - old-install migrations and old database upgraders;
  - single-folder library settings;
  - iOS paths;
  - two dead-code passes over Dart, Kotlin and Rust.

### Features added or changed
- **Identity:**
  - renamed to Sistrum, with old stored keys still readable;
  - version reset to 1.0.0;
  - a side-by-side build option;
  - a new launcher icon.
- **Home:** local editorial feed with cached shelves, pull to refresh and loading states.
- **Library:**
  - Album Artists list and Genres;
  - tag separators with Keep together;
  - Appears On;
  - Go to Artist or Composer with a picker;
  - sorting by file size;
  - section headers and fast scrolling.
- **Detail pages:** restored artist page with Popular; centered collection actions; song menus with all local
  actions.
- **Player:**
  - Normal and Immersive views;
  - Ken Burns drift;
  - optional lyric line above the seek bar;
  - heart favorite and quality badge;
  - normalization pre-amp and track or album gain;
  - optional equalizer (5 to 31 bands, preamp, balance, limiter, compressor, presets, import and share);
  - AutoMix that lands on the beat;
  - retry after errors.
- **Lyrics:**
  - spring scrolling, with work paused when hidden;
  - lyric quote cards;
  - untimed TTML shown as plain text;
  - right-to-left word sweep for Arabic.
- **Glass:** quality and clarity settings, touch-only glass thumbs, floating headers, shared backdrop reads, artwork
  ground images, and a hidden performance overlay.
- **Accessibility:** 48dp targets, labels, named sliders, live selection counts and large text.
- **Setup:** one flow with the local guide and permission checks.
- **Insights:** a tab with Rewind highlights.
- **Languages:** reduced to English, then all 19 translations restored on the owner's request.
- **Updater:** restored with in-app download and install.

### Upstream updates
- All 533 upstream changes between 5.1.1 and 5.2.6 were checked one by one:
  - 12 ported in the final pass;
  - 144 handled earlier (ported, already present, or declined with a reason);
  - 339 not applicable to an offline app;
  - 38 translation updates.
- Notable ports:
  - exact FLAC output;
  - tag separators;
  - lyric spring scrolling;
  - Rewind;
  - the equalizer;
  - media controls that follow late metadata;
  - AutoMix beat landing;
  - scans that index untagged MP3/MP4, raw AAC and ID3-prefixed FLAC.

### Safety and correctness audits

| Area | Main fixes |
|---|---|
| Folder scanning | A provider error is no longer read as an empty folder; an empty listing cannot wipe indexed songs |
| CUE delete and split | Deleting a CUE row removes only the row, never the audio file |
| Tag writing | Only edited fields are written; a failed write keeps the original file |
| CUE and library identity | Stricter CUE parsing; rescans re-read metadata; safer cover cache |
| Backup and startup | A crafted backup cannot write outside the private folder; covers restore with their rows |
| Lyrics | Untimed TTML shows plain text instead of raw XML |
| Playback | Seeks after restoring a session and previous-track restarts are no longer lost |
| Library correctness | Correct album grouping, Singles from explicit totals, safer search and deletion |
| Speed | Indexes for artist pages, a genre cache, cheaper scans and cover cache |
| Visible bugs | Partial album deletes, safe metadata saves, stale searches, damaged spectrograms |
| Accessibility | Touch targets, labels, large text |
| Build | The release signing fallback warns; unused dependencies removed |
| Dead code | Unused writers, wrappers and policies removed |

Two Opus scanning bugs found on a real device library were also fixed.

### Code health
- Every code-quality, duplication, test-health and file-health issue the scanner reported was fixed or skipped with
  a written reason.
- Folders were grouped by feature, and `test/` mirrors `lib/`.
- Large files were split under about 500 lines, then given descriptive names.
- A smaller FFmpeg package was tried, then reverted.

### Review fixes (2026-10-31)

**Architecture review (five findings)**
- Malformed native payloads now fail instead of reading as empty.
- Restoring playback returns a clear result and retries after a failure.
- The widget binding and AutoMix status belong to each player runtime.
- Audio analysis logic moved out of the widget and gained tests.
- Folder access checks and audio route reads return clear results.

**Native bridge review**
- A crash in the USB worker becomes a playback error.
- Non-English file paths reach native code correctly.
- Playback file handles are no longer taken away mid-song.
- Log reads have a time limit, and a file-type lookup left the main thread.
- Cancellation is simpler and bounded.
- Folder timestamp lookups run in cancellable chunks.
- Small data jobs skip a background isolate (measured on a computer only).
- Still open: a watchdog for a stuck USB stream, and measurements on a device.

### Last changes of the period
- **Setup folder step:**
  - choosing a music folder or tapping Skip for now goes straight to the next page;
  - reopening setup no longer jumps past the folder page;
  - a new test proves the fix.
- **New workflow:** a self-contained workflow package for the next repository (section 5).
- **Builds:** two release APKs for arm64, not tested on a device.

## 4. How the work is done (from AGENTS.md)

### Order of work
1. Read the progress record and recent history before continuing.
2. For codebase questions, query the code graph first, then targeted searches.
3. Make the change, then verify it.
4. Commit in three separate commits, in this order:
   - code (source, tests, configuration);
   - the code-graph refresh;
   - documentation and the progress record.
5. Stage files by name. Never stage everything at once, because generated files are untracked on purpose.

### Verification
- `flutter analyze` must be clean, and the full `flutter test` must pass before committing.
- Rust changes run the Rust check script (format, clippy, tests).
- Android native changes run the Android unit-test script.
- Flutter tests and APK builds never run at the same time.
- Compiling device tests is not running them on a device, and is never reported as a device pass.

### Removing a feature
1. Plan from the code graph: every file and link the feature touches.
2. Remove it, cross-checking with searches.
3. Prove it is gone: analyzer clean, full tests pass, and no references remain.
4. Commit in the three-commit order.

### Code rules
- **Failure signalling:**
  - A lookup that may find nothing returns a nullable value, and null means only "not found".
  - An operation the user can see fail returns a typed result or throws a typed exception, never a bare boolean or
    a map with an error key.
  - Best-effort cleanup says so in its name or comment.
  - A wrapper that only forwards a result's success flag is removed.
- **Part files** only split one library's private implementation and add no imports. Everything else is a normal
  module.
- **Naming:** every shared UI file uses the `app_` prefix and every class the `App` prefix. The app name, package
  name and stored or external identifiers keep their original values.

### Reviews and upstream
- Reviews follow one protocol, with specialised read-only reviewers and incremental reviews by commit range.
- Reviewers never edit code. Fixes come in separate batches of one to three findings.
- Upstream ports follow a port plan and record every upstream change. They never bring back upstream branding;
  the original authors keep their copyright credit.

## 5. New workflow for the next repository

The next repository starts from the original 5.1.1 release, then adds this project's code without agent files,
then installs a new workflow and begins the Media3 plan. The workflow package (`sistrum-workflow/`) is ready.

- **Use:** the owner talks normally. The workflow decides whether a request is a question, a plan, a small fix, a
  feature, an architecture change, a review or a release.
- **Fix:**
  1. Find the cause.
  2. Write a test that fails without the fix, and prove it fails.
  3. Make the smallest complete change.
  4. Run the checks, commit, and report.
- **Features and architecture:** spec, then plan, then tasks, then implementation, then an independent review in a
  fresh context, then ship. Architecture changes also get a design review until two rounds in a row are clean.
- **Pieces:**
  - a constitution;
  - seven skills and three read-only reviewers;
  - templates;
  - one Python tool for checks, evidence, gates, proof of tests and a guard against dangerous git and shell
    commands.
- **Requirements:** nothing to install. The tool has 45 tests.
- **Sources of the ideas:** spec-kit, the elephant-goldfish model, deepseek-stack, ponytail and desloppify. Scores
  and installed tools were left out on purpose.

## 6. Not verified yet

- **On a device:**
  - playback, background behaviour and controls;
  - scanning, metadata and lyrics saving, backups;
  - folder access, USB output and widgets;
  - older Android versions.
- **Recent native changes:** Kotlin tests were not run.
- **Full test suite after the setup fix:** it did not finish in the cloud environment, though every test folder
  passed on its own.
- **Two helper-script tests:** one needs a parser library installed, and one fails an assertion.
- **Release signing:** builds use a development key; official distribution needs a production key.

## 7. Where the details are

| File | Content |
|---|---|
| `LOCAL_OFFLINE_MIGRATION_PLAN.md` | Every step with its checks and results |
| `PHASE6_DECISIONS.md` | Decisions made while removing the download engine |
| `AGENTS.md` | The current product and working rules |
| `docs/AUDIO_ENGINE_MIGRATION.md` | The Media3 plan and its decisions |
| `reviews/` | Audits, findings, upstream records, review reports |
| `sistrum-workflow/README.md` | The new workflow |
