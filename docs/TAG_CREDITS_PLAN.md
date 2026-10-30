# Split tag credits (artist, album artist, composer, genre)

Goal: a tag such as `artist1, artist2` shows up in the library as two artists, each
with its own page and songs. The same applies to album artist, composer and genre.
Files are never rewritten by this feature; splitting happens when the library is read.

Executor: follow the phases in order, one code commit per phase. Do not start a
phase until the previous one passes its checks.

## Owner decisions (final)

1. The Artists list includes everyone credited: album artists and track artists
   (featured artists too). On an artist page, releases where the artist only
   appears as a track artist go in a third shelf, **Appears On**, directly below
   Singles.
2. Settings get a **Keep together** list now. Any name the user adds there is never
   split (`Tyler, The Creator`, `Earth, Wind & Fire`).
3. Genres do not split on `,`.
4. The song menu gets **Go to composer**.
5. The Tag separators page has two rows instead of four: **Artists** (one value
   shared by artist, album artist and composer) and **Genre**.

## Ground rules

- Do not touch the Rust scanner (`rust_backend/`) or the `library` table schema
  (`LibrarySchema.version` stays 20). Split names live in a derived TEMP table
  that Dart rebuilds; a rescan is never needed when the rules change.
- One splitter for every caller. Delete the ad-hoc splitters it replaces
  (`libraryGenreTagsSql`, `_artistNameSplitPattern`/`splitArtistNames`).
- Keys use `sqlite.normalizeLookupText` (the same normalisation as the current
  `album_artist_norm` lookups), so `Amr Diab` and `amr diab` are one artist.
- Persisted keys stay compatible: `metadataSeparators` keeps its four JSON fields
  (`artist`, `album_artist`, `composer`, `genre`) so old backups and the Rust
  writer keep working. Only the UI and the model's setters merge them.
- Follow AGENTS.md: `flutter analyze` prints `No issues found!`, explicit
  `git add <paths>`, commit order code -> graphify -> docs. `graphify` may be
  missing in the container; if so, say so in the report and skip that commit.
- Run only the tests named in each phase. Do not run the full `flutter test`
  unless the owner asks for it.

## Splitting rules

`List<String> splitTagCredits(String? raw, TagCreditField field, {String userSeparator = '', List<String> keepTogether = const []})`

| Field | Splits on | Never splits on |
|---|---|---|
| artist | `;` `,` `،` newline, word-delimited `feat.` `ft.` `featuring`, the Artists separator | `&` `/` `x` `and` `with` |
| albumArtist | `;` `,` `،` newline, the Artists separator | same as artist, and no `feat.` |
| composer | `;` `,` `،` newline, the Artists separator | `&` `/` `and` |
| genre | `;` `،` newline, the Genre separator | `,` `/` `&` (R&B/Soul, Hip-Hop/Rap stay whole) |

- Keep together first: every Keep-together name found in `raw` (case-insensitive,
  whole name: not preceded or followed by a letter or digit) is swapped for a
  placeholder before splitting and restored afterwards, using the user's spelling
  from the tag. It applies to artist, album artist and composer, not genre.
- `userSeparator` comes from settings (Phase 1): the Artists value for the three
  name fields, the Genre value for genre. Empty means no extra delimiter. Match it
  literally (escape it for RegExp) and trim spaces around it.
- `feat.` family: case-insensitive, matched only as a whole word with whitespace
  before it (`Daft Punk feat. Pharrell` splits, `Featurette` does not). Strip
  wrapping brackets left behind: `A (feat. B)` -> `A`, `B`.
- Trim each part, drop empty parts, de-duplicate by key, keep first-seen order
  (position 0 is the main credit).
- Album artist: when the tag is empty, use the track artist (matches what the
  scanner stores in `album_artist_norm`).

## Phase 1 - settings: two separators and Keep together

Model, `lib/models/metadata_separators.dart`:
- Add `String get names` (the shared Artists value) and
  `MetadataSeparators withNames(String separator)` that writes the same value to
  `artist`, `albumArtist` and `composer`. Keep `genre` and `withField` for genre.
- `fromJson`: when the three name fields differ (settings saved before this
  change), use the first non-empty of artist, album artist, composer for all three.
- `writerFields` and the Rust writer are unchanged.

Keep together, `lib/models/settings.dart`:
- New field `final List<String> tagKeepTogether` (JSON key `tagKeepTogether`,
  default empty). Regenerate `settings.g.dart` with
  `dart run build_runner build --delete-conflicting-outputs`.
- `fromJson` drops blank entries, trims, de-duplicates case-insensitively, and
  caps each entry at 100 characters and the list at 200 entries.
- `settings_provider.dart`: `setMetadataNamesSeparator(String)`,
  `addTagKeepTogether(String)`, `removeTagKeepTogether(String)`.

UI, `lib/screens/settings/metadata_separator_settings_page.dart`:
- Two rows: **Artists** (subtitle: "Artist, Album Artist, Composer" plus the
  preview of the current choice) and **Genre**. Both open the existing
  `_SeparatorPicker`; Artists saves through `setMetadataNamesSeparator`.
- Below them a **Keep together** section: a short explanation, one row per name
  with a delete button, and a text field with an Add button. Reuse
  `SettingsSectionHeader`, `SettingsGroup` and the existing row widgets; match the
  page's current look.
- l10n keys in `lib/l10n/arb/app_en.arb` only (`tagSeparatorsArtists`,
  `tagSeparatorsArtistsFields`, `tagKeepTogether`, `tagKeepTogetherDescription`,
  `tagKeepTogetherHint`, `tagKeepTogetherAdd`, `tagKeepTogetherRemove`).
- Settings search (`settings_search_catalog.dart`): one entry for Keep together.

Tests:
- `test/metadata_separator_settings_test.dart`: rewrite for two rows. Saving
  Artists sets all three fields; Genre stays independent; dismissing the sheet
  keeps the saved value; adding and removing a Keep-together name.
- `test/models_and_utils_test.dart` (or a new model test): old JSON with three
  different name separators loads as one value; `tagKeepTogether` round-trips and
  is cleaned.
- `test/settings_bottom_inset_test.dart` if it targets this page.

Commit: `feat(settings): merge name tag separators and add Keep together`.

## Phase 2 - splitter and credits table

New file `lib/services/library/library_tag_credits.dart`:

- `enum TagCreditField { artist, albumArtist, composer, genre }` with a stable
  `dbName` (`artist`, `album_artist`, `composer`, `genre`).
- `splitTagCredits(...)` as described above, pure Dart, no Flutter imports.
- `class TagCreditRules` holding `namesSeparator`, `genreSeparator` and
  `keepTogether`, with `==`/`hashCode`, built from `AppSettings`.
- `class LibraryTagCreditsCache`, modelled on `LibraryGenreTagCache` in
  `library_genres.dart` (serialised `ensure`, one transaction, rebuild only when
  the signature changes):
  - TEMP table `library_tag_credits(item_id TEXT NOT NULL, field TEXT NOT NULL,
    name TEXT NOT NULL, name_key TEXT NOT NULL, position INTEGER NOT NULL)`,
    indexes on `(field, name_key)` and `(item_id)`.
  - `Future<void> ensure(Database db, {required int libraryVersion,
    required TagCreditRules rules})`. Signature = `libraryVersion` + `rules`.
    Rebuild by reading `id, artist_name, album_artist, composer, genre` from
    `LibrarySchema.visibleView` in pages of 2000 rows, inserting with a batch.
  - `void invalidate()` for callers that change rows without a scan (metadata
    edits).
- One shared instance via a Riverpod provider next to `libraryDatabaseProvider`,
  plus `tagCreditRulesProvider` that selects the rules from `settingsProvider`.

Tests, new `test/library_tag_credits_test.dart`:
- every row of the rules table: `AC/DC`, `R&B/Soul`, Arabic comma, newline,
  `A (feat. B)`, separator ` | `, duplicates, empty and null input;
- Keep together: `Tyler, The Creator, Kali Uchis` with `Tyler, The Creator` kept
  -> 2 names; case-insensitive match; a kept name inside a longer word is not
  matched; genre ignores the list;
- cache: in-memory sqflite DB (see `test/library_genres_test.dart` for setup). One
  row per credit; a new version, separator or Keep-together list rebuilds, an
  unchanged signature does not.

Commit: `feat(library): split tag credits into a derived table`.

## Phase 3 - genres use the credits table

- `library_genres.dart`: `LibraryGenres` takes the shared cache and the rules. The
  genre list is `SELECT name_key AS genre_key, MIN(name) AS name,
  COUNT(DISTINCT item_id) AS track_count FROM library_tag_credits
  WHERE field = 'genre' GROUP BY name_key ORDER BY name_key`. Genre songs use
  `l.id IN (SELECT item_id FROM library_tag_credits WHERE field = 'genre' AND
  name_key = ?)`. Delete `libraryGenreTagsSql` and `LibraryGenreTagCache`.
- `local_genres_screen.dart`: `genrePageLoaderProvider` watches
  `tagCreditRulesProvider` and the shared cache.
- Tests: update `test/library_genres_test.dart` and
  `test/local_genres_screen_test.dart`; add a case where Genre separator `/` splits
  `Hip-Hop/Rap` and the default keeps it whole.

Commit: `feat(library): genres read split credits`.

## Phase 4 - Artists list, artist page, Appears On, artist picture

In `library_browse_store.dart`, `LibraryDatabase` and their callers (ensure the
cache before each query below):

- `artistPage`: list credits with `field IN ('album_artist', 'artist')` grouped by
  `name_key` (`MIN(name)` for display, `COUNT(DISTINCT item_id)` for the count,
  search on `name_key LIKE ?`). Cover: the newest `cover_path` (by `sort_added`)
  among the artist's credited songs with artwork, per the AGENTS.md rule.
- `_appendBrowseLocalFilters` (`request.albumArtist`): replace
  `l.album_artist_norm = ?` with `l.id IN (SELECT item_id FROM
  library_tag_credits WHERE field IN ('album_artist', 'artist') AND name_key = ?)`,
  so the artist page lists their own songs and songs they are featured on.
- Albums and Singles shelves: a release belongs to the artist when any of its
  tracks has an `album_artist` credit with that key. Find the album query used by
  `local_artist_screen.dart` / `local_artist_providers.dart` and apply the filter
  with `field = 'album_artist'` only. Keep the existing Singles rule (explicit
  total-tracks tag of 1) and release-date ordering.
- **Appears On** shelf (`local_artist_screen.dart`), directly below Singles:
  releases where some track has an `artist` credit with that key and no track of
  the release has an `album_artist` credit with that key. Same album cards,
  release-date order, and swipe-to-load-more paging as the other discography
  shelves; hidden when empty; no Show-more control. l10n key `artistAppearsOn`.
- Popular stays capped at 20 and ranked by play counts; full-artist playback
  plays every credited song.
- `library_search.dart`: artist results come from the same credits, so `artist2`
  is findable on its own.
- Tests: update `test/app_library_browse_test.dart` and the local artist screen
  tests (`grep -l local_artist test/`). Add: a track tagged `A, B` lists both A
  and B; a featured-only artist C (`Song feat. C`) is listed, C's page shows the
  release under Appears On and not under Albums or Singles; A's Albums shelf has
  the release.

Commit: `feat(library): artists split on credits with Appears On`.

## Phase 5 - opening an artist from a song

- `lib/navigation/detail_navigation.dart`: `navigateToArtistCredits` uses
  `splitTagCredits(raw, TagCreditField.artist, ...)` with the current rules. One
  name opens that artist; several names open a small `showAppBottomSheet` listing
  each name; tapping one opens `local_artist_screen.dart`. Remove the
  `getBrowseArtistRows` exact-match lookup and `splitArtistNames` with its tests
  in `test/artist_utils_test.dart`.
- Callers: `grep -rn navigateToArtistCredits lib` (song menu, player, headers).
- Test: a song tagged `A, B` -> Go to artist shows a sheet with A and B; picking B
  opens B's page. With `A, B` in Keep together it opens `A, B` directly.

Commit: `feat(library): choose an artist from split credits`.

## Phase 6 - composers

- A query for a composer's songs (`field = 'composer'`), like the genre songs.
- A composer songs screen: generalise `LocalGenresScreen` to take a
  `TagCreditField` rather than copying it.
- Song ellipsis menu: **Go to composer** after Go to artist, shown only when the
  song has a composer; several composers use the Phase 5 picker sheet.
  l10n key `actionGoToComposer`.
- Tests: hidden without a composer; opens the chosen composer's songs.

Commit: `feat(library): browse songs by composer`.

## Phase 7 - docs and wording

- `metadataSeparatorsDescription` (app_en.arb): the chosen separators are used
  when saving tags and to split names in the library; Keep together names are
  never split.
- AGENTS.md: replace "There is no read-side tag splitting: tags are shown as
  stored." with: the rules table summary, the two separator rows, Keep together,
  the derived TEMP table, Appears On below Singles, the artist picker, and Go to
  composer in the song-menu action list. Update the earlier "Per-field tag
  separators" sentence to describe the two rows.
- `graphify update .` and its commit if graphify is installed.

Commits: `chore(graphify): refresh code graph after tag credits`, then
`docs: record split tag credits`.
