# Local Android audio patch

Based on audioplayers_android 5.3.0 (license retained in LICENSE).

`UrlSource` duplicates app-owned `/proc/self/fd/<fd>` sources and passes the
descriptor directly to MediaPlayer. Android AppFuse proxies, including remote
SAF providers, permit only the original open; reopening the proc path fails.
The caller must hold the original lease until source preparation completes.
Other URLs and file paths retain upstream behavior.

## Output failure handling (upstream f426b2d1, local 6e44c6be)

MediaPlayerWrapper skips initial normal-speed PlaybackParams, explicitly starts playback,
and restores 1.0 after a non-default speed. WrappedPlayer clears prepared/playing state,
releases focus and reports AndroidAudioError as handled so Android does not also deliver
an error as completion. Dart forwards the output error, retains the selected song and
supports Play retry; failed output must not automatically advance the queue.
No equalizer code/dependencies were imported from upstream. The existing descriptor lease
patch above is retained. Device MediaPlayer behavior still needs physical-device testing.

## Native gapless handoff (2026-11-01)

`setNextPlayer` links two prepared ordinary MediaPlayer wrappers through
`setNextMediaPlayer`. The wrapper marks the already-started incoming player as
playing on outgoing completion and avoids stop/seek/focus release during that
handoff. Dart owns generation validation, unlinking on cancellation and deck
disposal; USB/direct and exclusive paths do not use this link. The API is
available since Android API 16 and introduces no native ABI dependency. The Android
Kotlin library compiles, host orchestration/cancellation tests cover the Dart
owner, and a separate Android integration test is supplied. Acoustic continuity
and OEM behavior remain unverified on a physical device.
