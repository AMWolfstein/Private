# Home release shelves and Logs filters

Home now presents Albums followed immediately by Singles using the existing release cards and local detail routes. Each shelf has an independent bounded SQLite query, loading state, retry and refresh. Release classification happens before ordering/limits, so singles cannot consume the album shelf's result budget.

A single requires explicit grouped metadata `total_tracks = 1` and `total_discs <= 1`. An album with only one locally available song remains an album when its tag declares more tracks. EPs, unknown totals and multidisc releases remain in Albums. Latest Releases and Recently Added retain their existing behavior.

Settings > Logs no longer offers Full or switches into a separate live-logcat view. Available filters are ALL, DEBUG, INFO, WARN and ERROR, with existing search, selection, copying and sharing. Detailed logging, persisted crash diagnostics and diagnostic export remain supported. The obsolete Full label was removed from every locale.

## Verification

Regression tests cover real SQLite classification before limits, partial albums, EPs, unknown totals, multidisc releases, both Home brightness modes, independent shelf requests/order and the Logs level picker. The focused suite passed 25 tests. Full-suite and analysis results are recorded in the migration progress tracker.

No APK was built and no device UI or performance measurement was performed for this change.
