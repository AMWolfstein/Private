# Split tag credits (artist, album artist, composer, genre)

Goal: a tag such as `artist1, artist2` shows up in the library as two artists, each
with its own page and songs. The same applies to album artist, composer and genre.
The library splits names when it reads them; files change only when the user saves
tags from Edit Metadata.

Executor: follow the phases in order, one code commit per phase. Do not start a
phase until the previous one passes its checks.

## Owner decisions (final)

1. The Artists list includes everyone credited: album artists and track artists
   (featured artists too). On an artist page, releases where the artist only
   appears as a track artist go in a third shelf, **Appears On**, directly below
   Singles.
2. Settings get a **Keep together** list. Any name the user adds is never split
   (`Tyler, The Creator`, `Earth, Wind & Fire`).
3. Genres do not split on `,` by default.
4. The song menu gets **Go to composer**.
5. The Tag separators page has two sections: **Artists** (shared by artist, album
   artist and composer) and **Genre**.
6. Each section shows its separators as chips only, in the Library Filters sheet
   style, four per row in equal cells: **All** first, then the separators, then
   **Add separator**. Selected chips are the separators the library splits on.
   Defaults are selected from the start, tinted with the Appearance accent.
7. Under each grid a **Save with** row picks the single separator used to join
   names when tags are saved from Edit Metadata.
8. Tapping **All** when every chip is already selected returns the section to its
   defaults. A section can never have no separator selected.

## Ground rules

- Do not touch the Rust scanner or the `library` table schema
  (`LibrarySchema.version` stays 20). Split names live in a derived TEMP table that
  Dart rebuilds; a rescan is never needed when the settings change.
- One splitter for every caller, including the save path. Delete the ad-hoc
  splitters it replaces (`libraryGenreTagsSql`, `_artistNameSplitPattern` /
  `splitArtistNames`, the `,`/`;` split in `formatMetadataTagValue`).
- Keys use `sqlite.normalizeLookupText` (the same normalisation as the current
  `album_artist_norm` lookups), so `Amr Diab` and `amr diab` are one artist.
- Persisted keys stay compatible: `metadataSeparators` keeps its four JSON fields
  (`artist`, `album_artist`, `composer`, `genre`); old backups still load.
- Follow AGENTS.md: `flutter analyze` prints `No issues found!`, explicit
  `git add <paths>`, commit order code -> graphify -> docs. `graphify` may be
  missing in the container; if so, say so in the report and skip that commit.
- Run only the tests named in each phase. Do not run the full `flutter test`
  unless the owner asks for it.

## Separators and rules

Two delimiter lists live in settings, one per section.

| Section | Chips offered (in this order) | Selected by default |
|---|---|---|
| Artists | `;` `,` `،` `feat.` `ft.` `featuring` `/` `&` `x` `with` | `;` `,` `،` `feat.` `ft.` `featuring` |
| Genre | `;` `،` `,` `/` `&` | `;` `،` |

- A newline always separates, whether or not it is selected (it has no chip).
- Word delimiters (`feat.`, `ft.`, `featuring`, `x`, `with`, and any added
  separator made of letters) match case-insensitively and only as whole words: no
  letter or digit directly before or after (`Daft Punk feat. Pharrell` splits;
  `Featurette`, `Xavier` and `Lift Up` do not). Symbol delimiters match anywhere.
  For the feat. family, strip wrapping brackets left behind:
  `A (feat. B)` -> `A`, `B`.
- Keep together runs first: every Keep-together name found in the value
  (case-insensitive, whole name) is swapped for a placeholder before splitting
  and restored afterwards with the spelling from the tag. Applies to the Artists
  section only, not genre.
- Trim each part, drop empty parts, de-duplicate by key, and keep first-seen order
  (position 0 is the main credit).
- Album artist: when the tag is empty, use the track artist (as the scanner does
  for `album_artist_norm`).

`List<String> splitTagCredits(String? raw, TagCreditField field, TagCreditRules rules)`

## Phase 1 - settings model and page

Model, new `lib/models/tag_credit_settings.dart`:
- `class TagCreditSettings` with `List<String> artistDelimiters`,
  `List<String> genreDelimiters`, `List<String> keepTogether`; `toJson`/`fromJson`,
  `copyWith`, `==`/`hashCode`.
- Constants `kArtistDelimiterChoices`, `kArtistDelimiterDefaults`,
  `kGenreDelimiterChoices`, `kGenreDelimiterDefaults` from the table above.
- `fromJson`: an empty or missing list falls back to the defaults; trim and
  de-duplicate entries; a delimiter is 1-16 characters with no control
  characters; Keep together entries are trimmed, de-duplicated case-insensitively,
  at most 100 characters each and 200 in total.
- `AppSettings` (`lib/models/settings.dart`) gets
  `final TagCreditSettings tagCredits` (JSON key `tagCredits`, default
  `const TagCreditSettings()`). Regenerate `settings.g.dart` with
  `dart run build_runner build --delete-conflicting-outputs`.

Save separator, `lib/models/metadata_separators.dart`:
- Add `String get names` and `MetadataSeparators withNames(String separator)` that
  writes one value to `artist`, `albumArtist` and `composer`; `genre` stays its own.
- `fromJson`: when the three name fields differ (settings saved before this
  change), use the first non-empty of artist, album artist, composer for all three.

Provider, `lib/providers/settings_provider.dart`:
- `toggleArtistDelimiter(String)`, `toggleGenreDelimiter(String)`,
  `selectAllArtistDelimiters()`, `selectAllGenreDelimiters()` (when everything is
  already selected, reset that section to its defaults),
  `addArtistDelimiter(String)`, `addGenreDelimiter(String)` (adds and selects),
  `removeCustomDelimiter(...)` for user-added ones, `addKeepTogether(String)`,
  `removeKeepTogether(String)`, `setMetadataNamesSeparator(String)`. Toggling off
  the last selected chip does nothing (a section never ends up empty).
- Custom delimiters are stored in the same list as the selected ones plus a
  separate `customArtistDelimiters` / `customGenreDelimiters` list in
  `TagCreditSettings`, so an added chip stays visible when it is deselected.

Page, rewrite `lib/screens/settings/metadata_separator_settings_page.dart` (keep the
`AppSliverHeader.page` header, description text, `NavBarSliverSpacer` and the
current spacing):
- Section **Artists**: `SettingsSectionHeader`, a one-line caption
  "Artist, Album Artist, Composer", then the chip grid, then a `SettingsGroup`
  with one **Save with** row (subtitle = current choice or "Keep source
  formatting") that opens the existing `_SeparatorPicker` sheet and saves through
  `setMetadataNamesSeparator`.
- Section **Genre**: same layout; its Save with row uses
  `setMetadataSeparator('genre', ...)`.
- Section **Keep together**: a short description, one row per name with a delete
  button, and a text field with an Add button.
- Chip grid widget (private to the page): a `LayoutBuilder` that gives every cell
  the same width, `(maxWidth - 3 * 8) / 4`, laid out with `Wrap(spacing: 8,
  runSpacing: 8)` inside 16 px side padding (the `SettingsGroup` inset). Each cell
  is an `AppChoiceChip` (`lib/widgets/primitives/app_choice_chip.dart`, the
  Filters sheet chip) stretched to the cell, label centred and ellipsised.
  Order: **All**, then the section's choices, then its custom delimiters, then
  **Add separator**. All is selected when every chip is selected. Custom chips are
  removed with a long press (confirm with the existing `AppAlertDialog`).
  **Add separator** opens a small `showAppBottomSheet` with one field
  (1-16 characters, same validation as `MetadataSeparators.validSeparator`) and a
  Save button, in the `_SeparatorPicker` layout.
- Show symbols readably on chips: `,` `;` `/` `&` `،` as is; the word delimiters
  as words.
- l10n keys in `lib/l10n/arb/app_en.arb` only: `tagSeparatorsArtists`,
  `tagSeparatorsArtistsFields`, `tagSeparatorsGenre`, `tagSeparatorsAll`,
  `tagSeparatorsAdd`, `tagSeparatorsAddHint`, `tagSeparatorsRemoveTitle`,
  `tagSeparatorsSaveWith`, `tagKeepTogether`, `tagKeepTogetherDescription`,
  `tagKeepTogetherHint`, `tagKeepTogetherAdd`.
- Settings search (`settings_search_catalog.dart`): entries for Tag separators and
  Keep together.

Tests:
- Rewrite `test/metadata_separator_settings_test.dart`: defaults are selected; a
  chip toggles; the last selected chip cannot be turned off; All selects every
  chip and a second tap restores the defaults; Add separator adds a selected chip
  that a long press removes; Save with on Artists sets all three name fields and
  Genre stays independent; Keep together add and remove; four equal cells per row
  at 390 px and 844 px wide.
- Model test (`test/models_and_utils_test.dart` or new): round trip, empty lists
  fall back to defaults, old JSON with three different name separators loads as
  one value.
- `test/settings_bottom_inset_test.dart` if it targets this page.

Commit: `feat(settings): tag separator chips with Save with and Keep together`.

## Phase 2 - splitter, save path and credits table

New file `lib/services/library/library_tag_credits.dart`:
- `enum TagCreditField { artist, albumArtist, composer, genre }` with a stable
  `dbName` (`artist`, `album_artist`, `composer`, `genre`).
- `class TagCreditRules` (artist delimiters, genre delimiters, keep together;
  `==`/`hashCode`), built from `AppSettings.tagCredits`; a
  `tagCreditRulesProvider` selects it from `settingsProvider`.
- `splitTagCredits(...)` as described above, pure Dart, no Flutter imports.
- `class LibraryTagCreditsCache`, modelled on `LibraryGenreTagCache` in
  `library_genres.dart` (serialised `ensure`, one transaction, rebuild only when
  the signature changes):
  - TEMP table `library_tag_credits(item_id TEXT NOT NULL, field TEXT NOT NULL,
    name TEXT NOT NULL, name_key TEXT NOT NULL, position INTEGER NOT NULL)`,
    indexes on `(field, name_key)` and `(item_id)`.
  - `Future<void> ensure(Database db, {required int libraryVersion,
    required TagCreditRules rules})`; signature = version + rules. Rebuild by
    reading `id, artist_name, album_artist, composer, genre` from
    `LibrarySchema.visibleView` in pages of 2000 rows and inserting with a batch.
  - `void invalidate()` for metadata edits.
- One shared instance via a Riverpod provider next to `libraryDatabaseProvider`.

Save path (Edit Metadata):
- `formatMetadataTagValue(value, separator)` becomes
  `formatTagCreditsForSave(value, field, rules, separator)`: split with
  `splitTagCredits`, join with the Save with separator; an empty separator keeps
  the value unchanged.
- `lib/services/library/track_metadata_persistence.dart` and
  `lib/providers/metadata_editor_controller.dart`: format the four fields in Dart
  with the function above and stop adding `MetadataSeparators.writerFields` to the
  writer map, so the Rust writer stores the Dart result as is (otherwise it splits
  again on `,`/`;` and breaks Keep-together names). Leave the Rust code unchanged.
- After a successful save, call `LibraryTagCreditsCache.invalidate()`.

Tests, new `test/library_tag_credits_test.dart`:
- every rule: `AC/DC`, `R&B/Soul`, Arabic comma, newline, `A (feat. B)`,
  `Lift Up` with `with` selected, `x` only as a word, an added letters-only
  separator, duplicates, empty and null input, a deselected `,` keeps
  `A, B` whole;
- Keep together: `Tyler, The Creator, Kali Uchis` -> 2 names; case-insensitive;
  not matched inside a longer word; genre ignores it;
- save: `A, B` with Save with `; ` -> `A; B`; a Keep-together name survives;
  empty Save with keeps the value; the writer map has no `*_separator` keys;
- cache with an in-memory sqflite DB (see `test/library_genres_test.dart`): one row
  per credit; a new version or new rules rebuilds; an unchanged signature does not.
- Update the tests that covered `formatMetadataTagValue` and `writerFields`
  (`grep -rln "formatMetadataTagValue\|writerFields" test`).

Commit: `feat(library): split tag credits for the library and saving`.

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
  `test/local_genres_screen_test.dart`; add a case where selecting `/` for Genre
  splits `Hip-Hop/Rap` and the default keeps it whole.

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
  with `field = 'album_artist'` only. Keep the Singles rule (explicit total-tracks
  tag of 1) and release-date ordering.
- **Appears On** shelf (`local_artist_screen.dart`), directly below Singles:
  releases where some track has an `artist` credit with that key and no track of
  the release has an `album_artist` credit with that key. Same album cards,
  release-date order and swipe-to-load-more paging as the other discography
  shelves; hidden when empty; no Show-more control. l10n key `artistAppearsOn`.
- Popular stays capped at 20 and ranked by play counts; full-artist playback plays
  every credited song.
- `library_search.dart`: artist results come from the same credits, so `artist2`
  is findable on its own.
- Tests: update `test/app_library_browse_test.dart` and the local artist screen
  tests (`grep -l local_artist test/`). Add: a track tagged `A, B` lists both A and
  B; a featured-only artist C (`Song feat. C`) is listed and C's page shows the
  release under Appears On, not under Albums or Singles; A's Albums shelf has the
  release.

Commit: `feat(library): artists split on credits with Appears On`.

## Phase 5 - opening an artist from a song

- `lib/navigation/detail_navigation.dart`: `navigateToArtistCredits` uses
  `splitTagCredits(raw, TagCreditField.artist, rules)`. One name opens that artist;
  several names open a small `showAppBottomSheet` listing each name; tapping one
  opens `local_artist_screen.dart`. Remove the `getBrowseArtistRows` exact-match
  lookup and `splitArtistNames` with its tests in `test/artist_utils_test.dart`.
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

- `metadataSeparatorsDescription` (app_en.arb): selected separators split names in
  the library; Save with joins them when tags are saved; Keep together names are
  never split.
- AGENTS.md: replace "There is no read-side tag splitting: tags are shown as
  stored." and the "Per-field tag separators" sentence with: the two sections and
  chip grid (All, defaults, Add separator, never empty, All resets), Save with,
  Keep together, the rules table summary, the derived TEMP table, Appears On below
  Singles, the artist picker, and Go to composer in the song-menu action list.
- `graphify update .` and its commit if graphify is installed.

Commits: `chore(graphify): refresh code graph after tag credits`, then
`docs: record split tag credits`.
