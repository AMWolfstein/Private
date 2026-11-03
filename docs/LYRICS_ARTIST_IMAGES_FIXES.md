# Lyrics and Deezer artist-image corrections

Owner-authorized combined implementation, 2026-11-03. This batch intentionally includes source, tests, graph and documentation in one commit, overriding the usual three-commit convention. The preceding centered-Play commits through `f7c4758e` were pushed first.

## Lyrics

- Native error maps and empty metadata are typed read failures, never absent lyrics. Failed reads cannot reach a metadata writer or bypass replacement confirmation.
- Sidecars are flushed in a sibling temporary directory. Replacement publishes by rename; no-replace creation uses an exclusive destination reservation rather than an existence check. Failed publication preserves an existing sidecar and cleans owned staging/reservations. The brief empty reservation is not a promise of a cross-process filesystem transaction; an unrelated program that deliberately overwrites an owned path remains outside this coordinator.
- File-write results and the timing cache are separate: cache errors are logged after successful embedding without prompting a second audio-file write. Both save UI paths always release Busy and report exceptions.
- A successful Now Playing embed refreshes only the still-current source. SAF refresh reads the canonical document rather than a stale playback copy; generation guards reject late replies after track changes.
- Artist matching uses complete normalized artist credits, preserving featured-artist matches without accepting a shared first name.
- Every source is still queried once in parallel. Stable partial snapshots appear as sources finish, each source has a bounded deadline, and closing/replacing a search cancels result delivery and closes its owned client. No staged-search UX is restored.

## Artist photos

- Automatic passes recheck activation, network policy, cache generation and per-artist revision across asynchronous boundaries. Only an absent record can receive an automatic publication; manual selection and Reset win over stale automatic work. Provider disposal closes its request client.
- Disabling automatic downloads preserves all records/photos and their display. Reset stores an explicit album-cover preference, suppressing future automatic replacement. Clear is independent and invalidates in-flight passes; later scheduled automatic passes may start again if still enabled.
- Mutations are serialized within the shared store. New generations have independent filenames per artist key, including when two keys select the same Deezer ID. Legacy shared files are pruned only after their final record reference disappears.
- Database publication precedes deletion of the old photo. Failed publication cleans the unrecorded candidate while preserving the prior record/file. Manual-save and Reset storage failures are handled visibly with Busy cleanup.
- Automatic artist names use the same Tag separators and Keep together rules as Library credits.
- Missing/malformed Deezer `data` arrays are outages, not durable not-found records. Existing legitimate not-found/reset records retain their documented suppression behavior; this does not guess which historical misses came from an old malformed response.
- Photo revisions are published after bounded batches (five changes by default), with a final flush on completion, early stop or failure, instead of waiting for the entire library pass.

## Verification

- Focused lyrics, artist-image and player-metadata regressions: **110 passed**.
- Full Flutter suite: **2,568 passed / 3 skipped / zero failures**, completed in 6m09s.
- `flutter analyze --no-pub`: **No issues found**.
- Graph refreshed from this combined source tree before commit; existing extractor limitations remain.
- No native production sources changed.

Tests use fake HTTP/native metadata boundaries and temporary files. No live Deezer/lyrics-endpoint acceptance, actual device storage or physical playback test is claimed. Store serialization is process-local, not a distributed lock. A native/database operation that has already begun cannot be physically cancelled midway; later manual/reset/clear operations are ordered and ownership is checked before publication.

The requested ARM64 development-key release is built after the implementation commit. Its independent artifact branch contains the APK, checksum and JSON manifest with the exact source revision and signing certificate; artifact success is reported only after upload verification.
