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
Do not replace the feed with only the recent-access history list.

Settings no longer include the obsolete output-folder Files & Folders page or the
download-era Metadata page. Music scanning stays under Local Library; local per-file tag
editing remains supported. Audio playback uses only the built-in player, including on old
settings imports: do not restore player-mode choices, external-player shortcuts or automatic
external fallback on initialization failure. Keep USB/output-device controls and DSP settings.

Audio format conversion is removed entirely: do not restore single-track or batch Convert
menus, format/bitrate/quality sheets, encoding services or converted-file publication.
Keep local tag/cover/lyrics editing, ReplayGain and CUE splitting as separate operations.
Artwork probing and FFmpeg processing for those retained features remain supported.

Appearance exposes Player view with Normal view (the default inset artwork) and Immersive
view (the existing full-bleed portrait artwork). Persist the choice across restarts; lyrics,
queue, track changes and mini-player dismissal must work in both views. Landscape retains
the two-column player. Do not restore the obsolete History View/Layout preference or search
entry; the Library overview uses cards and dedicated Library sections use rows.

Album-style collection headers (albums, playlists, Loved and Wishlist) use one centered
row ordered left to right: Loved, Play/Pause, Shuffle, Add to playlist. Reuse the filled
Play and translucent Shuffle pills with compact sizing and at least 48px touch targets;
keep the outer icons in the same row, including RTL. Do not move Shuffle into the toolbar.
The artist header retains its separate centered-Play design.

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
