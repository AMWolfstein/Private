# Collection and application-job lifecycle

## Scope

STATE-03 concurrency-auditor, source d5d5a02 unchanged HEAD5179dfea. Complete principal reads: lib/providers/library_collections_provider.dart1–839,playback_notification_provider.dart1–57; lib/services/batch_track_actions.dart1–139,local_track_batch_actions.dart1–73,player_widget_service.dart1–291,notification_service.dart1–335,app_orientation.dart1–71 (1,805 lines).
S1: lib/widgets/batch_progress_dialog.dart1–185,app_alert_dialog.dart1–125; screens/selection_mode_mixin.dart1–56; services/replaygain_service.dart35–122; widgets/local_song_menu.dart175–195; services/music_player_runtime.dart145–167,227–269 presentation bindings only; main.dart125–143; providers/local_library_provider.dart1340–1385,1520–1542,1590–1648,1668–1675; test/player_widget_service_test.dart1–350 source only. Fresh DATA-006/UI-002 read for dedup. Audio engine excluded.

## Findings

### CONC-001 [P2] [confidence: high] [VALIDATED — static]

- Location: lib/services/batch_track_actions.dart:124, runBatchReplayGain; lib/widgets/batch_progress_dialog.dart:84, dismiss.
- Scenario: start long ReplayGain operation, Android Back dismisses progress, open Settings while job continues; completion pops Settings.
- Root cause: job does not track dialog route dismissal and blindly pops top root route.
- Impact: unrelated screen closes; Back leaves batch running without cancellation.
- Fix: own/dismiss exact dialog route; prevent Back or route it through cancellation.
- Evidence: show67–77 barrierDismissible false but no PopScope/route-future tracking; only Cancel sets cancelled at batch83–85;123–124 dismisses if false; dialog86 unrestricted root pop. app_alert_dialog7–43 RawDialogRoute has no Back interception; song menu184–189 exposes operation; ReplayGain69–89 awaits work.
- Cross-refs: batch_progress_dialog.dart,app_alert_dialog.dart,local_song_menu.dart,replaygain_service.dart.
- Guards checked: barrier flag blocks outside taps only; captured root navigator stays mounted after dialog leaves; UI-002 is different collection-removal callback. Coordinator independently read complete batch action, dialog1–99 and route1–47.

## Verification / limits

Graph collections/batch/widget query completed truncated; explain LibraryCollectionsNotifier completed. Source guards checked: mutation queue and hydration identity, widget art generations/channel serialization, notification work serialization/scan-state checks. No runtime navigation, Flutter tests/analyzer, builds or devices. Test source inspection only. Review prompt-only; no changes. Separate restore-cover security lead queued for independent trust-boundary validation; not certified here. Result FINDINGS, one P2.
