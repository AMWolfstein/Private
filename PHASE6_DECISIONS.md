# Phase 6 decisions (auto-resolved to recommended options)

Per the resume instruction: decisions the assistant would normally have asked about were
auto-resolved to the **recommended** option and recorded here instead. Each entry: question →
options → chosen (recommended). Keep this file alongside `LOCAL_OFFLINE_MIGRATION_PLAN.md`;
fold any follow-ups into Phase 8.

## PD1 — Online detail screens (album_screen / artist_screen / playlist_screen)

**Correction (V3, 2026-10-18):** The decision below overlooked the explicit requirement to
reuse the online Mornye designs over local data. It is superseded for UI presentation:
the original artist portrait/identity, featured release, five-song carousel and discography
composition are restored in `local_artist_screen.dart`; album/playlist surfaces use the
original immersive artwork, centered primary pill, Love and Add-to-playlist actions and footer.
The primary action plays local files. Provider/download code remains removed. Artist links
from metadata, home/search, library and favorites now open the local detail screen.
The generic filtered album scaffold is no longer the artist detail destination.

**Question:** their only data source is the extension metadata system (`extensionProvider`,
`trackProvider`, `PlatformBridge.getProviderMetadata`). With the extension registry deleted in
Phase 6 they cannot fetch anything. Delete outright, or keep them stripped-but-dead for a later
online revival?

**Options:** (a) delete outright now; (b) keep stripped as static placeholder screens.

**Chosen (recommended): (a) delete outright.** Reasoning: local browsing already has
`local_album_screen.dart`, `library_tracks_folder_screen.dart` (playlist mode) and the
`MornyeLibraryScreen(page: albums, artist: …)` scaffold used by `queue_tab` for artists; keeping
extension-fetch screens that can only show errors is dead weight. Artist-name/album-name click
navigation (`clickable_metadata.dart`, now-playing, favorite-artists) is re-pointed to the local
scaffold. Deleted with them: `artist_screen_widgets.dart`, `album_screen.dart`'s snapshot/
download plumbing, and the `Extension{Artist,Album,Playlist}Screen` variants inside
`home_tab_*`.

## PD2 — Library DB history lane (biggest blast radius)

**Question:** `LibraryDatabase` ATTACHes `history.db` and merges `history_db.history` rows
("downloaded" lane) into the Library paging/search SQL; the *Rust* native scan
(`rust_backend/crates/mobile/src/native_library.rs:92`) also ATTACHes `history.db` and excludes
paths already present in history. D1 says delete download history. Rip everything out now, or
phase it?

**Options:** (a) strip all Dart SQL lanes now, keep the `history.db` file + ATTACH +
native-scan exclusion SQL until the Rust re-home; (b) delete everything including the DB file
and now.

**Chosen (recommended): (a) phased.** In Phase 6:
- `library_queue_store.dart` / `library_search.dart` queries become strictly local-library only
  (no `history_db` read lanes, no `'downloaded'` source).
- `upsertBatchExcludingHistory` → plain upsert (Dart-side scan no longer excludes anything).
- All invalidation keyed on `downloadHistoryProvider.loadedIndexVersion` re-points to
  `localLibraryProvider.loadedIndexVersion`.
- `deleteDownloadedRowsForSource` loses all callers (its purpose was dedupe vs download rows).
- **Kept until Phase 7:** the `history.db` *file*, `_ensureHistoryAttached`, the native scan
  / import exclusion SQL and `HistoryDatabase` class itself (Rust `native_library` and backup
  still read/refer them; deleting the file early would break native scans on device).
- **Accepted consequence:** previously downloaded tracks do not appear in the Library tab
  after Phase 6 (their old UI lane is gone; the Rust scan still excludes their paths until
  Phase 7 removes that exclusion — at which point a local scan re-adopts those files).

## PD3 — UnifiedLibraryItem

**Question:** delete the wrapper entirely and use `LocalLibraryItem` everywhere (high churn), or
keep `UnifiedLibraryItem` but strip the download-history lane?

**Chosen (recommended): keep the type, strip the lane.** Drop `fromDownloadHistory`,
`historyItem`, `LibraryItemSource.downloaded`; all remaining items are `source: local`.
The pure-rename simplification (fold into `LocalLibraryItem`) is deferred to Phase 8 polish so
the Phase 6 diff stays reviewable.

## PD4 — Home search (Mornye home search removal)

**Question:** what replaces extension-backed home search?

**Options:** (a) local-only search reusing `librarySearchProvider` + `LibrarySearchResults`
(existing local search tab surface); (b) remove home search entirely.

**Chosen (recommended): (a).** `HomeTab` search mode re-parents to `LibrarySearchResults`
(All/Songs/Albums/Artists/Playlists chips, pagination already local). Deleted: `track_provider`
(+ `live_search_cancellation` machinery), `HomeSearchProviderPolicy`, the search-provider
dropdown, URL/Spotify-URI fetch (`_fetchMetadata`), filter-extension plumbing,
`home_tab_search_results.dart` extension buckets.

## PD5 — Home "Recent downloads" row + recent access

**Question:** `_homeHistoryPreviewProvider` and the recents view are fed by
`downloadHistoryProvider`. Re-point or drop?

**Chosen (recommended): re-point to the local library.** "Recent downloads" becomes
"Recently added" backed by `localLibraryProvider` (items sorted by `addedAt`/scan time), merged
with `recentAccessProvider` explicit accesses as before. The download-derived recents
aggregation (`isRecentDownloadAfterClear`, hidden-download bookkeeping for download-derived
entries), `DownloadedAlbumScreen` routing and the `TrackMetadataScreen(item: historyItem)`
recent-payloads are removed; explicit local accesses keep working.

## PD6 — DownloadedEmbeddedCoverResolver (name says download, body is local)

**Question:** the plan lists `downloaded_embedded_cover_resolver.dart` for removal, but the
class is a shared embedded-cover extractor + `cleanFilePath` util for *local* (scanned)
files, load-bearing for `music_player_service`, `track_metadata_*`,
`library_tracks_folder_screen`, `local_track_batch_actions`, `duplicate_cleanup_policy`.

**Options:** (a) delete resolver and its local preview features; (b) keep the file until
Phase 8 and rename/de-couple then.

**Chosen (recommended): (b) keep in Phase 6.** It is a local-file utility mis-named for the
download era; deleting it would break local embedded-art previews and file-path cleaning for
no offline-feature gain. Renaming/trimming is deferred to Phase 8 (its download-only cache
sweep branch is trimmed there).

## PD7 — Verification notifications + widget + queues feedback

**Question:** keep any verification-notification plumbing for future online services?

**Chosen (recommended): delete all.** `verification_notification.dart`,
`NotificationService` track-download verification methods + channel handlers,
`VerificationNotificationIntent.kt`, verification event channels in `platform_bridge.dart`,
`DownloadQueueWidgetProvider.kt` (home-screen widget), `DownloadQueueFeedback`, and the
BackgroundWorkService download path are all removed (Rust/Kotlin method-channel *implementations*
still present until Phase 7 are simply dead code Dart no longer calls).

## PD8 — CSV import flow (home_tab_import)

**Question:** home-tab CSV import enqueues *downloads* (it is download-queue glue, not local
file import).

**Chosen (recommended): delete** `home_tab_import.dart` wholesale with the engine. Local
track import is the library scan; no separate CSV flow survives.

## PD9 — cover_download_service

**Chosen (recommended): delete** — it exists to save remote (http) cover art of downloads.
Local embedded-art saving via the resolver's extract path is unaffected.

## PD10 — Settings keys

**Chosen (recommended): delete all download-engine/extension-only keys**
(`defaultService`, `audioQuality`, `filenameFormat`, `separateSingles`,
`singleFilenameFormat`, `folderOrganization*`, `askQualityBeforeDownload`,
`useExtensionProviders`(+ force-enable), `downloadFallbackExtensionIds`,
`extensionVerificationBrowserMode`, `autoConvert*`, `redownloadFakeHiRes`, `useAllFilesAccess`,
`autoExportFailedDownloads`, `downloadNetworkMode`, `networkCompatibilityMode`,
`allowLocalNetwork`, `songLinkRegion`, `nativeDownloadWorkerEnabled`, `concurrentDownloads`,
`deduplicateDownloads`, `allowQualityVariants`, `saveDownloadHistory`, `searchProvider`,
`defaultSearchTab`, `homeFeedProvider`, plus the settings-provider setters/sanitizers) and
`download_settings_page.dart` itself. **Kept:** `downloadDirectory` / `downloadDirectoryBookmark`
/ `storageMode` / `downloadTreeUri` — the local library scan + SAF playback still need the
storage concept (renamed only if/when Phase 8 touches l10n).

## PD11 — Tests

**Chosen (recommended):** every test whose subject is the download engine, download history,
extension registry/auth/verification, `track_provider` search, or the queue-download UI is
deleted (see inventory below); tests that merely use download fixtures bootstrap their state
from the local library instead. The known-flaky
`test/library_browse_sqlite_paging_test.dart` remains the only accepted failure.
