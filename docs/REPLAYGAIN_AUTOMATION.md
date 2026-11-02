# ReplayGain automation corrections

Owner-approved implementation, 2026-11-02.

## Pipeline

`ReplayGainAutoWriter` discovers visible Library songs, measures missing or known-changed track tags, measures whole albums, and then publishes all pending track/album fields together for each file. Album loudness is measured from the concatenated programme, never an average of track gains. The album scan also produces true peak. When both sets of fields are needed and available in a pass, one call to the native metadata editor (or one stream-copy fallback) writes them, under one integrity-checked update. If an album cannot be measured completely, no partial-album gain is published.

An absent saved track stamp means first observation, not a detected change. Valid existing track tags are preserved; complete existing album tags are adopted on first observation when no track needs remeasurement. Known stamp changes or missing values cause the corresponding measurement. Successful per-file stamps and whole-album fingerprints remain in the existing state store; a failed/deferred album is never marked complete.

## SAF and ownership

Filesystem and `content://` documents participate in the same album. Metadata reads and measurements of SAF documents use app-owned temporary copies. All album copies remain alive until the measurement finishes and are deleted on success, decoder exceptions and partial permission failures. Writes use the existing verified SAF write-back service and report failures. Providers must expose usable file size/modification identity; unknown identities fail visibly instead of allowing unverified stale writes. Virtual CUE rows remain excluded, and unsupported/nonlocal album members prevent partial-album measurements.

Track and album measurement remain distinct audio operations; combining their tag publication does not claim one decode or a device-speed improvement. Large SAF albums require temporary space for their staged members.

## Lifecycle and playback

A generation invalidates cancelled work. Rapid off/on and index refreshes received during a pass queue a fresh pass instead of being dropped by `_running`. Charging/deferred waits can be woken immediately on disable, policy changes or disposal; their real timers are cancelled. In-flight work does not publish stale progress after disposal.

The writer rechecks the currently playing source and file identity after measurement and passes a guard into the service, which checks again immediately before editing and before SAF publication. Playing/changed files are deferred for a later pass, not counted as successful. This is a check before each operation, not an atomic lock against playback starting inside an already-running local native edit; such an edit cannot be cancelled midway by this Dart coordinator. An already-started operation finishes before a newly queued pass starts.

## UI and failure reporting

`ReplayGainProgress` separates preparing, track measurement, album measurement, writing, waiting for charging/playback, completion and failure. The visible UI shows checked/total plus written, unchanged, failed and deferred counts. A disabled writer has no progress indicator; waiting/error states do not animate a spinner. Work-unit progress cannot reach 100% before the publishing stage finishes, and is not an estimate of elapsed time. Completion with errors has a distinct label. Explicit off/on retries failures; routine refresh does not repeatedly retry a session's known failures.

English and Arabic describe missing/changed tags, combined publication, SAF and the separate Playback volume-normalization control. Other locales use existing English fallbacks for the newly introduced strings.

## Removal is not an app operation

At the owner's additional request, `ReplayGainService.removeFromFile`, its six dedicated tests and orphaned removal translations are deleted. The service rejects empty/nonfinite gain/peak values, so passing blank values to its write API cannot serve as a removal shortcut. Disabling automation preserves existing tags. Generic native metadata-editor field replacement semantics remain intact; they are also needed to replace existing values correctly and are not a dedicated ReplayGain-removal service.

## Integrity

Combined writes retain the existing audio-packet hash, size, tag-readback and recovery guards, Opus/native-container handling and playback-normalization refresh. The source is not edited if its initial audio hash is unavailable. Unexpected exceptions after a completed backup trigger best-effort restoration; an incomplete backup is never restored over the original. Failed restoration retains the recovery backup.

## Verification

Source `3450abd0`. `flutter analyze --no-pub`: **No issues found**. Full Flutter suite: **2,468 passed / 3 skipped / zero failures** (5m55s). Focused coordinator, integrity, service/SAF, progress UI, measurement-parser and library checks: **50 passed** after removing the six obsolete removal tests and adding the empty-value rejection test.

Coverage includes combined native edit/publication counts, existing-tag adoption, stamp changes, mixed SAF/filesystem albums, partial permission failures and temp cleanup, playback starting during measurement/before publication, cancellation/off-on/index refresh/disposal, failed writes, failed state persistence without double counting, unknown identities, empty libraries, waiting/disabled UI and all outcome counts. Earlier broad runs were stopped for final corrections and the owner's removal request; the reported final full run completed successfully. Integrity arithmetic regressions remain in a dedicated test file.

Graph `a0112844`, built from `3450abd0`: **29,428 unique nodes / 56,089 links / zero dangling endpoints**. The removed service method has no node. Existing native-vendor extraction limitations remain.

Native channels and audio measurement are faked in host SAF/coordinator tests; these are not physical-device SAF-provider or format-wide codec acceptance results. No native-source changes, instrumentation/device run or device performance benchmark. The owner additionally requested a pushed source branch and a development-key-signed ARM64 release APK on a separate artifact branch; build identity, SHA-256 and signing certificate are recorded with that uploaded artifact.

Commit-order exception: the first graph validator encountered nullable source-file metadata and stopped before staging the graph. The already-pushed documentation checkpoint preceded the graph commit; this follow-up corrects its reference without rewriting remote history. The graph passed validation after handling the optional metadata.

## Settings presentation correction

The owner's APK screenshot prompted a compact title/description and a standard SettingsItem status/count layout. Outcome labels wrap individually in muted supporting text. The inset progress bar matches Song analysis and remains visible with a determinate value while waiting for charging/playback or after an error. Only initial preparation can be indeterminate; disabled automation stays empty. Eight widget tests passed, including 320 px width at 2x text scale in English and Arabic; analysis clean. The measurement/write pipeline did not change, and the prior full-suite result above predates this UI-only patch.
