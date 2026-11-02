# Library sorting and filter removal

The owner clarified that the control to retain is **Sort**. Album completeness and the former Songs filter sheet are removed.

## Behavior

Library headers expose the same Sort icon immediately before the Settings/profile button, including the overview, Albums, Artists, Album Artists, Songs, Genres/composer songs, playlists, Loved Songs, Favorite Artists, album details and artist details. The existing header actions share their glass capsule. Its sheet opens above shell chrome through the root navigator.

The selected order is shared across Library routes for the current session. Every page offers **A–Z** and **Z–A**, using the displayed item name, with **A–Z** as the default. The owner subsequently restored **Size (Largest first)**, **Size (Smallest first)**, **Release Date (Newest)** and **Release Date (Oldest)** on applicable song/release lists. Size uses the existing SQLite file-size inventory for Songs and release shelves; in-memory detail/collection lists with release tags offer release-date order. Artist/category directories and playlist directories retain alphabetical options; a nonapplicable shared choice falls back to A–Z. Original order, added-date and per-field choices stay removed. Home and Search keep their own ordering.

Songs starts alphabetically, so its letter rail is visible on first opening. Album detail sorting stays within disc groups, while header genre/year come from source metadata independently of display order. Artist Popular keeps its play-count ranking. Collection sorting operates on copied display lists; manual playlist reordering uses the saved order. Sort changes reset Songs pagination/selection. A pending Play-all read uses one order snapshot and stops if the user changes it.

Album, artist and genre queries apply the shared alphabetical direction before their page limits. In-memory collections sort copied display rows with stable identity ties.

## Removed components

- Album completeness sheet, badges, row model, request field, inventory assessment SQL and dedicated service.
- Songs Quality, Format and Metadata filter sheet, selection state and query/cache plumbing.
- Obsolete localization keys in every locale and tests exclusive to the removed features.

Release metadata still classifies Home Singles and Albums. Ordinary album track-count badges remain.

## Verification

The latest full Flutter suite passed **2,445 tests**, with **3 skipped** and no failures (5m45s); analysis reported no issues. The focused suite passed **37 tests**, covering real file-size behavior, size/release picker dispatch to bounded queries, root-navigation modal accessibility, playback/selection, side-only letters and off-page Songs navigation.

Graph `e97b6ac6` contains 29,366 unique nodes and 56,025 links with no dangling endpoints; existing extraction limitations remain. No native source changes, APK build or device execution were performed for this restoration.
