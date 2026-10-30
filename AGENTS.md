## Migration status

This repo is being converted to a local/offline Android-only music player.
**Read `LOCAL_OFFLINE_MIGRATION_PLAN.md` (esp. `## Progress`) and `git log --oneline -10`
before continuing any migration work.**

The app targets Android and local files only: no iOS code paths and no on/off switch for the local library (it is always on). Sistrum is its sole production theme; keep
light/dark modes and local storage, playback, lyrics, backup and USB support. Do not
reintroduce providers, downloads, extension credentials or remote artwork loading.

V3 detail designs are restored over local data. Artist navigation must open
`local_artist_screen.dart`, not a generic filtered album browser. Keep Play centered,
feature releases by their release-date tags, and classify Singles from explicit total-track
tags (1), never from the number of files stored from an album; EPs remain under Albums.

Artist Popular shows at most 20 local songs, ranked by all-time recorded play counts; use a
random selection for unplayed songs/no history, stable while the page stays open. Display five
songs per page with dots (at most four). No artist Show-more controls; discography shelves
load additional pages when swiped near their end. Keep full-artist playback independent of
the Popular cap.

V2 Home uses the Apple Music editorial-card/shelf composition with local data. Keep featured
releases ordered by release tags, bounded shelf queries, local artwork and local detail routes.
Home has no Recent access-history section. Latest Releases uses valid release-date tags
from local songs, normalized chronologically without scan/add-date fallback; keep Home's
Recently Added shelf unchanged. Do not replace the feed with only access history.

Detailed logging is always on and has no toggle; Logs filters by level with a Full option that shows every entry. There is no separate App settings page.
Lyrics settings do not contain Embed lyrics or its output-mode submenu/preferences.
Local lyrics reading and per-file metadata/lyrics editing remain supported. Appearance has
no decorative Library preview card. Settings and Library subpages reuse the album header's
circular back button in Sistrum.

Settings no longer include the obsolete output-folder Files & Folders page or the
download-era Metadata page. Music scanning stays under Local Library; local per-file tag
editing remains supported. Tag separators (see Tag separators below) live under Local Library settings and apply when
local tags are saved; Artist Tag Mode is removed entirely (UI, preferences and writer plumbing: do not restore it). Local Library settings have no Default view or Audio quality
label-mode options: do not restore their preferences, pickers, search entries or tab-reset
behavior. Library badges use the standard measured/stored bitrate policy, with codec
fallback for legacy lossy files. Audio playback uses only the built-in player, including on old
settings imports: do not restore player-mode choices, external-player shortcuts or automatic
external fallback on initialization failure. Keep USB/output-device controls and DSP settings.
Playback errors keep the selected song for retry; same-ID duration/artwork updates must reach open players.
Scanned artwork that is absent or stale falls back to the bounded local embedded-cover cache.
Exact PCM output decodes FLAC through the integer native source; never trust vendor raw
FLAC decoding to preserve source precision or label padded output as source bit depth.
Switch and slider thumbs (AppSwitch, AppSlider, horizontal AppLevelSlider) turn into
liquid glass only while touched and only when the glass thumb gate allows it; no lens or
capture at rest, and the plain controls are the fallback. Seek, volume and vertical EQ
faders keep their painted controls.
Sistrum album headers and the immersive player's cover drift slowly (Ken Burns, `AlbumKenBurns`); Appearance > Animated artwork turns it off. Albums and the player's cover (both Normal and Immersive views) only: playlists, Loved and artist headers stay still. The player's drift pauses while lyrics show. It pauses for reduced motion, glass off or low-end devices, covered routes and a page scrolled past the cover.
Pinned headers float: transparent toolbars with a glass back circle, IconButton and menu actions in
one glass capsule and a backing band only once content scrolls under (opaque on flat level or high
contrast). Header controls (not the player's) are 48dp, 4dp from the edge, with 22dp icons; the
profile photo (opens Settings, rim outline, no glass) ends every header 8dp after the capsule and
is hidden on Settings and its subpages. Headers mirror in RTL. Only the bottom bar samples its backdrop, through one shell LiquidGlassView held at
rest; headers judge known backdrops (page, artwork top) and never sample themselves.
Glass is configured by `glassQuality` (auto / lite / full / off; Auto follows the device class
and alone honours high contrast) and `glassClarityLevel` 1-5 in app settings. Every clarity
number lives in `kAppGlassLevels`; never store a percentage or add clarity formulas. Level 1
is a plain blur, never a lens; off has no lenses, blur or sampling; lite has no shader except
touch-only thumbs and segment pills. Do not restore "Always use blur effects". The performance
HUD is a hidden developer option (seven taps on About's version) and is absent when off; it starts
top-left, drags, minimizes to a pill and its statistics never take touches. Blur never drops below
sigma 6 (lighter tint makes Clear and Crystal). Auto measures p90 raster time per build (above 14 ms:
full -> lite -> Level 1 lite), saved outside the settings backup; explicit qualities are never measured.
In the shell, persistent chrome shares one backdrop read: one public `LiquidGlassBatch`
(`AppChromeBatch`) above pages and bar (a second one above the root navigator serves Settings
and other root routes), joined only through `AppChromeMember` (header leading
circle and actions, tab capsule, mini player, bar side buttons at rest). Blurs push its key through
our own layer, on Impeller only; never import `liquid_glass_easy/src` or allocate ids. The band,
page content, sheets, glass inside Opacity, folding side buttons and moving or covered routes read
on their own. Glass over known artwork (the player's menus and sheets; album and artist header
controls, which opt in through `AppHeaderControls`) reads nothing: it draws a pre-blurred
ground image (`AppPlayerGround`/`AppPageGround`, 384 px wide, at most 6 MB in total, released
with their screen) through our `app_artwork_glass.frag`; never a BackdropFilter, lens or view
there. Album, playlist and artist headers soften while scrolling by fading that ground over the
artwork (`AppGroundVeil`), never a live blur. Lite and Level 1 draw the ground without the shader; an overlay picks its material once at
open (opaque if its ground is not ready). No menu has a staged glass reveal: page menus keep one
material from the first frame too.
Cover colours come from one analysis per cover version (`CoverPalette` -> `appCoverColors`:
bottom/top edge, dominant, harmonized accent; HCT, chroma never above the cover's, AA on-colours;
stored in the library DB's derived `cover_analysis` table). Screens and grounds take every cover
colour from it; never add HSL or second copies of the colour maths.

Audio format conversion is removed entirely: do not restore single-track or batch Convert
menus, format/bitrate/quality sheets, encoding services or converted-file publication.
Keep local tag/cover/lyrics editing, ReplayGain and CUE splitting as separate operations.
Artwork probing and FFmpeg processing for those retained features remain supported.

Tag separators live under Local Library settings as a list of rows: Artists (artist,
album artist, composer), Genre and Keep together, each of the first two opening a sheet with
its chips and Keep together opening a sheet of names that are never split. Each row opens a sheet with a grid of separator chips (four
per row) with defaults, All (selects every chip; when all are selected it resets to the
defaults), and an Add separator field that Save adds; a section is never empty. A Save with
group (Artists, Genre) picks the separator that joins names when Edit Metadata saves tags. Keep together lists names that are never split.
The library reads credits through a derived TEMP table `library_tag_credits` (item_id, field,
name, name_key, position, built by `LibraryTagCreditsCache` from the visible view with the
same rules), so artist and genre pages, search, and the discography shelves agree with the
settings. Track-artist credits make the Artists list and artist pages; album-artist credits make a
separate Album Artists list, placed directly below Artists in the overview. Albums
uses album-artist credits, and Appears On sits directly below Singles for releases where the
artist is credited on a track but owns no track of the release. Go to Artist and Go to Composer
in the song menu open one name directly, or a picker when a credit splits into several names.
Artist pictures use the artwork of the artist's most recently added song that has one.

Appearance exposes Player view with Normal view (the default inset artwork) and Immersive
view (the existing full-bleed portrait artwork). Persist the choice across restarts; lyrics,
queue, track changes and mini-player dismissal must work in both views. Landscape retains
the two-column player. Do not restore the obsolete History View/Layout preference or search
entry; the Library overview uses matching category rows and dedicated Library sections
use rows. The overview has no Recently Added album grid. Keep Genres directly below Songs, followed by Loved Songs and Favorite Artists,
with Playlists in its own category. Genres uses bounded local tag queries against the visible
library, with exact tag matching and no online catalog. Songs contains only tracks (including
playlist members), with no collection rows or individual playlists mixed into the list.

Library pages have no search field (search lives in the bottom Search tab). Songs headers show Play/Shuffle, the
player favorite is a heart, Insights (listening statistics) is the tab after Home and records listening always on, with no Record listening toggle, Edit Metadata has no cover resizer, and each
lyric line takes its direction from its first strong letter.

The updater is restored: `UpdateChecker` reads GitHub releases from `AppInfo.githubRepo`, Settings > Updates (above About) holds Check now and the
Check-for-updates and preview-release switches, and `UpdateDialog` downloads the APK (HTTPS, resumable, SHA-256
checked) and hands it to the system installer. The release manifest therefore allows INTERNET (and
REQUEST_INSTALL_PACKAGES with a FileProvider); no other feature may use the network.

Song taps start local playback; do not restore the separate TrackMetadataScreen/details
route. Song ellipsis menus expose the former local track actions: Play/Share, Play next,
Add to queue, Go to album/artist, Copy file path, Edit Metadata, ReplayGain apply/remove,
Audio Quality Analysis and confirmed deletion. CUE tracks have Split into Tracks; deleting
one virtual row must preserve the backing CUE/audio. Do not restore Wishlist, conversion or
online-only actions. Capture the tapped ellipsis button's root-overlay bounds before any
async lookup; long popovers scroll within space above/below that control. Songs, playlists
and Loved Songs use artwork, title plus explicit E, artist underneath, circular Play and
ellipsis controls. Albums use track numbers instead of artwork. Keep selection, range
selection and queue order working. Loved Songs remains a UI-only rename: persisted collection
keys and backups stay compatible.

Album-style collection headers (albums, playlists and Loved) use one centered
row ordered left to right: Loved, Play/Pause, Shuffle, Add to playlist. Reuse the filled
Play and translucent Shuffle pills with compact sizing and at least 48px touch targets;
keep the outer icons in the same row, including RTL. Do not move Shuffle into the toolbar.
The artist header retains its separate centered-Play design.

Wishlist is removed from the Library, track menus, models, backups and native collection
queries. Collection schema v3 drops the obsolete table on upgrade; old JSON imports ignore
that category. Keep Loved, playlists and favorite artists supported.

The app supports every locale with an arb file in `lib/l10n/arb` (English is the template). Setup
and Appearance offer the language picker, and the chosen locale is saved. Untranslated strings fall
back to English. Keep `lib/l10n/supported_locales.dart` and `lib/constants/language_choices.dart` in
sync with the arb files. Do not reintroduce the old 70% completion filter.

First-run setup and the local-player guide form one flow. Keep the local playback tips and
permission checks under the same page counter and Back/Next navigation.
Get Started finishes directly in Home from the final permission page; do not restore the
old download/output-folder step or a second tutorial afterward. Persist both completion
flags together, and migrate old setup drafts without restoring their output-folder fields.
Music-library folder selection remains available under Local Library settings.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).

## Feature-removal workflow

**Always use graphify first** when removing a feature (never start from raw grep alone):

1. **Plan** — read the latest graph (`graphify query` / `path` / `explain`, and
   `graphify-out/GRAPH_REPORT.md` if needed) to find every node/edge the feature touches and to
   confirm the blast radius before deleting anything.
2. **Remove** — make the code changes (cross-check paths with `grep` as you go).
3. **Confirm removal** — run `flutter analyze` (must be `No issues found!`) **and the full
   `flutter test`**; also re-query graphify / grep to prove no references remain. Fix until clean
   (no standing flaky-test exception; investigate and record any failure).
4. **Commit** — in the order below.

## Code review

Review rules, finding format and state live in `reviews/PROTOCOL.md`; resume from
`reviews/STATE.md`. Claude Code: `/review [range]` (incremental, default 1 reviewer, max 3)
and `/audit <subsystem>` (one bounded subsystem); reviewer agents are in `.claude/agents/`.
OpenCode loads the same reviewers as read-only subagents from `.opencode/agents/`; regenerate
them with `python3 scripts/sync_opencode_agents.py` after editing `.claude/agents/` (`--check`
reports drift). Codex: act as one named reviewer from `.claude/agents/<name>.md` per pass.
`scripts/review_scope.sh` picks scope, reviewers and graph freshness without a model.
Reviewers never edit code; fixes are separate 1–3 finding batches that follow the commit
conventions below. Review checkpoints commit only `reviews/` (`docs(review): <unit>`).

## Upstream ports

Synced lyrics suspend hidden/background work and settled word tickers; line changes use the lyric spring with reduced-motion support, while scrubbing stays quick and manual scrolling keeps its anchor.

Upstream remains [the original project](https://github.com/%6D%6F%72%6E%79%65app/%4D%6F%72%6E%79%65),
not a new Sistrum repository. Ports follow `reviews/PORT_PLAN.md` (setup, rules, batch
order, testing once per batch) with specs in `reviews/UPSTREAM.md`.

**T16 owner override (2026-10-28):** the owner explicitly supersedes the earlier
branding-preservation rule for this owner-wide Sistrum rename (including internal
identifiers and filenames). Every file whose basename is `README.md` remains unchanged.
Legacy backups, settings and other persisted identities remain supported through encoded
legacy identifiers; encoding must preserve their exact original runtime values. External
upstream and published APK URLs use percent-encoded former tokens, not invented remote
repositories or renamed remote artifacts. Historic copyright attribution remains with the
original authors. Historical reports normalize names mechanically, not evidence of new runs.
For later upstream ports, do not import unrelated upstream branding.

## Shared widget names

Every UI identifier uses the `app_` file prefix and the `App` class prefix (`kApp` for
constants), including the theme (`app_theme.dart`, `AppTheme`), glass, chrome, slider,
context-menu and player widgets. No UI name uses `sistrum_` or `Sistrum`. The app name
`SistrumApp`, the `sistrum` package name and persisted or external identifiers (preference
keys, backup and export file prefixes, channel names) keep their original values.

Apply the rule to new shared widgets and do not rename them by hand to a different prefix.

## Commit conventions

The workflow ends in **three separate commits** — never mix them:

1. **Code commit** — source, tests, config only (`lib/`, `test/`, `integration_test/`, `scripts/`,
   `pubspec.*`, Android files, etc.). The message describes the code change (`chore(offline): ...`).
   This commit must **NOT** include `graphify-out/` or `LOCAL_OFFLINE_MIGRATION_PLAN.md`.
2. **Graphify commit** — run `graphify update .` and commit only `graphify-out/` tracked files as
   `chore(graphify): refresh code graph after <phase>`.
3. **Docs commit** — `LOCAL_OFFLINE_MIGRATION_PLAN.md` (and `AGENTS.md`/docs if touched), e.g.
   `docs: record <phase> in progress tracker`.

Order: **code → graphify → docs** (graphify reflects the code commit; docs record the finished
work). Stage paths explicitly (e.g. `git add -u` then list `graphify-out/...` files); never
`git add -A` because generated artifacts (`.dart_tool/`, `build/`,
`lib/l10n/app_localizations*.dart`, `.flutter-plugins-dependencies`, `graphify-out/cache/`) are
untracked.

## Local verification commands

Activate the repository toolchain and run `dart scripts/prepare_flutter_sdk.dart` once per fresh Flutter
install (it backports a semantics crash fix), then run `flutter analyze` and the full `flutter test`.
Rust changes require `bash scripts/check_rust_backend.sh`; Android native changes require
`bash scripts/check_android.sh` (host unit tests; no APK packaging). Instrumentation source
compilation is separate from device execution; never report compilation as a device pass.

Run Flutter test commands and APK builds serially in this checkout: both regenerate Android plugin registrants, and a test can add a dev-only plugin while release Java compilation excludes it.

## Part files

Use `part of` only to split one library's private implementation across files, such as a
`State` class or a widget whose helpers share private members with it. Everything else is a
library module that imports what it needs. A part file never adds its own imports. Generated
`*.g.dart` files are exempt.

## Failure signalling in services

- A lookup that may find nothing returns `T?`, and null means only "not found".
- An operation the user can see fail returns a typed result (`MetadataEditResult`,
  `SafWriteBackResult`, `ApkDownloadResult`, `BackupParseException`) or throws a typed exception.
  Do not add a bare `bool` or a map whose failure is a key to check.
- Best-effort cleanup uses `deleteBestEffort` or a logged catch, and says so in its name or comment.
- A wrapper that only forwards a typed result's `success` is removed; callers use the typed result.
