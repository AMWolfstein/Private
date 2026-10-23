# Library query and statistics integrity

## Scope

STATE-04 data-integrity-auditor, application source d5d5a02 unchanged. Principal complete: lib/services/library_queue_store.dart1–965 (complements prior STATE-02 reads),library_duplicates.dart1–65,library_genres.dart1–49,album_completeness.dart1–97,library_edited_metadata.dart1–43,listening_statistics.dart1–429,listening_rewind.dart1–436; lib/utils/release_date_display.dart complete. Truncated combined statistics/rewind output reread separately.
S1/S2: lib/screens/local_artist_screen.dart340–412,queue_tab_item_widgets.dart1–120,queue_tab_helpers.dart1–140,240–300; services/library_database_models.dart19–150,metadata_persistence_service.dart1–200,library_row_mapper.dart1–100,library_database.dart180–205,525–551,library_schema.dart1–150,205–240; widgets/local_song_menu.dart1–105,150–188,241–330. Schema visibility ranges added during trace without advance supplement announcement; ledger records exact reads. No complete supplemental-file claim.

## Findings

### DATA-012 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/services/library_queue_store.dart:919, _queueTrackRowToJson.
- Scenario: edit metadata from an artist Popular song originally indexed under a configured folder; save replaces its source with legacy; disabling/removing real folder leaves song visible.
- Root cause: queue SQL/mapping drop source_id; model defaults to legacy and metadata save writes that identity back.
- Impact: songs detach from real source visibility/removal/maintenance ownership.
- Fix: project source_id to sourceId or reuse complete shared mapper.
- Evidence: select286–332 lacks source_id; mapper919–963 lacks sourceId; model116 defaults legacy; artist387–394 directly passes track to song menu; menu180–181 edit then304–329 fresh metadata → localMetadataAfterEdit → upsert(sourceId:item.sourceId); mapper41–42 writes provided legacy; database184–201 replaces row without existing source lookup. schema224–228 gates by source; removeSource535–545 deletes original source rows only.
- Cross-refs: local_artist_provider.dart,local_artist_screen.dart,local_song_menu.dart,library_edited_metadata.dart,library_database_models.dart,library_row_mapper.dart,library_database.dart,library_schema.dart.
- Guards checked: CUE edit blocked but normal tracks pass; fresh tags do not recover source identity; Artist bypasses full-record collection lookup; legacy source enabled/available. Coordinator reread projection, model defaults, menu/edit path, mapper and upsert; reviewer explicitly rechecked no source merge.

### BUG-006 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/services/library_queue_store.dart:286, _queueTrackUnionSql.
- Scenario: indexed explicit song appears in Songs or Artist Popular without E badge.
- Root cause: queue select/mapping omit explicit; model defaults false.
- Impact: required explicit labels absent despite stored flag.
- Fix: select/map explicit and verify local queue round trips.
- Evidence:286–332/919–963 omit field; model143 missing false; queue helpers285–296 decode UnifiedLibraryItem; item_widgets65 passes false to LocalSongRow; Artist356–358 uses track.explicit.
- Cross-refs: library_database_models.dart,queue_tab_helpers.dart,queue_tab_item_widgets.dart,local_artist_provider.dart,local_artist_screen.dart.
- Guards checked: rendering does not rehydrate full record; ellipsis lookup does not repair row display. Coordinator independently reread full select/map/model.

## Verification / limits

Graph query genres/duplicates/rewind/statistics/pagination completed, truncated navigation only. Source findings independently checked. No mutation reproduction, tests/builds/device execution. No additional defect validated for exact genre matching, completeness, recorder persistence retry, date buckets or cursor comparison. Legacy COUNT-based Singles alternate branch reachability insufficient; not reported. Prompt-only restrictions; no edits. Result FINDINGS, two P2. Earlier BUG-003/004 deliberately not duplicated.
