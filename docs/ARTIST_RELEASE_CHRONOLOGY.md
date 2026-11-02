# Artist release chronology and live portraits

Artist detail Albums, Singles and Appears On follow validated release-tag chronology, newest first. Global Library Sort no longer changes these shelves. Undated/invalid dates follow dated releases; existing added-time and album-key ties remain deterministic.

Albums and Singles have independent bounded 40-item pages, so newer Singles cannot crowd Albums out of an initial mixed page. Each shelf retains independent pagination/retry. Appears On keeps track-only-credit ownership rules.

The Featured card selects the newest owned album through a separate one-item album query. If no album exists, a second bounded one-item query selects the newest owned Single. Explicit one-track, one-disc Singles are excluded from the album choice but remain eligible for the Single fallback; releases belonging only to Appears On are excluded from both. Partial albums, EPs, unknown totals and multidisc releases retain the existing Albums classification.

The same selected release supplies the artist detail portrait. Artist/Album Artist directory SQL uses equivalent album ownership, classification, normalized release-date order and cover aggregation. Favorite Artists tiles read the live Featured provider. A selected release with missing artwork shows a placeholder rather than another song's cover; artists with neither an owned album nor an owned Single retain existing route/saved/track fallbacks.

Featured selection watches the loaded library-index revision and shared tag-credit scope. A newly indexed newer album therefore updates an already-open artist page and its portrait, as well as active directory/favorite views. Persisted favorite entries and routes cannot override a new Featured cover. Adding an older album later does not replace a newer release.

Directory portrait selection stays inside the existing bounded-page SQLite SELECT, using correlated album/Single aggregation compatible with the existing Android SQLite baseline rather than window functions. No artwork download, new native channel or schema migration is introduced.

## Verification

Focused tests passed 30 cases covering real SQLite ownership/chronology, more than 40 newer Singles, a newer guest appearance, directory portrait refresh, missing-cover handling and a mounted artist page updating on an index revision while global Sort is set to size, including the Single-only fallback and matching portrait. The final full Flutter suite passed **2,446 tests**, with **3 skipped** and no failures (5m54s); analysis reported no issues. Graph `b566b686` contains 29,378 unique nodes and 56,059 links with no dangling endpoints; existing extraction limitations remain. No APK, device execution or performance measurement is claimed.
