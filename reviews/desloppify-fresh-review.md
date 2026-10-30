# Fresh Desloppify design review

Branch: `desloppify/code-health`; reviewed commit: `0af12fc`.

Before publication, the branch was fast-forwarded to upstream `f445aad`. The four upstream commits after the reviewed commit are outside this review; these assessments describe `0af12fc`.

Twenty design dimensions were reviewed by four independent native Codex reviewers using the same blind packet and current source. Reviewers received no historical scores. No application source changes, test execution, or APK builds were performed.

The CLI batch runner failed authentication. The supported manual import succeeded: 20 assessments and 11 findings. Assessment scores are provisional and reset on the next scan unless replaced through a trusted runner. The displayed strict score is 90.1 and overall 91.1, combining new provisional design judgments with the existing objective scan (94.9); these are not freshly rescanned objective results. No claim of complete code health or runtime correctness is made.

## Assessments

| Dimension | Score |
|---|---:|
| abstraction_fitness | 93.0 |
| ai_generated_debt | 90.0 |
| api_surface_coherence | 96.0 |
| authorization_consistency | 100.0 |
| contract_coherence | 91.0 |
| convention_outlier | 100.0 |
| cross_module_architecture | 94.0 |
| dependency_health | 100.0 |
| design_coherence | 88.0 |
| error_consistency | 90.0 |
| high_level_elegance | 86.0 |
| incomplete_migration | 100.0 |
| initialization_coupling | 96.0 |
| logic_clarity | 93.0 |
| low_level_elegance | 89.0 |
| mid_level_elegance | 88.0 |
| naming_quality | 92.0 |
| package_organization | 87.0 |
| test_strategy | 92.0 |
| type_safety | 94.0 |

## Findings

### 1. Audio analysis backend ownership remains split between widget State and the service package

Dimension: `high_level_elegance`. Confidence: high.

Files: `lib/widgets/audio_analysis/audio_analysis_widget.dart`, `lib/widgets/audio_analysis/audio_analysis_models.dart`, `lib/services/audio_analysis/audio_analysis_jobs.dart`, `lib/services/audio_analysis/audio_analysis_cache.dart`

- AudioAnalysisCard State implements _loadFromCache/_saveToCache and source-mtime validation at lines 418-485, while services/audio_analysis/audio_analysis_cache.dart owns only cache budgeting/eviction.
- The same State implements _runAnalysis (line 544), SAF staging, _generateSpectrogram (line 670), FFprobe metadata extraction (line 898) and full-stream level analysis (line 998), in addition to widget lifecycle and build.
- AudioAnalysisData is a part of the widget library, so the operation result model is also bound to the presentation library. Changing analysis inputs, storage or execution policy requires editing the widget implementation despite the focused service package.

Recommendation: Move the existing analysis operation and cache read/write methods, together with their plain result records, into the existing services/audio_analysis package as a concrete analysis runner. Keep image display/disposal, user actions and setState in the card. Reuse AudioAnalysisJobs and AudioAnalysisCache directly; do not introduce an interface/factory family. This relocates existing responsibilities and removes backend protocols from State.

### 2. Metadata persistence and device probe storage are placed in widget directories

Dimension: `package_organization`. Confidence: high.

Files: `lib/widgets/library/track_metadata_persistence.dart`, `lib/services/library/metadata_cover_resources.dart`, `lib/services/library/metadata_index_reconciler.dart`, `lib/widgets/glass/app_glass_auto_probe.dart`, `lib/providers/runtime_profile_provider.dart`, `lib/main.dart`

- track_metadata_persistence.dart contains a framework-free MetadataPersistenceService that performs native tag edits, FFmpeg fallback, SAF writeback and resource cleanup; it contains no widget. The closely related cover-resource and index-reconciliation services already live in services/library.
- app_glass_auto_probe.dart contains AppGlassAutoResult/Step, JSON encoding, SharedPreferences persistence and frame-window sampling, while the actual host widget is separately implemented in app_glass_auto_probe_host.dart.
- runtime_profile_provider.dart imports the widgets/glass file to type state and call saveGlassAutoResult; main.dart imports it to bootstrap persisted probe results. Thus the misplaced file is already serving application/runtime code rather than just widgets.

Recommendation: Move track_metadata_persistence.dart into services/library and update its sheet/test imports. Move the non-widget auto-glass probe module into a focused runtime/service location (or keep its data with models/app_glass.dart and its persistence/sampler in one service file), updating the provider, bootstrap and host imports. Preserve the existing implementations and public names; add no forwarding barrels.

### 3. SAF temp-copy failures lose their causes before reaching callers

Dimension: `error_consistency`. Confidence: high.

Files: `lib/services/native/media_file_bridge.dart`, `android/app/src/main/kotlin/com/amwolfstein/sistrum/MainActivitySafIo.kt`, `lib/widgets/audio_analysis/audio_analysis_widget.dart`, `lib/widgets/library/batch_track_actions.dart`

- copyUriToTemp catches SecurityException and all other Exceptions, logs their messages and returns null; safCopyToTemp returns that null as a successful channel response.
- MediaFileBridge.copyContentUriToTemp exposes Future<String?> without an error reason. _runAnalysis replaces null with Exception("Failed to copy SAF file for analysis"), and ReplayGain returns storageFailed without its error field. Permission denial, missing media and storage/provider I/O failures become indistinguishable.

Recommendation: Have the native safCopyToTemp channel handler return a PlatformException with a stable storage failure code and the original cause/message on copy failure; return a non-null path on success. Preserve that exception in ReplayGainWriteResult.error and let analysis retain it.

### 4. Backup parsing reports unsupported and corrupt native archives as unreadable

Dimension: `contract_coherence`. Confidence: high.

Files: `lib/services/backup/backup_service.dart`, `lib/screens/settings/backup_restore_page.dart`, `rust_backend/crates/mobile/src/native_backup/archive.rs`, `rust_backend/crates/mobile/src/data_jobs.rs`

- BackupParseFailure.unsupportedVersion is documented for incompatible backup versions and has a dedicated localized UI message, but no parse branch constructs that reason.
- archive::read rejects invalid magic, versions other than 3 and malformed metadata through Result errors; data_jobs wraps those as NativeDataJobError::Operation. _parseArchiveNative maps only Dart FormatException to corruptArchive and all other exceptions to unreadable, so readable incompatible/corrupt ZIP backups receive the storage-read-failure message.

Recommendation: Carry a small explicit backup failure code from the native reader across the channel and map it to unsupportedVersion, corruptArchive or unreadable in BackupService; separate native version rejection from malformed metadata.

### 5. The failed ReplayGain constructor permits a value that reports success

Dimension: `type_safety`. Confidence: high.

Files: `lib/services/playback/replaygain_write_result.dart`, `lib/widgets/library/batch_track_actions.dart`

- ReplayGainWriteResult.failure is ReplayGainWriteFailure?, and const ReplayGainWriteResult.failed(this.failure, {this.error}) therefore accepts null.
- isWritten is defined as failure == null. Consequently ReplayGainWriteResult.failed(null) is a legal failed-constructor call that batch code treats as a written result. Existing call sites pass enum values, so this is a public type-contract hole rather than evidence of a current failed write being marked successful.

Recommendation: Declare the failed constructor parameter non-null explicitly: const ReplayGainWriteResult.failed(ReplayGainWriteFailure failure, {this.error}) : failure = failure.

### 6. AsyncData pages run the same cache update twice

Dimension: `logic_clarity`. Confidence: high.

Files: `lib/screens/library/library_section_tab.dart`

- At lines 269-274, _resolveLibraryBrowsePageData calls storePage(value.asData.value), then value.whenOrNull(data: storePage). For AsyncData both calls receive the same page.
- storePage performs cache lookup, stale-request traversal, mutation and trimming, so these are duplicate side effects rather than alternative fallbacks.

Recommendation: Keep the direct asData path once; remove the subsequent whenOrNull dispatch. This also retains the existing behavior for previous data exposed by asData.

### 7. Browse paging loses the lyrics-presence field at the database/domain seam

Dimension: `mid_level_elegance`. Confidence: high.

Files: `lib/services/library/library_browse_store.dart`, `lib/services/library/library_browse_rows.dart`, `lib/services/library/library_row_mapper.dart`, `lib/models/local_library_item.dart`

- _queueTrackUnionSql selects has_replaygain but never has_lyrics; queueTrackRowToJson also omits hasLyrics.
- LocalLibraryItem.fromJson interprets missing hasLyrics as false, while LibraryRowMapper.decode explicitly maps has_lyrics. Thus the same stored song has different domain metadata depending on whether it was read through trackPage or the canonical mapper.
- test/library_schema_test.dart verifies canonical round-tripping with hasLyrics=true; the browse-store fixture does not set that flag.

Recommendation: Select l.has_lyrics in the track query and use LibraryRowMapper.decode for shared track fields in queueTrackRowToJson, adding only actual browse-specific fields. Add a browse-page check with hasLyrics=true to verify parity.

### 8. The metadata filter sheet repeats the same chip behavior for every option

Dimension: `low_level_elegance`. Confidence: medium.

Files: `lib/screens/library/library_section_tab.dart`

- _showFilterSheet repeats AppChoiceChip label/selected/onSelected subtrees from the metadata section through the completeness filters (roughly lines 537-688). Each option repeats its mode string in selection and callback.
- The same method already uses a compact sortChip(label, mode) helper for its sort options, demonstrating that the repeated state wiring is unnecessary.

Recommendation: Mirror the existing sortChip helper with a local metadataChip(label, mode) helper, or iterate a local list of (label, mode) records. Keep option order and localized labels in the sheet while defining selection/callback wiring once.

### 9. Snapshot-retention parameters misleadingly describe active downloads

Dimension: `naming_quality`. Confidence: high.

Files: `lib/screens/library/library_browse_refresh_policy.dart`, `lib/screens/library/library_section_tab.dart`, `test/library_browse_refresh_policy_test.dart`

- resolveLibraryBrowseCountsSnapshot accepts activeDownloadFallback and shouldRetainLibraryBrowsePageSnapshot accepts activeDownloadFallbackAvailable, but neither observes a download.
- Their caller passes nonEmptyFallback and nonEmptyFallback != null, representing an in-memory snapshot. Tests describe the same mechanism as both a download refresh and in-memory history.

Recommendation: Rename the parameters to nonEmptyFallback and nonEmptyFallbackAvailable (or snapshotFallback equivalents) and update the download/history test descriptions to describe local browse snapshot retention.

### 10. Local-only browse SQL retains unnecessary multi-source assembly scaffolding

Dimension: `ai_generated_debt`. Confidence: high.

Files: `lib/services/library/library_browse_store.dart`

- counts and _getUnfilteredQueueCounts each allocate parts, add exactly one SQL string and join with UNION ALL; their outer SELECT then SUMs the one aggregate row (lines 68-93 and 117-137).
- _queueTrackUnionSql and _queueAlbumUnionSql likewise add only one bounded local query before joining parts. There is no branch that contributes a second source.

Recommendation: Return the bounded local SQL string directly from the track/album builders. Execute each count aggregate directly and remove its one-element parts list and outer SUM layer, preserving the existing COALESCE behavior.

### 11. Two SQL behavior fixtures depend on the formatting of production Dart source

Dimension: `test_strategy`. Confidence: high.

Files: `test/album_completeness_query_test.dart`, `test/replaygain_library_filter_test.dart`, `test/library_schema_test.dart`

- album_completeness_query_test.dart _definition and replaygain_library_filter_test.dart _tableDefinition read library_schema.dart and extract CREATE TABLE with a regex requiring a newline before the closing parenthesis, then force-unwrap the match.
- These behavior tests fail on a harmless one-line SQL declaration or equivalent extraction into a helper, and run the uninterpolated Dart string rather than executing schema creation. library_schema_test.dart already demonstrates executing LibrarySchema.create against SqliteProcessDatabase instead.

Recommendation: Use LibrarySchema.create with the existing SqliteProcessDatabase helper to prepare these fixtures, and run their actual predicates/page queries against that database. Remove the source-reading regex helpers and retain the existing result assertions.

## Next step

The tool requests `workflow::create-plan`: prioritize the new findings before implementation. No findings were fixed in this review. Restore CLI authentication for a durable trusted batch assessment; avoid interpreting provisional score improvements as measured runtime improvements.

Raw independent reviews and the merged import are retained under `.desloppify/fresh-review/`. The previous review state was archived outside the repository at `/workspace/review-backups/desloppify-before-rereview.tar.gz`.
