# Library sorting and filter removal

The owner clarified that the control to retain is **Sort**. Album completeness and the former Songs filter sheet are removed.

## Behavior

Library headers expose the same Sort icon immediately before the Settings/profile button, including the overview, Albums, Artists, Album Artists, Songs, Genres/composer songs, playlists, Loved Songs, Favorite Artists, album details and artist details. The existing header actions share their glass capsule.

The selected order is shared across Library routes for the current session. Each page offers applicable choices; unsupported choices use that page's default. Original order clears the session override. Existing defaults remain: alphabetical browse lists, recently added Songs, release chronology on artist shelves, tagged disc/track order in albums and stored collection order. Home and Search keep their own ordering.

Songs retains sorting choices independently of its removed filters. Album detail sorting stays within disc groups. Artist Popular keeps its play-count ranking. Collection sorting operates on copied display lists; manual playlist reordering uses the saved order. Sort changes reset Songs pagination/selection. A pending Play-all read uses one order snapshot and stops if the user changes it.

Album, artist and genre queries sort before their page limits. Artist ordering supports alphabetical and added-date directions with stable name ties; genres support reverse-name pages and their songs use applicable metadata/date orders.

## Removed components

- Album completeness sheet, badges, row model, request field, inventory assessment SQL and dedicated service.
- Songs Quality, Format and Metadata filter sheet, selection state and query/cache plumbing.
- Obsolete localization keys in every locale and tests exclusive to the removed features.

Release metadata still classifies Home Singles and Albums. Ordinary album track-count badges remain.

## Verification

The focused Flutter suite passed 38 tests, including actual SQLite ordering before page limits, header controls without retired options, light/dark browse navigation, enlarged detail layouts and original disc ordering. The complete suite passed **2,438 tests**, with **3 skipped** and no failures (6m09s); `flutter analyze` reported no issues. Graph `5a433b5b` contains 29,323 unique nodes and 55,949 links with no dangling endpoints. Existing extractor limitations remain.

An initial focused run exposed a listener registered from a nested album Builder; it was moved into the Consumer build, and the focused suite was rerun successfully. No native source changes, APK build or device execution were performed.
