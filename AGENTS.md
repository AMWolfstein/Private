## Migration status

This repo is being converted to a local/offline Android-only music player.
**Read `LOCAL_OFFLINE_MIGRATION_PLAN.md` (esp. `## Progress`) and `git log --oneline -10`
before continuing any migration work.**

The app targets Android and local files only. Mornye is its sole production theme; keep
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

Detailed logging is the first option in Logs; there is no separate App settings page.
Lyrics settings do not contain Embed lyrics or its output-mode submenu/preferences.
Local lyrics reading and per-file metadata/lyrics editing remain supported. Appearance has
no decorative Library preview card. Settings and Library subpages reuse the album header's
circular back button in Mornye.

Settings no longer include the obsolete output-folder Files & Folders page or the
download-era Metadata page. Music scanning stays under Local Library; local per-file tag
editing remains supported. Per-field tag separators (artist, album artist, composer, genre;
empty keeps the tag) live under Local Library settings as Tag separators and apply when local
tags are saved; do not restore Artist Tag Mode UI. Local Library settings have no Default view or Audio quality
label-mode options: do not restore their preferences, pickers, search entries or tab-reset
behavior. Library badges use the standard measured/stored bitrate policy, with codec
fallback for legacy lossy files. Audio playback uses only the built-in player, including on old
settings imports: do not restore player-mode choices, external-player shortcuts or automatic
external fallback on initialization failure. Keep USB/output-device controls and DSP settings.
Exact PCM output decodes FLAC through the integer native source; never trust vendor raw
FLAC decoding to preserve source precision or label padded output as source bit depth.

Audio format conversion is removed entirely: do not restore single-track or batch Convert
menus, format/bitrate/quality sheets, encoding services or converted-file publication.
Keep local tag/cover/lyrics editing, ReplayGain and CUE splitting as separate operations.
Artwork probing and FFmpeg processing for those retained features remain supported.

Tag separators (artist, album artist, composer, genre) live under Local Library settings and
apply only when local tags are saved via Edit Metadata; do not restore the download-era
Metadata page or Artist Tag Mode UI for them.

Appearance exposes Player view with Normal view (the default inset artwork) and Immersive
view (the existing full-bleed portrait artwork). Persist the choice across restarts; lyrics,
queue, track changes and mini-player dismissal must work in both views. Landscape retains
the two-column player. Do not restore the obsolete History View/Layout preference or search
entry; the Library overview uses matching category rows and dedicated Library sections
use rows. The overview has no Recently Added album grid. Keep Genres directly below Songs, followed by Loved Songs and Favorite Artists,
with Playlists in its own category. Genres uses bounded local tag queries against the visible
library, with exact tag matching and no online catalog. Songs contains only tracks (including
playlist members), with no collection rows or individual playlists mixed into the list.

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

First-run setup and the local-player guide form one flow. Keep language choice, local
playback tips and permission checks under the same page counter and Back/Next navigation.
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
   (the only accepted failure is the known-flaky `test/library_browse_sqlite_paging_test.dart`).
4. **Commit** — in the order below.

## Code review

Review rules, finding format and state live in `reviews/PROTOCOL.md`; resume from
`reviews/STATE.md`. Claude Code: `/review [range]` (incremental, default 1 reviewer, max 3)
and `/audit <subsystem>` (one bounded subsystem); reviewer agents are in `.claude/agents/`.
Codex/OpenCode: act as one named reviewer from `.claude/agents/<name>.md` per pass.
`scripts/review_scope.sh` picks scope, reviewers and graph freshness without a model.
Reviewers never edit code; fixes are separate 1–3 finding batches that follow the commit
conventions below. Review checkpoints commit only `reviews/` (`docs(review): <unit>`).

## Upstream ports

Synced lyrics suspend hidden/background work and settled word tickers; line changes use the lyric spring with reduced-motion support, while scrubbing stays quick and manual scrolling keeps its anchor.

Upstream is `mornyeapp/Mornye` (renamed SpotiFLAC-Mobile). Ports follow `reviews/PORT_PLAN.md`
(setup, rules, batch order, testing once per batch) with specs in `reviews/UPSTREAM.md`. Never
port renaming or branding.

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
