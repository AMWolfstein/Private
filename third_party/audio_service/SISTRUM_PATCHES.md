# Local audio_service 0.18.19 patch

Source: the published `audio_service` 0.18.19 package (MIT; see LICENSE).
Only runtime sources are vendored. This replaces the same dependency, without
adding another playback engine or native SDK.

- Android: include custom media actions in MediaStyle notifications on Android
  12 and older. Upstream exposes them only through PlaybackState, which hides
  them on those versions. Keep custom action order and compact indices aligned.
- Android: allow a custom action to supply an explicit in-app activity class
  using the `sistrum.activity` extra. Its notification PendingIntent opens the
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
- Android (upstream %4D%6F%72%6E%79%65 `463c2ce9`): prepare metadata artwork off the main
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


## Local Android Auto extension (2026-11-01)

Source checkpoint: `1b694df8`; upstream reference Mornye v5.3.0
`afee4332a257f1b6aeb288229eddf04ac0777b3c`.

- `AudioServicePlugin` offers a pre-Dart shared-engine configurator. The app
  registers playback/SAF/cover channels with application context, so a car can
  initialize the existing player without an Activity. Renderer argument policy
  and trusted-browser policy remain intact.
- Queue descriptions map allowlisted app-owned artwork to read-only content
  URIs through the app-supplied `QueueArtResolver`. Main metadata retains its
  original URI. Missing/recycled queue bitmaps cannot invalidate the queue.
- `MediaArtwork` bounds decoded session art to 512px and creates independent
  bitmap copies for metadata keys, queue descriptions and notifications. Text
  metadata remains available if an image is recycled or rejected.
- `RecentArtCache` holds at most three bounded decoded covers and preserves only
  the current entry on memory trim. Consumers do not recycle borrowed bitmaps.
- Adapted upstream helpers retain their LGPL notices; complete terms and
  attribution are registered by the application in
  `assets/licenses/android_auto.txt`. Existing vendored license remains intact.

Verification: vendored JVM tests **11 passed**; app JVM tests **93 passed,
1 skipped**. Full Flutter suite **2,349 passed, 3 skipped, 0 failures** and
analysis clean. Instrumentation sources compile, but bitmap IPC behavior,
headless playback and car/OEM lifecycle behavior were **not tested on a device**.
No APK was built. See `docs/ANDROID_AUTO.md` for architecture and limitations.


## Queue publication coalescing (2026-11-01)

Adapted upstream `4eaa5eff` in source `bad86c09`: only Android receives the full
session queue. An idle change publishes immediately; while a native setQueue
request is pending, intermediate queues are replaced with the newest snapshot.
The latest pending queue publishes after completion or failure, retaining its
ordering relative to item/state calls. App-side queue streams are unchanged.
Adapted platform tests cover complete queues, platform exclusion, burst
coalescing, failure recovery and item/state ordering. App runtime additionally
installs an Android-only media-state extrapolation filter; vendor playback
state APIs are unchanged. Full Flutter **2,377 passed / 3 skipped**, analysis clean.
