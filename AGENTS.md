## Migration status

This repo is being converted to a local/offline Android-only music player.
**Read `LOCAL_OFFLINE_MIGRATION_PLAN.md` (esp. `## Progress`) and `git log --oneline -10`
before continuing any migration work.**

The app targets Android and local files only: no iOS code paths and no on/off switch for the local library (it is always on). Sistrum is its sole production theme; keep
light/dark modes and local storage, playback, lyrics, backup and USB support. Do not reintroduce providers, downloads, extension credentials or remote artwork loading, except the owner-approved artist photo lookup and Apple Music video artwork lookup below. The online features are the user-started lyrics lookup, the artist photo lookup and the video artwork lookup below; only the artist photo lookup and the video artwork lookup run in the background, each only while its own setting is on.

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
Latest Releases uses portrait full-bleed editorial cards with release date/title/artist over a bottom gradient; keep local detail routes and release-tag ordering. Home places separate Albums and Singles shelves next to each other, Singles directly below Albums. Filter each bounded query before its limit; Singles require explicit total_tracks = 1 and total_discs <= 1. Partial albums, unknown totals and EPs remain Albums. Home has no Recent access-history section. Latest Releases uses valid release-date tags
from local songs, normalized chronologically without scan/add-date fallback; keep Home's
Recently Added shelf unchanged. Do not replace the feed with only access history.

Typography always uses system fonts and platform glyph fallback, including Arabic. The global accent is fixed red (light #CC2E33, dark #FF453A). Appearance has no color picker, system/custom-font controls or bundled text fonts. Hero transitions are always enabled, with reduced-motion and rotation/lifecycle safeguards; do not restore their toggle or the alternate opening slide. Retired font/accent preferences and the old Hero preference are ignored on import. Keep icon fonts and system monospace for diagnostic text.

Insights is the listening-statistics feature in its own tab. Listening recording stays automatic; do not restore its removed enable/disable setting.

Detailed logging is always on and has no toggle; Logs filters are ALL, DEBUG, INFO, WARN and ERROR. Do not restore the removed Full option. There is no separate App settings page.
Lyrics settings do not contain Embed lyrics or its output-mode submenu/preferences.
Local lyrics reading and per-file metadata/lyrics editing remain supported.
Find lyrics (the Now Playing action and the per-song button in Lyrics > Songs without synced
lyrics) opens one sheet pre-filled with the song's title, artist, album and duration; the fields can
be edited before a normal search. The search asks every built-in source in `lib/services/lyrics/`
once, at the same time, and groups the matches by their own timing (word-synced, line-synced,
plain text). Tapping a match previews it with two actions: Embed in file writes the lyrics through
the Edit Metadata persistence path (every other tag is kept; existing lyrics are replaced only after
the user confirms), and Download .lrc writes a `.lrc` file beside the audio file (replacing one only
after confirmation; folder-picker songs cannot get one). Timing is classified from the lyrics text,
never from the source name. Extensions are never consulted for lyrics. Appearance has
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
Full scans extract covers into fresh generations and publish stable filenames only after successful indexing. Cover pruning preserves references from local collections, playback sessions and Insights, holding store writer barriers and passing only a detached private reference projection to native maintenance.
Exact PCM output decodes FLAC through the integer native source; never trust vendor raw
FLAC decoding to preserve source precision or label padded output as source bit depth.
Switch and slider thumbs (AppSwitch, AppSlider, horizontal AppLevelSlider) turn into
Tinted Lite glass (`AppGlassThumb`) only while touched and only when the glass thumb gate
allows it; nothing is painted or read at rest, and the plain controls are the fallback. Seek,
volume and vertical EQ faders keep their painted controls. Only the motion comes from g1455 (the
look stays Sistrum's): the thumb lifts and settles over 180 ms eased out, stretches while it
speeds up and squashes as it brakes (`GlassDropStretchDriver`, none under reduced motion, none for
a tap placing it) and moves in its own `GlassTravel` region; the switch knob travels 220 ms
easeOutCubic and its track colour changes over 160 ms once the value commits. The selection pill
(the floating tab bar and segmented pills) lifts on g1455's tab-bar spring (520/34, a slight
overshoot), slides on its slide spring (380/36) carrying the finger's speed, and stretches the
same way while held.
Sistrum album headers and the immersive player's cover drift slowly (Ken Burns, `AlbumKenBurns`); Appearance > Animated artwork turns it off. A saved video cover (see Video artwork below) replaces that drift on the same cover; the static fallback keeps it. Albums and the player's cover (both Normal and Immersive views) only: playlists, Loved and artist headers stay still. The player's drift pauses while lyrics show. It pauses for reduced motion, glass off or low-end devices, covered routes and a page scrolled past the cover.
Pinned headers float: transparent toolbars with a glass back circle, IconButton and menu actions in
one glass capsule and a backing band only once content scrolls under (opaque on flat level or high
contrast). Header controls (not the player's) are 48dp, 4dp from the edge, with 22dp icons; the
profile photo (opens Settings, rim outline, no glass) ends every header 8dp after the capsule and
is hidden on Settings and its subpages. Headers mirror in RTL. Headers judge known backdrops
(page, artwork top) and never sample themselves.
Glass Engine V2 has four rendering modes, `AppGlassMode` in `AppGlass` (and `AppGlassPanel`,
which wraps it); no other code draws glass: GROUND (a pre-blurred artwork ground, reading no live
backdrop), FROSTED (`BackdropFilter` with `kAppGlassStyle`, sigma 6 and never lower, clipped to the
glass bounds, with a surface tint and a rim), LIQUID (the backdrop refracted through the `g1455`
package's `GlassSurface`, using `kAppLiquidGlassFinish`) and TINT (the fill alone, no sampling).
`AppGlassMode.auto` (the default) picks GROUND over a known artwork ground, TINT where glass is off
(flat level, high contrast, low-end devices, or nested inside other glass) and FROSTED otherwise.
Auto never picks LIQUID: a surface opts in explicitly with `mode: AppGlassMode.liquid`, and only
where `GlassHost` captures its backdrop. An explicit LIQUID over an artwork ground still uses the
ground. An explicit GROUND without a ground falls back to FROSTED. There are no user-facing glass
quality, clarity, lens, shader or Auto measurement settings and no Appearance glass controls; do
not restore them.
LIQUID uses the MIT-licensed `g1455` package (`https://pub.dev/packages/g1455`, pinned in
`pubspec.yaml`). `GlassHost` sits above the navigator in `app.dart` and captures the painted tree
once per change; each liquid surface samples its own slot of that capture. Declare a known, static
backdrop (an artwork ground, a colour, a gradient) with `GlassBackdrop` so no capture is taken. Do
not add other shader packages, `liquid_glass_easy`, or a second glass renderer.
Current LIQUID surfaces: the header back circle and action capsule (`AppHeaderCircle` and
`AppHeaderActions` through `AppChromeControls`), the profile avatar, the bottom bar, the mini player,
the search field, the action buttons, the switch, slider and level-slider thumbs (`AppGlassThumb`)
and the selection pill (`app_selection_pill.dart`). Sheets, menus and dialogs stay FROSTED, or
GROUND when an artwork ground is open; the Artist and Album header band stays FROSTED or GROUND
(see below). Video-covered Artist and Album pages keep their header band and controls FROSTED on
the live backdrop (`AppArtistSurface.liveBackdrop`), because the video is not a host capture; those controls share one backdrop read (`AppLiveVideoBackdrop.backdropKey` through `AppHeaderControls`) and the band keeps its own; once the band is fully shown with its blur the controls are nested glass on it and draw their fill only (`AppLiveVideoBand`). Glass Engine V2 has two looks over the same engine (`AppGlassLook`): BitChord-inspired (a deeper g1455 lens, saturation 1.5 on the frosted blur, a white hairline rim), the default (owner, 2026-11-04), and Sistrum's own. **Owner override (2026-11-04):** the BitChord look only may blur below sigma 6: it uses BitChord's sigma 5 (an 8 dp RenderEffect radius) for FROSTED, LIQUID and the header band; it replaces the fills of light glass (controls, chips, header buttons) with BitChord's 0.4 surface tint (`#121212` dark, `#FAFAFA` light); slabs that hold text or navigation (`strongTint`: menus, sheets, the bottom bar) keep their own opaque fill, as BitChord's menus keep a 0.80 slab, and nested glass keeps its own; and its rim paints a chromatic fringe (warm outside, cool inside, strongest at the corners) because g1455's shader has no dispersion. The Sistrum look keeps sigma 6 and its own fills. Every launch starts in the BitChord look; the developer HUD can switch to Sistrum's for comparison, never persisted; it is not an Appearance control. See `docs/GLASS_ENGINE_V2_PERFORMANCE.md`.
Low-end devices (`lowEndDeviceProvider`) and flat surfaces draw opaque fills. A FROSTED surface
reads its own backdrop with a clipped `BackdropFilter`; there is no adaptive sampling.
Surfaces nested in glass draw only their fill. The performance HUD is a hidden developer option
(seven taps on About's version) and is absent when off; it starts top-left, drags, minimizes to a
pill and its statistics never take touches.
Glass over known artwork (the player's menus and sheets; album and artist header controls, which
opt in through `AppHeaderControls`) reads nothing: it draws a pre-blurred ground image
(`AppPlayerGround`/`AppPageGround`, 384 px wide, at most 6 MB in total, released with their
screen) through `AppArtworkGlassRender`; never a BackdropFilter there. The exception is an artist or album page whose saved video cover is playing: the video covers the photo, so its header controls read the live backdrop (`AppArtistSurface.liveBackdrop`) instead of the photo's ground. Album, playlist and artist
headers soften while scrolling by fading that ground over the artwork (`AppGroundVeil`), never a
live blur. An overlay picks its material once at open (opaque if its ground is not ready). No menu
has a staged glass reveal: page menus keep one material from the first frame too.
Cover colours come from one analysis per cover version (`CoverPalette` -> `appCoverColors`:
bottom/top edge, dominant, harmonized accent; HCT, chroma never above the cover's, AA on-colours;
stored in the library DB's derived `cover_analysis` table). Screens and grounds take every cover
colour from it; never add HSL or second copies of the colour maths.

Audio format conversion is removed entirely: do not restore single-track or batch Convert
menus, format/bitrate/quality sheets, encoding services or converted-file publication.
Keep local tag/cover/lyrics editing and CUE splitting as separate operations. ReplayGain is written
automatically in the background by `ReplayGainAutoWriter`, when its own "Write ReplayGain automatically" setting is on (Library > ReplayGain, with "Only while charging"). Filesystem and SAF songs share the verified path; unavailable identities/permissions fail visibly. Measure missing or known-changed Track tags and complete albums before publishing all pending Track/Album values together in one update per file. An absent saved stamp alone never means a changed file: preserve existing tags on first observation. Keep generation/restart guards, recheck playback/identity immediately before writing, and never mark a failed/deferred album complete. Show phase and written/unchanged/failed/deferred counts; no spinner while disabled. It has no manual Apply/Remove actions in menus or selection bars, no internal ReplayGain removal service, and its write API rejects empty values. Disabling automation preserves existing tags.
Artwork probing and FFmpeg processing for those retained features remain supported.

Tag separators live under Local Library settings as a list of rows: Artists (artist,
album artist, composer), Genre and Keep together, each of the first two opening a sheet with
its chips and Keep together opening a sheet of names that are never split. Each row opens a sheet with a grid of separator chips (four
per row) with defaults (Artists: every chip, so All is on by default), All (selects every chip;
when all are selected it resets to the defaults), and an Add separator field that Save adds; a
section is never empty. There is no Save with group or save-time join: Edit Metadata saves
names as typed. Keep together lists names that are never split; it is the fix for a name a
default chip splits wrongly (for example AC/DC or Malcolm X).
The library reads credits through a derived TEMP table `library_tag_credits` (item_id, field,
name, name_key, position, built by `LibraryTagCreditsCache` from the visible view with the
same rules), so artist and genre pages, search, and the discography shelves agree with the
settings. Track-artist credits make the Artists list and artist pages; album-artist credits make a
separate Album Artists list, placed directly below Artists in the overview. Albums
uses album-artist credits, and Appears On sits directly below Singles for releases where the
artist is credited on a track but owns no track of the release. Go to Artist and Go to Composer
in the song menu open one name directly, or a picker when a credit splits into several names.
Artist detail Albums, Singles and Appears On always use release-tag chronology newest first, independently of global Library Sort. Albums and Singles use separate bounded queries. Featured is the newest owned non-Single release, or the newest owned Single when no album exists, selected independently of shelf paging; its cover is the artist portrait in the detail page, directories and Favorite Artists. Loaded-index changes refresh it automatically. A missing cover on that album stays a placeholder; only artists with neither an owned album nor an owned Single retain their existing fallback picture.

Appearance exposes Player view with Normal view (the default inset artwork) and Immersive
view (the existing full-bleed portrait artwork). Persist the choice across restarts; lyrics,
queue, track changes and mini-player dismissal must work in both views. Landscape retains
the two-column player. Do not restore the obsolete History View/Layout preference or search
entry; the Library overview uses matching category rows and dedicated Library sections
use rows. The overview has no Recently Added album grid. Keep Genres directly below Songs, followed by Loved Songs and Favorite Artists,
with Playlists in its own category. Genres uses bounded local tag queries against the visible
library, with exact tag matching and no online catalog. Songs contains only tracks (including
playlist members), with no collection rows or individual playlists mixed into the list.

Songs, Artists and Album Artists show a persistent Arabic/Latin alphabet rail on the physical right edge. These lists have no inline letter or month/date section headings. Its initial/count projection covers the whole visible category, not just loaded pages, and navigation loads bounded pages on demand. Keep generation/lifecycle guards and current-owner controller attachment. Row revelation reserves space below the pinned toolbar.

Library headers keep a shared Sort control beside the Settings/profile icon on overview and detail routes, except album and artist pages: they have no Sort control; album pages always list tracks by disc, then track number (1 to the last), ignoring the shared order; their More button sits in the header's glass circle. A–Z and Z–A are shared by every Library route, with A–Z as the default. Song/release lists additionally support file size (largest/smallest) when the SQLite file-size inventory is available, and release date (newest/oldest) when the items have release tags. Nonapplicable shared orders fall back to A–Z. Open its sheet on the root navigator so shell chrome cannot obscure its choices. Do not restore Original order, added-date or per-field Library sort options. Albums retain disc groups and artist Popular retains play-count ranking. Collection view sorting never rewrites saved playlist order. Album completeness (assessment, badges and filters) and the Songs Quality/Format/Metadata filter sheet are removed: do not restore them. Home's explicit release-tag Singles classification remains.

Library pages have no search field (search lives in the bottom Search tab). Songs headers show Play/Shuffle, the
player favorite is a heart, Insights (listening statistics) is the tab after Home and records listening always on, with no Record listening toggle, Edit Metadata has no cover resizer, and each
lyric line takes its direction from its first strong letter.

The updater is restored: `UpdateChecker` reads GitHub releases from `AppInfo.githubRepo`, Settings > Updates (above About) holds Check now and the
Check-for-updates and preview-release switches, and `UpdateDialog` downloads the APK (HTTPS, resumable, SHA-256
checked) and hands it to the system installer. The release manifest therefore allows INTERNET (and
REQUEST_INSTALL_PACKAGES with a FileProvider); no other feature may use the network except the user-started lyrics lookup described under
Lyrics settings, the artist photo lookup under Appearance > Download artist images (Apple Music first, Deezer as fallback), and the Apple Music video artwork lookup under Appearance > Download video artwork.

Song taps start local playback; do not restore the separate TrackMetadataScreen/details
route. Song ellipsis menus expose the former local track actions: Play/Share, Play next,
Add to queue, Go to album/artist, Copy file path, Edit Metadata,
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
Play and Tinted Lite glass Shuffle pills with compact sizing and at least 48px touch targets;
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

## Video artwork

Album and artist covers can show a saved, looping, silent Apple Music video (`lib/services/animated_artwork/`, `lib/widgets/animated_artwork/`). The Apple Music catalog is used for two owner-approved things only: saved video artwork and artist photos (see Artist photos below). Nothing else from Apple Music is allowed, and both are owner-approved exceptions to the offline rule above. The catalog interface is unofficial (the web player's developer token), so every response is checked and a failure is reported as unavailable, never as "no video".

- Acquisition and display are separate. The Download video artwork switch (with Wi-Fi, mobile, or both, default Wi-Fi) controls only new background lookups. Turning it off never deletes, hides or stops a saved video. Display follows Appearance > Animated artwork.
- Ownership follows the artist-photo rules: a manual choice always wins and supersedes in-flight automatic work; an automatic result fills only an entity with no record or with a legitimate miss (retried after 14 days); Reset removes the video and blocks automatic replacement until a new manual choice; Clear removes every video and supersedes anything in flight.
- Album identity is title plus album artist (the same key everywhere, including Now Playing). A match needs an identical normalized title and album artist, and a compatible track count and UPC when both are known. Editions never match the standard release. Local tags are never overwritten.
- Downloads are single-file fMP4 HLS only, fetched whole into owned storage, bounded in bytes, frame size and time, validated as MP4, and published only after the database write succeeds. Segmented playlists are unsupported, not concatenated.
- Playback is muted, mixed with other audio (no audio focus), looping, and shows the static cover until the first frame. It pauses when covered, inactive, backgrounded or under reduced motion, and never changes music playback.

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

## Lyrics and artist-image ownership

Failed or empty native metadata reads must stop lyrics embedding. Stage and flush sidecars before publication; separate successful file writes from timing-cache errors. Reload only the still-current song after embedding, using canonical SAF metadata. Lyrics search keeps one parallel request per source, partial results, bounded deadlines and disposal cancellation.

Turning automatic artist downloads off preserves cached photos and display. Automatic publication never replaces an existing manual or Reset record. Clear invalidates in-flight work; store mutations preserve prior files until database publication succeeds. Automatic names use Library Tag separators and Keep together. Publish progress in bounded batches and recheck network policy and ownership after asynchronous boundaries.

Artist photos (owner-approved 2026-11-03): the automatic lookup tries Apple Music's artist artwork first, at 1000 px, and falls back to Deezer when Apple fails or has no portrait for the exact name. A Deezer failure stops the pass; an Apple failure without a match leaves the name unrecorded for a later pass, so a not-found is recorded only when Apple answered. The manual Find artist image sheet searches both sources and labels Apple results. Deezer-only records keep the Deezer id; Apple records store none.
