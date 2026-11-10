# Verified dead-code cleanup

Branch: `Mornye-reboot5`. Baseline: `32248ff34a3f1c6d6e184f531fb35f2397c03183`.
The owner requested verification and cleanup in one commit. This report accompanies that commit.

## Removed

The 12 confirmed audit groups were rechecked against callers, generated/part code,
platform entry points and tests before removal:

- Unreferenced `PlaybackEngine` enum and obsolete MediaKit/AVPlayer comments.
- Obsolete `PlatformBridge.castCall`, unused `CastOutput.position` wrapper and private `_MusicFailures.playNext` wrapper. Active Cast commands/play-next paths remain.
- Unread `LastfmService.initialized` getter and never-accessed `MusicPlayerRuntime.lastfm` lazy accessor, with its unreachable backing-field cleanup. Lastfm implementation and tests remain.
- Unread `PlaybackDependencies.convertAudio`/`playbackCopies` and unused conversion default. Actual FFmpeg conversion and playback fallbacks remain.
- Uncalled `TrackListTile.activate` helper; active `_TrackItemWithStatus.activate` remains.
- Old `_WhatsNewDialog`, its state and private tab widget. Routes, About and tests use the current `WhatsNewScreen`.
- Unconstructed extension keyring-mode exception/enum. Secure-storage key validation, encrypted-data preservation and migration remain.
- Uncalled `showAppSheetDialog` wrapper. The distinct `AppSheetDialog` surface remains.

Removed 14 previously reported unread fields/callbacks, with corresponding constructor
parameters and call-site arguments: preset onApply, shelf inset, top-result context
menu, route-device mixerBitPerfect, album moreMenu/onAddToPlaylist, skeleton showQuality,
audio-facts softwareVolume, artist showTitleListenable, two track-card context-menu
callbacks, and three unused extension-restore summary outputs. Restore failure counts
and all actual installation/settings operations are preserved. Native JSON fields and
native interfaces were not changed.

Also removed the newly orphaned cover-save input on the top collection card and private
menu/playlist helpers reachable only through discarded callbacks. The obsolete
`SelectionModeMixin.showSelectionMenu`/`applySelectionClick` chain, constant-false
menu-only flags, write-only mixin anchor and unused `track_lists/list_selection.dart`
adapter were removed after tracing all references. Active mobile selection, queue/log
range selection and `ordered_range_selection.dart` remain.

The unsupported-format tests no longer inject an unused converter, fake AVPlayer flag
or playback-copy directory. The no-transcoding assertion now watches the real FFmpeg
platform channel rather than an unconsumed dependency callback. Existing queue,
error-state and missing-file assertions remain.

## Verification

- Dart formatting: affected existing Dart files formatted; `git diff --check` clean.
- Final `dart analyze`: no issues.
- Final targeted Flutter run: 129 affected test files, **1,151 passed**, no failures.
  Command: `flutter test --no-pub --concurrency=4 --timeout=120s -r expanded <selected files>`.
  Selection covers playback, Cast, Lastfm, extensions, download queue/history,
  album/artist/search/header UI, selection, queue and library-directory behavior.
- Full configured Android unit command: `bash android/gradlew -p android testDebugUnitTest --continue`,
  **BUILD SUCCESSFUL** on Java 25. Current XML reports: 635 tests, 633 passed,
  2 skipped, zero failures/errors; Gradle reused up-to-date tasks where valid.
- Fresh independent read-only review: **CLEAN**. It checked surrounding callers,
  removed callbacks and transitive selection/menu cleanup; reviewer did not run tests.
- Final CodeGraph map: current, 1,868 files (1,768 indexed, 95 resource-indexed,
  5 shell-indexed), no map problems. A preliminary overlapping refresh correctly
  blocked on changed source; the final frozen-source refresh succeeded.
- Incremental dartograph scan: 44 original raw findings reduced to 19. Eighteen
  remaining reports have direct setter/override/test/polymorphic references;
  the other is the retained ShareIntentService lifecycle hook. Native-worker
  false positives from the independent ciach audit were checked manually and retained.

No Rust/Kotlin/C++ source, exported signature, Android manifest, dependencies,
lockfiles, database schema, migrations or application UI behavior was changed.
Previous baseline Rust all-target checks, NDK Clang checks and 18/18 JNI correspondence
were preserved; they were not rerun as new native checks for this Dart-only change.
The complete Flutter suite was not rerun after cleanup; the affected suite above was.
No APK build or physical-device verification occurred.

## Intentionally retained

- `app_links`: missing Dart imports do not establish absence of native plugin/intent
  effects; dependency removal needs a separate validated intent-flow change.
- Cupertino icon fonts, code generation, analyzer plugin and icon-generation tooling:
  concrete non-import uses invalidate the dependency-tool findings.
- Explicit test hooks, private prevent-instantiation constructors, rendering setters,
  polymorphic overrides, active native worker/Cast/audio/FFmpeg paths and migrations.
- `ShareIntentService.dispose`: retained as a lifecycle hook for an active stream-owning
  service; no lifecycle redesign was included in dead-code cleanup.
- Pre-existing untracked `extensions/` node_modules residue: untouched and not committed.

Java 25 test compatibility/cache configuration remains local under the cloud Gradle
user home. It is not part of the application or this commit. No Java 21 override remains.
