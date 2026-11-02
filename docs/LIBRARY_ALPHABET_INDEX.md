# Library alphabet index

Songs, Artists and Album Artists now show a persistent letter rail in A–Z/Z–A order, with A–Z as the default. Size or release-date ordering hides the rail until alphabetical ordering is selected again. Tapping or dragging a letter goes to its first matching row. The rail follows the order of the list, includes Arabic and Latin initials and the `#` bucket for nonletters, and stays on the physical right edge in both LTR and RTL layouts. It shows only initials present in that category.

Songs, Artists and Album Artists have continuous rows without inline letter headings. Songs also has no month/date headings. The letter rail is the only alphabetical index shown. Other Library categories keep their existing navigation.

## Data and navigation

SQLite returns a compact projection of initial groups and counts from the entire visible library. Artist and Album Artist indexes use their respective split-credit scopes. This projection supplies global row offsets without transferring every track or its metadata/artwork.

Selecting an off-page letter loads the intervening existing bounded pages on demand and retains normal paging behavior. A lazy section controller seeks through render estimates, then reveals the actual row below the pinned toolbar, without retaining a key per song. Request generations cancel superseded navigation; sort changes, scans and disposal invalidate pending jumps. Controller attachment belongs to its current list state, so disposal of a replaced list cannot detach its replacement.

Large jumps can require several page reads; this is on-demand navigation rather than a preloaded full-library snapshot. Device latency and very large-library memory usage were not measured.

## Verification

Tests cover Arabic/Latin rail taps and drag gestures in LTR/RTL; lazy navigation forwards and backwards through 1,500 variable-height rows; off-page Artists and Album Artists; Songs navigation past the initial 300 rows to row 600; removal of Songs date headings; and SQLite index counts, order, unavailable sources and credit scopes. The full Flutter suite passed **2,445 tests**, with **3 skipped** and no failures (5m45s); analysis reported no issues. Graph `e97b6ac6` contains 29,366 unique nodes and 56,025 links with no dangling endpoints; existing extraction limitations remain.

A focused Songs test exposed a stale list-state detach clearing the replacement controller binding. Ownership checks corrected it, and the navigation test was rerun successfully. No native code, APK build or device execution is involved.
