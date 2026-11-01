# Local playback additions (2026-11-01)

These additions run on the current Flutter/audioplayers Android engine. They do
not depend on the planned Kotlin/Media3 migration. No online discovery, remote
artwork, account, download or network analysis is introduced.

## Local library mixes

Home's **Made from your library** shelf offers a daily mix, favorites, fresh
finds, and artist/genre/decade mixes when enough matching songs exist. Tapping a
card plays its real library rows through the existing queue controller.

The provider reads at most three 500-row pages, spaced across the enabled
library. This is a representative sample for large libraries, not an exhaustive
scan. It refreshes on library-index changes, favorites changes, Home refresh,
and midnight while observed. Daily shuffling is deterministic; mixes contain
at most 40 distinct local sources, with at most ten cards. Artist balancing
applies except to artist-specific and newest-first selections. Highly overlapping
cards are suppressed; small libraries can legitimately have fewer cards.

## Local learning

The existing hashed AdaGrad model now also learns artist/genre Beta arms and
uses Thompson sampling per refill. It learns from audible listening, meaningful
skips, intentional replay, and successfully committed loves/playlist additions.
Loading, restoring and importing collections do not manufacture endorsements.
A scoped library event source connects to learning in the app shell; the library
never imports the playback implementation, and feedback never creates a player.

Learning remains controlled by **Learn from listening**, independently of the
statistics opt-in. The same reset clears the model. Version-1 models are accepted
and migrated to the version-2 snapshot with bounded arms (maximum 2,048). The two
regression arrays still occupy 64 KiB; arms add bounded storage. Model persistence
contains hashed features, not raw names, file paths or audio.

The personalization implementation and its upstream tests are adapted from
Mornye v5.3.0 (`afee4332a257f1b6aeb288229eddf04ac0777b3c`), specifically
`lib/services/autoplay_personalization.dart` and
`test/autoplay_personalization_test.dart`. Relevant upstream changes include
`c4b98bba` and `5bc71671`. The adapted implementation/tests retain LGPL-3.0-only attribution;
`assets/licenses/autoplay_learning.txt` packages the notice and complete terms
for the in-app Licenses page. Other files keep their existing licenses. Other additions adapt the feature concepts to Sistrum's existing
modules; no whole upstream player or networking subsystem is transplanted.

## Acoustic Autoplay matching

The initial six-measurement adaptation is superseded by native MFCC, tempo,
key and energy descriptors with confidence-aware transition matching. The
existing optional **Playback > Match the sound** preference, bounded scheduling,
SAF ownership and cancellation remain. The version-2 cache rejects obsolete
summaries and audio edits. See `docs/UPSTREAM_530_FOLLOWUP.md` for current window
selection, cache/ranking limits, upstream comparisons and verification.

## Lyrics timing

**Lyrics > Lyrics timing** adjusts display timing from -2 to +2 seconds in
100 ms steps. Negative values show lyrics earlier. Changes preview immediately,
persist on release, and reset to zero. The preference survives app restarts.

Lead/backing lines, words, romanization, instrumental countdowns and the line
above the seek bar follow the same offset. Parsed/exported source lyrics remain
unchanged. Tap-to-seek and share callbacks keep original song timestamps.
The preference uses the existing theme-preference persistence, like lyric text
size; the app's settings-only backup currently excludes these appearance
preferences. It is not a per-song offset or a lyric-file edit.

## Gapless on the existing Android player

When AutoMix is off, ordinary Android playback prepares the next deck in the
last 30 seconds and links it using `MediaPlayer.setNextMediaPlayer`. Android's
audio clock starts the next source; Dart adopts the already-running deck,
updates metadata/history/session state and retires the outgoing deck. No Dart
completion timer or crossfade is used to claim gapless playback.

The implementation shares AutoMix's generation checks, cache pins, normalization,
queue ownership and disposal. Seek, pause, focus loss, output/settings changes,
repeat-mode changes, queue edits and disposal unlink the next deck. Preparation
failure falls back to existing completion behavior. Repeat-one, direct USB,
bit-perfect, exclusive output and DSD retain their existing playback paths.
The vendored Android plugin remains MediaPlayer-based; no audio engine is
replaced. The native next-player API is available since Android API 16, below
the project's supported minimum, and adds no ABI-specific library.

## Verification

Host tests cover deterministic/local/diverse mixes, sound descriptors and cache
invalidation, model migration/feedback/exploration, lyric persistence and offsets,
and native-handoff orchestration/cancellation. The vendored Android Kotlin code
is compiled through its library unit-test task; that library currently has no
JVM unit-test sources, so a successful task is not a native behavior test.

`integration_test/playback/gapless_native_handoff_test.dart` is an Android device
check that verifies the incoming deck advances without a Dart resume command.
It has not been run here. Audible boundary continuity, codec delay/padding,
Bluetooth/USB routing, headset interruptions and CPU/battery cost require device
verification. Host tests cannot establish a measured zero-silence boundary.

Final host outcomes:

- `flutter analyze`: **No issues found**.
- `flutter test`: **2,321 passed, 0 failed, 3 skipped**.
- `:audioplayers_android:testDebugUnitTest`: **BUILD SUCCESSFUL**; Kotlin compiled,
  JVM test task **NO-SOURCE**.
- Android device integration/acoustic measurements: **NOT RUN**.

The progress tracker and upstream-port list record the source checkpoint.
No APK build or GitHub push is part of this implementation task.
