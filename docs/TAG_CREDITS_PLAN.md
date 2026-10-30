# Split tag credits (artist, album artist, composer, genre)

Goal: a tag such as `artist1, artist2` shows up in the library as two artists, each
with its own page and songs. The same applies to album artist, composer and genre.
Files are never rewritten; splitting happens only when the library is read.

Executor: follow the phases in order, one code commit per phase. Do not start a
phase until the previous one passes its checks.

## Ground rules

- Do not touch the Rust scanner (`rust_backend/`) or the `library` table schema
  (`LibrarySchema.version` stays 20). Split names live in a derived TEMP table
  that Dart rebuilds; a rescan is never needed when the rules change.
- One splitter for every caller. Delete the old ad-hoc splitters it replaces
  (`libraryGenreTagsSql`, `_artistNameSplitPattern`/`splitArtistNames`).
- Keys use `sqlite.normalizeLookupText` (the same normalisation as
  `album_artist_norm` lookups today), so `Amr Diab` and `amr diab` are one artist.
- Follow AGENTS.md: `flutter analyze` prints `No issues found!`, explicit
  `git add <paths>`, commit order code -> graphify -> docs. `graphify` may be
  missing in the container; if so, say so in the report and skip that commit.
- Run only the tests named in each phase. Do not run the full `flutter test`
  unless the owner asks for it.

## Splitting rules (Phase 1)

`List<String> splitTagCredits(String? raw, TagCreditField field, {String userSeparator = ''})`

| Field | Splits on | Never splits on |
|---|---|---|
| artist | `;` `,` `،` newline, word-delimited `feat.` `ft.` `featuring`, the user separator | `&` `/` `x` `and` `with` |
| albumArtist | `;` `,` `،` newline, the user separator | same as artist, and no `feat.` |
| composer | `;` `,` `،` newline, the user separator | `&` `/` `and` |
| genre | `;` `،` newline, the user separator | `,` `/` `&` (R&B/Soul, Hip-Hop/Rap stay whole) |

- `userSeparator` is that field's value in `AppSettings.metadataSeparators`
  (Settings > Local Library > Tag separators). What you save with is what the
  library reads with. Empty means no extra delimiter. Match it literally (escape it
  for RegExp), and trim spaces around it.
- `feat.` family: case-insensitive, matched only as a whole word with whitespace
  before it (`Daft Punk feat. Pharrell` splits, `Featurette` does not). Strip
  wrapping brackets left behind: `A (feat. B)` -> `A`, `B`.
- Trim each part, drop empty parts, de-duplicate by key, and keep the first-seen
  order (position 0 is the main credit).
- Album artist: when the tag is empty, use the track artist (matches what the
  scanner stores in `album_artist_norm`).

## Phase 1 - splitter and credits table

New file `lib/services/library/library_tag_credits.dart`:

- `enum TagCreditField { artist, albumArtist, composer, genre }` with a stable
  `dbName` (`artist`, `album_artist`, `composer`, `genre`).
- `splitTagCredits(...)` as above, pure Dart, no Flutter imports.
- `class LibraryTagCreditsCache`, modelled on `LibraryGenreTagCache` in
  `library_genres.dart` (serialised `ensure`, one transaction, rebuild only when
  the signature changes):
  - TEMP table `library_tag_credits(item_id TEXT NOT NULL, field TEXT NOT NULL,
    name TEXT NOT NULL, name_key TEXT NOT NULL, position INTEGER NOT NULL)`, with
    indexes on `(field, name_key)` and `(item_id)`.
  - `Future<void> ensure(Database db, {required int libraryVersion,
    required MetadataSeparators separators})`. The signature is
    `libraryVersion` plus the four separator values. Rebuild by reading
    `id, artist_name, album_artist, composer, genre` from
    `LibrarySchema.visibleView` in pages of 2000 rows and inserting with a batch.
  - `void invalidate()` for callers that change rows without a scan.
- One shared instance: a Riverpod `Provider<LibraryTagCreditsCache>` in
  `lib/providers/library_database_provider.dart` (or next to it), so every screen
  shares one table.

Tests, new `test/library_tag_credits_test.dart`:
- every row of the rules table, including `Tyler, The Creator` -> 2 names
  (documented limitation), `AC/DC`, `R&B/Soul`, Arabic comma, newline,
  `A (feat. B)`, user separator ` | `, duplicates, empty and null input;
- cache test with an in-memory sqflite DB (see `test/library_genres_test.dart` for
  setup): the table holds one row per credit, and changing the version or a
  separator rebuilds it while an unchanged signature does not.

Commit: `feat(library): split tag credits into a derived table`.

## Phase 2 - genres use the credits table

- `library_genres.dart`: `LibraryGenres` takes the shared
  `LibraryTagCreditsCache` plus `separators`; the genre list is
  `SELECT name_key AS genre_key, MIN(name) AS name, COUNT(DISTINCT item_id)
  AS track_count FROM library_tag_credits WHERE field = 'genre' GROUP BY name_key`.
  Genre songs use `l.id IN (SELECT item_id FROM library_tag_credits WHERE
  field = 'genre' AND name_key = ?)`. Delete `libraryGenreTagsSql` and
  `LibraryGenreTagCache`.
- `local_genres_screen.dart`: `genrePageLoaderProvider` watches
  `settingsProvider.select((s) => s.metadataSeparators)` and the shared cache.
- Tests: update `test/library_genres_test.dart` and
  `test/local_genres_screen_test.dart`. Add a case where a genre separator from
  settings (`/`) splits `Hip-Hop/Rap` and the default keeps it whole.

Commit: `feat(library): genres read split credits`.

## Phase 3 - artists list, artist page, artist picture

In `library_browse_store.dart`, `LibraryDatabase` and their callers (ensure the
cache before each query below; the request already carries enough to find
`loadedIndexVersion` through the providers that call it):

- `artistPage`: list `field = 'album_artist'` credits grouped by `name_key`
  (`MIN(name)` for display, `COUNT(DISTINCT item_id)` for the count, search on
  `name_key LIKE ?`). The cover subquery picks the newest `cover_path` among
  `item_id`s credited to that key (keep the "most recently added song with
  artwork" rule from AGENTS.md).
- `_appendBrowseLocalFilters` (`request.albumArtist`): replace
  `l.album_artist_norm = ?` with
  `l.id IN (SELECT item_id FROM library_tag_credits WHERE field IN
  ('album_artist', 'artist') AND name_key = ?)`. The artist page then lists the
  artist's own songs and songs where they are featured.
- Albums on the artist page: an album belongs to the artist when any of its
  tracks has an `album_artist` credit with that key. Find the album query used by
  `local_artist_screen.dart` / `local_artist_providers.dart` and apply the same
  `IN (...)` filter with `field = 'album_artist'` only.
- `localArtistCoverProvider` keeps working through the filtered track page.
- Popular (play counts) and full-artist playback need no change beyond the
  filter; check that the Popular cap (20) still holds.
- `library_search.dart`: artist results come from `album_artist` credits as
  above, so `artist2` is findable on its own.
- Tests: update `test/app_library_browse_test.dart` and the local artist screen
  tests (`grep -l local_artist test/`). Add: a track tagged `A, B` shows under
  both A and B in the Artists list, A's page lists it, and A's album shelf
  contains its album.

Commit: `feat(library): artists split on credits`.

## Phase 4 - opening an artist from a song

- `lib/navigation/detail_navigation.dart`: `navigateToArtistCredits` uses
  `splitTagCredits(raw, TagCreditField.artist, userSeparator: ...)`. One name
  opens that artist. Several names open a small `showAppBottomSheet` that lists
  each name (rows like the Library settings rows); tapping one opens
  `local_artist_screen.dart`. Remove the `getBrowseArtistRows` exact-match lookup
  and `splitArtistNames` with its tests in `test/artist_utils_test.dart`.
- Callers: `local_song_menu.dart` (Go to artist), clickable artist names in the
  player and headers (`grep -rn navigateToArtistCredits lib`).
- Test: a song tagged `A, B` -> Go to artist shows a sheet with A and B; picking B
  opens B's page.

Commit: `feat(library): choose an artist from split credits`.

## Phase 5 - composers

Composer has no browse view today. Add the smallest one:

- `LibraryTagCredits.page(field: composer, name: ..., offset, limit)` returning
  tracks, like the genre songs query.
- A composer songs screen that reuses `LocalGenresScreen`'s song-list layout.
  Prefer generalising that screen to take a `TagCreditField` over copying it.
- Entry point: a "Go to composer" item in the song ellipsis menu, shown only when
  the song has a composer; several composers show the same picker sheet as
  Phase 4. Add the l10n keys to `lib/l10n/arb/app_en.arb` only.
- Tests: the menu item is hidden without a composer, and opens the songs of the
  chosen composer.

Commit: `feat(library): browse songs by composer`.

## Phase 6 - docs and wording

- `metadataSeparatorsDescription` (app_en.arb): say that the chosen separator is
  also used to split names in the library.
- AGENTS.md: replace "There is no read-side tag splitting: tags are shown as
  stored." with the rules table summary, the derived TEMP table, and the
  Phase 4/5 entry points. Mention the new "Go to composer" action in the
  song-menu list.
- `graphify update .` and its commit if graphify is installed.

Commits: `chore(graphify): refresh code graph after tag credits`, then
`docs: record split tag credits`.

## Decisions for the owner (defaults used if no answer)

1. Artists list shows album-artist credits only, so featured artists get pages
   but are not listed. Alternative: list track-artist credits too. Default: album
   artist only.
2. Comma splits artist names, so `Tyler, The Creator` becomes two names. A
   "keep together" list could fix that later. Default: accept it.
3. Genres do not split on `,`. Default: keep.
4. "Go to composer" is a new song-menu action. Default: add it.
