# Library sorting and filter removal

The owner clarified that the control to retain is **Sort**. Album completeness and the former Songs filter sheet are removed.

## Behavior

Library headers expose the same Sort icon immediately before the Settings/profile button, including the overview, Albums, Artists, Album Artists, Songs, Genres/composer songs, playlists, Loved Songs, Favorite Artists, album details and artist details. The existing header actions share their glass capsule. Its two-row sheet opens above shell chrome through the root navigator.

The selected order is shared across Library routes for the current session. Every page offers exactly **A–Z** and **Z–A**, using the displayed item name, with **A–Z** as the default. Original order, date, size and per-field ordering choices were removed from the Library menu at the owner's request. Home and Search keep their own ordering.

Songs starts alphabetically, so its letter rail is visible on first opening. Album detail sorting stays within disc groups, while header genre/year come from source metadata independently of display order. Artist Popular keeps its play-count ranking. Collection sorting operates on copied display lists; manual playlist reordering uses the saved order. Sort changes reset Songs pagination/selection. A pending Play-all read uses one order snapshot and stops if the user changes it.

Album, artist and genre queries apply the shared alphabetical direction before their page limits. In-memory collections sort copied display rows with stable identity ties.

## Removed components

- Album completeness sheet, badges, row model, request field, inventory assessment SQL and dedicated service.
- Songs Quality, Format and Metadata filter sheet, selection state and query/cache plumbing.
- Obsolete localization keys in every locale and tests exclusive to the removed features.

Release metadata still classifies Home Singles and Albums. Ordinary album track-count badges remain.

## Verification

The final full Flutter suite passed **2,445 tests**, with **3 skipped** and no failures (5m51s); analysis reported no issues. Focused checks passed: 19 UI/navigation tests, 17 playback/selection tests and 7 browse/modal tests. They cover the two-option menu above nested-navigation shell chrome, default Songs rail visibility, side-only letters, off-page jumps, stable album header metadata and alphabetical queue order.

An initial complete run exposed header tags tied to the first sorted row. Header metadata was separated from display order; playlist expectations and scroll targets were updated for alphabetical rows, and the complete suite was rerun successfully. Graph `8f74a2d0` contains 29,363 unique nodes and 56,023 links with no dangling endpoints; existing extraction limitations remain.

No native source changes, APK build or device execution were performed for this correction.
