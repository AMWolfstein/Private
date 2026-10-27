# Local audio_service 0.18.19 patch

Source: the published `audio_service` 0.18.19 package (MIT; see LICENSE).
Only runtime sources are vendored. This replaces the same dependency, without
adding another playback engine or native SDK.

- Android: include custom media actions in MediaStyle notifications on Android
  12 and older. Upstream exposes them only through PlaybackState, which hides
  them on those versions. Keep custom action order and compact indices aligned.
- Android: allow a custom action to supply an explicit in-app activity class
  using the `spotiflac.activity` extra. Its notification PendingIntent opens the
  output picker directly. These activity controls are excluded from
  PlaybackState custom actions: background launches from media-session binder
  callbacks are blocked on newer Android. Use its native output switcher.
  This is only for app-owned controls, not extension input.
- Android: bound retained browser metadata to 256 recent items with
  `PinnedMetadataCache`. The active queue and current item stay pinned so
  notification, Android Auto and browser lookups survive recent-item eviction.
  Replacing the queue and clearing the service release their pinned metadata.
- Android (upstream `205e178e`, local `fa838caa`): accept renderer arguments via
  `AudioServicePlugin.setFlutterEngineArguments` before shared engine creation.
  Application startup supplies the existing device compatibility flags, including
  the scoped Xiaomi/Android 15 workaround. Arguments are copied and late changes
  rejected so Activity recreation cannot silently reconfigure the cached engine.
- Android (upstream Mornye `463c2ce9`): prepare metadata artwork off the main
  thread, then publish metadata, artwork and the notification on the main
  looper, and refresh the playback state's media ID without changing position
  or controls, so late artwork or tags reach the notification, lock screen and
  Android Auto. Instrumentation test `MediaControlMetadataTest`.
- iOS: allow the active music handler to re-publish retained Now Playing
  metadata after restoring its audio session on app lifecycle/video changes.
  Refresh keeps artwork and extrapolates elapsed time without restarting audio;
  it never activates the audio session or revives a stopped service.

Android 13+ still chooses the positions and built-in transport icons in System
UI. We preserve real play/pause/previous/next semantics for headsets, lock screen
and Android Auto instead of disguising them as unrelated custom actions.

When upgrading, compare these changes against the matching upstream files.
