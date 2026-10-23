# Dart UI dead-code review (D2)

## Scope

Role dead-code-hunter. Baseline47039b90, appd5d5a02 unchanged; graph46c4ea6a reported fresh. All162 lib/screens,widgets,theme,constants,routes,app.dart/main.dart paths screened by import/export/part and declaration-token census. Single-reference methods screened; not whole-body/branch reachability. Graph unused widgets query completed truncated; explain LibraryFileAvailabilityCache,TwoFingerPinchListener,LibraryPlaylistDragSource completed; source evidence authoritative.

Bounded whole reads: widgets/library_playlist_drag_source.dart1–41,two_finger_pinch_listener.dart1–101; screens/queue_library_refresh_policy.dart1–449; tests library_playlist_drag_test.dart,two_finger_pinch_listener_test.dart,track_metadata_badges_line_test.dart. Ranges: widgets/player_playback_controls.dart175–210,track_card.dart180–350,audio_quality_badges.dart74–157; test/queue_library_refresh_policy_test.dart1–185 plus later symbol hits; design_system_test.dart735–830. Coordinator independently reread live policy first53 lines and searched completion/cache names; read widget classes and playback enum; reference corpus includes native/tests/config.

## Findings

### DEAD-012 [P3] [confidence: high] [VALIDATED — static]

- Location: lib/screens/queue_library_refresh_policy.dart:39, completion bridge and file-probe policy island.
- Scenario: current Library retains approximately415 lines of absent download-completion machinery with no production caller.
- Root cause: removed download/completion UI left policy and two timer/cache implementations behind.
- Impact: obsolete state/probe policies and standalone regression fixtures obscure live paging behavior.
- Fix: remove35–449 and obsolete dedicated test cases/imports; retain live count/page helpers8–33. Low runtime risk, approximately415 source lines.
- Evidence: shouldRetainCompletionBridge,resolveCompletionBridgePlayableCandidates,resolveCompletionBridgePlayablePath,LibraryFileAvailabilityCache,CompletionBridgePlayableProbeCache/types appear in production only within same file; standalone queue_library_refresh_policy_test exercises them. Production importer queue_tab only uses separate count/page helpers.
- Cross-refs: queue_tab.dart,queue_library_refresh_policy_test.dart.
- Guards checked: test constructor injections are not instantiated by application; no persistence/channel/generated entrypoint. Do not remove whole imported module.

### DEAD-013 [P3] [confidence: high] [VALIDATED — static]

- Location: lib/widgets/library_playlist_drag_source.dart:5 and two_finger_pinch_listener.dart:11.
- Scenario: neither widget file is imported/instantiated by application routes; dedicated tests build isolated MaterialApp harnesses only.
- Root cause: previous Library interaction composition disappeared.
- Impact:142 source lines and obsolete standalone gesture fixtures with no application consumer.
- Fix: remove both files and dedicated tests; low runtime risk, preserve current row/selection/scroll controls.
- Evidence: production import/export/part census has no incoming edge; exact class searches return definitions and dedicated library_playlist_drag_test/two_finger_pinch_listener_test only.
- Cross-refs: those dedicated tests; track_card.dart.
- Guards checked: no generated hook, persisted data, channel or production injection seam; tests validate only orphan widgets themselves. Test-only usage alone was not used for other shared design primitives.

### DEAD-014 [P3] [confidence: high] [VALIDATED — static]

- Location: lib/widgets/player_playback_controls.dart:194, PlayerPlaybackMode.
- Scenario: unused enum advertises obsolete mode abstraction beside current controls.
- Root cause: callers disappeared but enum remained.
- Impact: misleading unused API.
- Fix: remove one line; negligible risk.
- Evidence: exact symbol search in lib,test,integration_test,android,rust_backend/crates,scripts yields declaration only.
- Cross-refs: single declaration.
- Guards checked: no test, serialization/string dispatch, generated or compatibility consumer; retained controls unaffected.

## Verification / limits

No analyzer/build/test/deletion/security checks or graph mutation. Candidate census initial syntax error corrected and rerun. Keep TrackGridCard,TrackGridPlayButton,TrackMetadataBadgesLine as shared design primitives with standalone/design-system tests pending stronger obsolete-contract evidence. Framework overrides,State classes/debug hooks and unproven public APIs retained. No whole-project absence-of-dead-code claim. Result FINDINGS, three P3, approximately558 source lines plus associated obsolete tests.
