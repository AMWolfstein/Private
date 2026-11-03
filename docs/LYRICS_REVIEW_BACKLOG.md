# Lyrics and artist-image review resolutions

Recorded: 2026-11-03.
Reviewed revision: `19c960879026cfd19d7d835adbfc7aa4420a73ce`.
Status: owner-authorized findings and both additional proposals implemented together on 2026-11-03. Historical references below describe the reviewed revision, not current line positions. See `LYRICS_ARTIST_IMAGES_FIXES.md` for resolutions, verification and limits.

## Five findings

1. **High — distinguish metadata-read failure from absent lyrics.**
   `lib/services/lyrics/embedded_lyrics_writer.dart:54` treats a metadata error map without a lyrics field as empty lyrics. A transient read failure can bypass replacement confirmation; the subsequent write also needs to reject failed/incomplete metadata reads rather than filling unrelated fields from defaults.
   Proposed fix: propagate a typed read failure and stop saving until the file can be read successfully. Test error maps, exceptions and a first failed read followed by a successful read of existing lyrics.

2. **High — protect existing LRC files during replacement.**
   `lib/services/lyrics/lrc_sidecar_store.dart:49` checks existence separately from writing, and line 52 writes directly to the destination. A write failure can leave an existing sidecar truncated; concurrent creation can also bypass the intended replacement confirmation.
   Proposed fix: stage and flush the new content, then publish with appropriate atomic replacement or no-clobber semantics. Test write/publication failures and concurrent creation, preserving the previous file on failure.

3. **High — separate successful embedding from timing-cache failure and always release Busy.**
   `lib/services/lyrics/lyrics_save_actions.dart:47` awaits timing-state persistence after the audio file has already been updated. Exceptions can escape to `lib/widgets/lyrics/find_lyrics_sheet.dart:148`, where the save handler has no error/finally path to clear Busy.
   Proposed fix: distinguish file-write success from a cache/index failure, report the actual outcome, and guarantee UI cleanup with lifecycle guards. Test metadata-read exceptions and timing-database failures after a successful write; do not rewrite the file merely to retry the cache update.

4. **High — refresh lyrics for the currently open player after embedding.**
   `lib/screens/player/now_playing_screen_menus.dart:29` discards the sheet's saved candidate. `lib/providers/playback/player_metadata_controller.dart:83` skips re-reading a previously loaded unchanged source path, so an index refresh alone does not refresh the open player's lyrics.
   Proposed fix: explicitly invalidate/reload the saved song's metadata while preserving track-change and request-generation guards. Test embedding into the current song and changing tracks while the sheet is open.

5. **Medium — tighten artist matching.**
   `lib/services/lyrics/lyrics_matching.dart:40` accepts any shared name word. For example, “محمد رمضان” and “محمد حماقي” match through “محمد”; with the same normalized song title and a sufficiently close/unknown duration, a wrong artist can pass filtering.
   Proposed fix: compare complete normalized artist identities/credits, retaining legitimate featured-artist matches. Test shared first names, Arabic names, collaborations and unrelated artists with the same song title.

## Additional proposal

**Display results incrementally and cancel requests when the sheet closes.**
`lib/services/lyrics/online_lyrics_search.dart:101` waits for every provider before exposing any result. The HTTP client created at `lib/widgets/lyrics/find_lyrics_sheet.dart:120` is closed only after that search finishes, rather than on sheet disposal.
Keep the owner-approved single concurrent request per source and grouping by detected timing; publish each available result as it arrives, enforce a bounded search lifetime, and cancel outstanding work on close. Preserve query-generation guards. Test a fast source alongside a stalled source, closing during search and stale replies. Do not restore the superseded staged-search UX.

## Verification at review time

The existing `flutter test test/services/lyrics --reporter expanded` run passed **50 tests** at the reviewed revision. That result does not cover all failure cases above. Live endpoints, physical-device storage permissions, and writes while playing were not verified. No fixes were implemented as part of recording this backlog.

## Artist-image review and owner rules (2026-11-03)

The owner authorized fixing this backlog and the artist-image findings together in one implementation commit (overriding the normal code/graph/docs split for that batch).

- In-flight automatic searches must not publish after disable or replace a manual selection/reset. Disabling automatic downloading preserves all saved photos and their display. Reset keeps the album-cover fallback and suppresses automatic replacement. Clear is the explicit cache/record deletion action.
- Distinct artist keys that select the same Deezer ID must not lose each other's files when one is reset or replaced.
- Failed database publication must preserve the preceding photo/record. Storage errors must clear UI Busy and be reported.
- Automatic lookup must use Library Tag separators and Keep together, rather than querying unsplit collaboration tags.
- Malformed successful API responses must be outages, never durable not-found records.
- Additional proposal: publish saved-photo revisions in bounded batches during an automatic pass, rather than only at the end.

Five temporary deterministic probes reproduced mid-request disable publication, manual-selection override, shared-file deletion, deletion before failed database commit, and malformed-response poisoning. No live Deezer/device validation was claimed. Implementation is authorized; completion evidence will be recorded after verification.
