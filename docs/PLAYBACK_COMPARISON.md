# Playback settings and recommendation learning comparison

Reviewed 2026-11-02 against a freshly fetched upstream main at
`7db0fc76f6cfeaef903327ebc73e13d9bdc3d936`. This is a source comparison,
not a device sound-quality or perceptual recommendation benchmark. Upstream
paths below are relative to that snapshot; Sistrum paths refer to this checkout.
No additional comparison recommendations were automatically implemented.

## Implemented in this batch

### Reset recommendation learning

Upstream's addition is a score-weight learner, not just a caption:
`lib/services/autoplay_ranker.dart` (introduced by `05b0ec3b`). The Playback
summary at upstream `lib/screens/settings/playback_settings_page.dart:110`
reports the learner's actual evaluation. Adapted the ranker and its tests,
with attribution in the existing in-app LGPL notice.

- The first feedback on a remembered Autoplay pick records its score components,
  reward, weight and timestamp. Manually selected songs do not become ranker
  outcomes. Existing personalization still learns the existing broader feedback.
- Starting score-component multipliers remain 1. At 40 outcomes, train on earlier
  outcomes and compare against the latest quarter (at least 10) held out. Use
  learned multipliers only when their held-out AUC is at least as good as the
  starting ranking. This is pair-order AUC, not a probability of liking a song.
- Learn on a worker isolate, retrain every 10 new outcomes, cap persisted outcomes
  at 2,000 and remembered picks at 200. Outcome rows contain score components,
  not file paths; source identities remain only in the bounded pending-pick map.
- The UI displays progress toward 40, waiting for both kept/skipped outcomes,
  learned versus standard percentages, or fallback to standard ranking. It
  observes the runtime's evaluation rather than displaying an invented count.
- Reset confirmation clears existing preference learning plus the ranker log,
  pending picks and learned weights. A generation guard rejects training that
  finishes after reset. Clear failures reach the UI and permit a retry.
- The player runtime owns the feedback subscription and ranker, forwards only
  opted-in feedback, flushes at playback lifecycle boundaries and disposes its
  work. Disabling personalization stops applying learned score weights.

Sistrum keeps its current local candidate-selection and acoustic APIs; the
ranker weighs their actual components (artist, album, genre, preference, recent
plays, repeated artists and acoustic score/transition). It does not import the
additional upstream session-diversity or taste features described below.

Implementation: `lib/services/playback/autoplay/autoplay_ranker.dart`,
`lib/services/playback/autoplay/music_player_autoplay.dart`,
`lib/services/playback/music_player/music_player_runtime.dart`,
`lib/screens/settings/playback/playback_settings_auto_mix_confirm.dart:61`.

### Gapless playback control

The native Android handoff already existed, but it had no exposed preference.
Added the upstream title/description and switch immediately before AutoMix.
It is off/disabled while AutoMix is on, retains its stored preference, and is
also disabled for USB direct/bit-perfect and exclusive output. The native handoff
now checks the preference. Turning it off cancels a prepared link and releases
its incoming deck; ordinary track completion remains available.

`gaplessPlayback` defaults to true, preserving the existing always-on handoff
when AutoMix is off. It round-trips through settings, backups and restoration;
search includes it. No engine replacement or new package/native dependency.

Implementation: `lib/screens/settings/playback/playback_settings_auto_mix_confirm.dart:141`,
`lib/services/playback/automix/music_player_automix_generation.dart:4`,
`lib/services/playback/music_player/music_player_service_session_handlers.dart:19`.
Upstream UI: `lib/screens/settings/playback_settings_page.dart:224`.

## Further improvements to existing Autoplay and personalization

Scope: improvements to features Sistrum already has, as clarified by the owner.
These are confirmed implementation differences; no measured improvement in this
fork is claimed. These recommendations develop the existing Autoplay and
personalization features; they are not a list of unrelated missing features.

| Priority | Upstream improvement | Sistrum now | Evidence and suggested scope |
|---|---|---|---|
| 1 | Spread candidate sampling across the library instead of taking one large contiguous page. | Up to 128 artist-search rows plus one 256-row random-offset page; a page can favor one recently added album/artist. | Upstream `lib/services/music_player_autoplay.dart:27` uses eight 48-row pages plus up to 32 seed-artist rows. Current `lib/services/playback/autoplay/music_player_autoplay.dart:37`. Adapt only local SQL sampling, test bounded reads and artist/album diversity; exclude network availability paths. |
| 2 | Session-aware genre relevance and stronger artist/album variety. | Genre match uses the seed's whole normalized genre tag. Repeated selected artists lose four points, without a four-song spacing rule or album penalty. | Upstream `lib/services/music_player_autoplay.dart:127` and `:226` weight genres from the latest 12 session songs; `:328` spaces artists when alternatives fit and `:380` discourages repeated albums. Current `lib/services/playback/autoplay/music_player_autoplay.dart:155` and `:218`. Adapt as a separate ranking batch with small-library fallback and deterministic tests; preserve explicit user queues. |
| 3 | Learn which songs/artists are listened to together, beyond acoustic similarity and artist/genre preferences. | Existing AdaGrad/exploration personalization, acoustic matching and the new component-weight ranker; no co-listening vector model. | Upstream `lib/services/autoplay_taste.dart:15`, `:105`, `:530` and upstream `lib/services/music_player_autoplay.dart:500`. This is a separate local model/log, with a 50-play cold start, not the 40-outcome ranker. Evaluate worker/retention/reset/lifecycle costs before adapting. It would need to join Reset explicitly. |

There is no additional missing core Android playback toggle in the sections
compared after this batch: normalization, haptics, AutoMix, Autoplay,
personalization, pause at zero volume, headphone connection behavior and native
output controls have corresponding local implementations. This does not claim
that every backend implementation is byte-for-byte equivalent.

## Other existing Playback features checked

| Existing feature | Improvement assessment |
|---|---|
| Equalizer | Both expose the 5–31-band/tone/dynamics model. Sistrum's Mornye-style EQ adaptation was completed previously; see `docs/PLAYER_CONTROLS_AND_EQUALIZER.md`. No additional control improvement found in the compared Playback entry. This was not a new comprehensive DSP audit. |
| ReplayGain normalization | Both offer track/album mode and preamp. Compared upstream `lib/widgets/playback_normalization_settings.dart` with local `lib/widgets/settings/playback_normalization_settings.dart`: no additional active Mornye-theme setting found. |
| Music haptics | Both have sensitivity and strength controls. Compared upstream/local `music_haptics_settings.dart`: no additional active Mornye-theme control found. |
| AutoMix | Compared upstream `lib/widgets/automix_settings.dart` and local `lib/screens/settings/playback/playback_settings_auto_mix_effects.dart`: automatic/manual duration, transition effects and custom controls are present. No extra setting identified. Full audio-engine equivalence/performance was not tested by this page review. |
| Gapless playback | This batch completes the exposed on/off preference and its interaction with AutoMix on top of the native handoff already present. Audible/device continuity remains a device check. |
| Song analysis | This batch's predecessor already added the scheduler, charging policy, clear and progress. Its location stays Local Library > Song analysis as requested; see `docs/SONG_ANALYSIS.md`. |
| Pause at zero volume / headphones | Corresponding switches exist in both Playback pages. No additional control found in the compared upstream section (`lib/screens/settings/playback_settings_page.dart:335`). |
| USB / exclusive output | Compared the Android section at upstream `lib/screens/settings/playback_settings_page.dart:472` with local `lib/screens/settings/playback/playback_settings_auto_mix_confirm.dart:255`: native-output switches, DSD transport, hardware-volume controls and status text are present. No additional setting found; this is not a new hardware compatibility measurement. |

Only the improvements to existing Autoplay/personalization listed above are
recommended from this comparison. Page organization, other platforms and removed
features are outside the owner's requested improvement list.

## Verification

Source checkpoint: `e8e7668c`. `flutter analyze`: **No issues found**. Full Flutter
suite: **2,419 passed / 3 skipped / zero failures** (5m45s). Focused controls,
ranker, queue-weighting and runtime-binding tests: **31 passed**; the real-worker
runtime regression also passed separately. The first complete run exposed a host
reset test without an injected ranker database; it now uses real in-memory SQLite
and the complete suite was rerun successfully. No Android/Rust/C++ source changed
in this batch, so no native build or hardware test is claimed. Graph checkpoint
`d91edba9`: **29,047 unique nodes / 55,500 links / zero dangling endpoints**,
built from `e8e7668c`; existing vendored/generated extraction limitations remain.
Focused tests cover ranker fitting/AUC/holdout fallback, persistence/first-feedback
semantics, late-training reset guards, failed-clear retry, real score-weighted
picks, runtime feedback/reset/opt-out, Gapless disable/cancellation, settings
round trips and live descriptions/AutoMix gating in light and dark themes.
No APK or physical-device run in this batch. Audible gaplessness, OEM behavior,
recommendation quality and device CPU/battery costs remain unmeasured.
