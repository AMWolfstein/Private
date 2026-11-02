# Local Library song analysis

Implemented 2026-11-02 on the existing local/offline Android player. This
completes the Mornye v5.3.0 library scheduler and controls omitted from the
previous refill-only acoustic adaptation. Reference tag:
`afee4332a257f1b6aeb288229eddf04ac0777b3c`.

## Location and controls

Local Library now lists **Song analysis** immediately after **Tag separators**.
Both rows have descriptions. Song analysis opens its own settings page with:

- **Song analysis:** enables local acoustic analysis and matching for Autoplay.
  It reuses the existing `autoplaySoundMatching` preference, so the previous
  opt-in is preserved. It remains off by default.
- **Only while charging:** on by default; controls library sweeps. The selected
  song is analyzed after its own delay even on battery. This preference is
  serialized with existing AppSettings and survives restart/backup.
- **Clear song analysis:** shows a successful-analysis count and progress bar,
  asks for confirmation, cancels/invalidates old work and clears derived acoustic
  records. It does not delete music, playlists, listening history or the
  personalization model. An enabled sweep subsequently starts again.

The former Match the sound row is removed from Playback to avoid duplicate
controls. Settings search points analysis/charging/clear results to Local Library.

## Execution and ownership

`MusicPlayerRuntime` owns `SongAnalysis`, including headless playback. The UI
uses an injected provider; opening/reopening the page refreshes counts, and a
library-index change refreshes them while observed. Runtime configuration forwards
settings, and disposal cancels owned timers, decoder/native requests and stream
subscriptions before waiting for in-flight work to settle.

The scheduler adapts upstream `song_analysis.dart`, `song_analysis_store.dart`
and `song_feature_analyzer.dart`:

- Startup sweep delay: 90 seconds; enabled/settings-change restart: 10 seconds.
- Current-source analysis delay: 20 seconds, independently of charging policy.
- One analysis at a time, one FFmpeg decoder thread, at most two 24-second mono
  windows at 22,050 Hz. Unknown durations try offsets 30/90 seconds; short songs
  use a central window. Native MFCC/tempo/key extraction is unchanged.
- Each decode has a 30-second cancellation deadline. Temporary PCM is deleted
  in `finally`; FFmpegKit owns its read-only SAF input. No audio is persisted or
  uploaded. CUE virtual sources and network URLs are not swept.
- Sweeps defer for recent track changes/AutoMix work, recheck external power
  before starting each file (including after a busy wait), and rest at least two
  seconds plus four times the previous job duration.
- Charging is read from Android's sticky battery broadcast through both the
  Activity and shared headless channels. Full batteries on external power count
  as plugged in. An unavailable probe fails closed for library sweeps.
- Charging is rechecked after five minutes when unavailable; repeated decoder
  unavailability backs off for an hour. Completed passes revisit after 30 minutes.
  A file already in progress can finish after unplugging; the next file checks
  power again. There is no new WorkManager job or wake lock: work resumes with
  the app/playback runtime and remains subject to Android process lifetime.

## Persistent records and progress

The earlier 512-entry JSON cache is replaced by `song_analysis.db`, a separate
SQLite database of source/version/stamp plus 42-float descriptor records. Retired
JSON summaries are no longer consumed; derived results are recomputed. Library
planning reads 500-row pages; features/records/removal requests bind at most 450
paths per statement. There is no 512-song eviction cap. Autoplay reads the same
records and validates file identity with at most four concurrent probes.

Successful and failed analyses retain the file identity and algorithm version.
Unsupported files are not retried repeatedly until identity/version changes or
analysis is cleared; unavailable/cancelled work remains retryable. Files changed
during extraction are not published. SAF documents without trustworthy identity
are skipped. Counted results refer to successful current-version library records;
a changed file is invalidated when read/played, so totals do not stat every audio
file on each UI rebuild. Removing library files prunes obsolete records during a
sweep, while retaining the current source.

Clear is serialized behind in-flight extraction. A revision guard rejects
pre-clear progress snapshots; retired sweeps cannot increment the reset counter.
SQLite deletion requests incremental vacuum. Preferences and source audio are
stored separately and are unaffected. Progress is zero rather than NaN for an
empty library.

## Verification

Source checkpoint: `44219a8c`. Verification: `flutter analyze` **No issues found**;
full `flutter test` **2,404 passed / 3 skipped / zero failures** (5m47s);
Android host app tests **95 passed / 1 skipped / zero failures**. Graph checkpoint
`453d697d`: **28,939 unique nodes / 55,334 links / zero dangling endpoints**,
built from `44219a8c`; existing vendor/generated-file extraction limitations remain. The full suite
initially exposed a settings test tapping an offscreen Auto Scan row after the
new descriptions changed layout; the test now scrolls to a hit-testable target,
and the focused and complete reruns passed. Tests cover
charging/battery policies, enabling/disabling, current-track analysis, owned
cancellation, failures/backoff, file changes, late snapshots after clear,
SQLite/version/clear behavior and more than 512 stored descriptors. UI tests
cover exact navigation placement/descriptions in light/dark, preference persistence,
progress, empty libraries and confirmed versus cancelled clearing. Android JVM
tests cover external-power flags.

No APK, emulator or physical phone execution was requested for this correction.
Real SAF providers, charger transitions, process restrictions and device battery/
CPU cost remain device acceptance checks. Existing release APKs predate this work.

Adapted service/store/analyzer and tests retain LGPL-3.0-only notices and complete
in-app terms in `assets/licenses/autoplay_learning.txt`. No package dependency,
audio-engine migration, Rust algorithm or remote service is introduced.
