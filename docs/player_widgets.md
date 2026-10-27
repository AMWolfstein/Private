# Android home-screen player widget

Add **Sistrum Player** from your launcher's widget picker. Resize it for compact,
horizontal or large artwork layouts. Widget configuration offers artwork colors,
light/dark appearance and artist-name visibility; reconfiguration depends on the launcher.
Choose a local track in the app first. Artwork/text opens the app; transport buttons use
the existing playback queue. An empty widget opens the app with transport disabled.

Artwork is a static local thumbnail. Updates follow track/transport changes, with no
continuous refresh timer. Remote artwork is ignored. Android controls update timing.

`PlayerWidgetService` publishes through `com.amwolfstein.sistrum/player_widget`, discards stale
artwork results and serializes commands. Native `RemoteViews` use per-widget preferences.
If the process has been killed, a control opens the activity to restore the saved queue
and execute the command; restored playback starts paused.

Run `flutter test test/player_widget_service_test.dart` for host behavior. On an Android
device, run `PlayerWidgetTest` and check play/pause, skip, cold launch, resizing, appearance
and local cover changes while backgrounded. There is no iOS widget target in this fork.
