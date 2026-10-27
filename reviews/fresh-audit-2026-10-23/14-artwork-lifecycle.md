# Artwork and non-engine presentation lifecycle

> Identity normalization (T16, 2026-10-28): historical names, paths and command strings below were mechanically renamed. Original evidence used the former terms; no listed checks were rerun by this rename. Encoded upstream/download identifiers retain their actual destinations.

## Scope

CONC-02 coordinator acting as concurrency-auditor; source d5d5a02 unchanged at5179dfea. Principal complete reads: lib/controllers/player_metadata_controller.dart1–246; lib/services/cover_analysis_store.dart1–91,library_cover_snapshot.dart1–125,custom_font_service.dart1–96,shell_navigation_service.dart1–218,sistrum_glass_auto_probe.dart1–151,sistrum_glass_migration.dart1–41,downloaded_embedded_cover_resolver.dart1–1017; lib/providers/runtime_profile_provider.dart1–192. Graph query broad/truncated, narrowed explain DownloadedEmbeddedCoverResolver identified source symbol67. No code edits, builds or graph mutation.

Named ART-S1 direct consumers: lib/widgets/local_library_artwork_builder.dart complete; services/metadata_persistence_service.dart complete (previous DATA-01 scope); services/library_edited_metadata.dart complete; widgets/local_song_menu.dart285–340; screens/now_playing_screen.dart85–135; test/downloaded_embedded_cover_resolver_test.dart1–110; player_metadata_controller_test.dart test names/calls searched only. Cross-repository resolver callers/invalidation searched. Shared artwork grounds/palettes are separate coverage.

## Findings

### BUG-005 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/services/downloaded_embedded_cover_resolver.dart:450, _ensureCover failure suppression.
- Scenario: a local filesystem track's embedded-cover extraction fails temporarily (e.g. removable file unavailable), then the file becomes readable and visible widgets request it again; resolver keeps returning no art even after the retry cooldown.
- Root cause: any remembered local-path failure returns immediately regardless of elapsed time or source version; only content URIs can retry.
- Impact: placeholder art persists until memory-LRU failure eviction, cache clear or process restart despite recoverable local artwork.
- Fix: version negative cache entries or allow bounded local retries after cooldown, retaining I/O concurrency limits.
- Evidence: _rememberFailedExtract records timestamp312–318; _extractCover remembers failures on missing output/error; _ensureCover checks !isContentUri OR cooldown and returns before reading source mtime. resolve/resolveOrExtract funnel misses into this branch. LocalLibraryArtworkBuilder75 uses it when scanned art missing; callbacks only repaint and do not clear failed entry.
- Cross-refs: lib/widgets/local_library_artwork_builder.dart; test/downloaded_embedded_cover_resolver_test.dart57–110 confirms SAF-only recovery contract in source (not executed).
- Guards checked: cache validation requires a positive entry, absent after first failure. Refresh/callback does not invalidate failure. Successful metadata editing may separately regenerate a scanned cover (local_song_menu304–329), so no claim that every Edit Metadata path fails; this finding concerns retry of temporarily unavailable filesystem files without a rescan.

## Verification / limitations

Static single-isolate state-machine proof only; no Flutter/runtime fixture executed. Extraction scheduling has two-worker/24-background queue bounds, generations and cancelled-job guard; metadata/lyrics parsing has generation/revision/disposal guards; snapshot cleanup retains attached files. No other concurrency defect validated in read chunk. Font import reentry/caller behavior and malformed preference-type startup failures not promoted without stronger paths. Result FINDINGS, one P2. Audio engine excluded; no multithread/FFI safety claim.
