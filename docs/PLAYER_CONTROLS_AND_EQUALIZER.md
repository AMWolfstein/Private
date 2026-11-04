# Player controls and Mornye equalizer UI

Implemented on the current local/offline Android player, 2026-11-01.
Upstream reference: Mornye v5.3.0 (`afee4332a257f1b6aeb288229eddf04ac0777b3c`).

## Show or hide the volume slider

Now Playing's ellipsis menu offers Hide volume slider / Show volume slider.
The default remains visible. The choice applies to Normal and Immersive layouts,
in portrait and landscape, and is persisted in AppSettings, including its existing
serialization/backup path. The row and its adjacent gap disappear when hidden.
The menu remains available to restore it. Toggling visibility never writes the
system volume or changes playback, DSP or hardware-key behavior.

Adapted feature: upstream `c489960b`.

## Equalizer comparison and UI port

The target's `EqualizerSettings` model already matches the upstream v5.3.0 model;
band interpolation, tone controls, automatic headroom, limiter and compressor
settings were already present. Existing playback/native DSP and headless EQ
bootstrap remain the owners of applying those settings. This change ports the
upstream Mornye presentation and missing UI affordances, rather than replacing
that audio implementation.

- Master enable row, bypass explanation and visible persistence/native errors.
- Overview with the matching preset name, band count, effective input gain and
  the upstream logarithmic response chart with axes/control points. It is an
  estimated curve, not a measured device response.
- Preset picker with selected checkmark, custom-preset deletion, save/import/share
  actions and save feedback. The preset dialog owns/disposes its text controller.
- 5/10/15/31-band segmented selector and responsive vertical faders. Dense rows
  scroll horizontally rather than squeezing all knobs into an unusable width.
  Each gain label resets that band to zero when tapped; frequency/value labels
  and accessible step controls follow upstream.
- Grouped preamp/effective preamp, bass, treble and balance controls; automatic
  headroom, limiter and compressor controls, with threshold/ratio/attack/release
  shown when the compressor is enabled.
- Confirmed reset at the bottom preserves the master enabled state. Settings can
  be prepared while bypassed, as in upstream. Bottom inset follows shell navigation.

Source UI: upstream `lib/screens/equalizer_screen.dart`, `equalizer_widgets.dart`
and `equalizer_curve.dart` at the reference tag. Only the Mornye layout is adapted
onto existing App settings, segmented controls, faders, dialogs and icon mapping.
No Material/Expressive renderer or desktop UI dependency is imported. Existing
Sistrum package identities and preset export format remain. Import accepts the
current format and upstream Mornye/legacy formats; the original streaming 64 KB
UTF-8 input cap is retained instead of an unbounded file read.

Adapted EQ sources retain their LGPL-3.0-only attribution. Complete terms and
notices are included in the already registered `assets/licenses/autoplay_learning.txt`.

## Verification

Source checkpoint `e555a7f8`. Full `flutter test --reporter expanded`: **2,386 passed / 3 skipped / zero failures** (5m41s). `flutter analyze`: **No issues found**. Focused EQ tests also pass. No Rust/Kotlin/C++ production source changed; native host checks were not repeated for this UI-only batch.
Graph checkpoint `4fcac150`: **28,759 unique nodes / 55,026 valid links**, no dangling endpoints; existing vendor extraction warnings remain.

Targeted widget tests cover portrait/landscape Normal/Immersive visibility,
restart persistence without volume writes, narrow large-text EQ
layout, band-count/gain edits, individual reset and compressor edits. Preset
parser, persistence, upstream format and playback bypass/error tests are retained.
Host previews with the app font were inspected in light and dark modes.

No APK, emulator or physical-device execution is part of this change. Actual
Android DSP response, listening quality and GPU frame-time/battery effects were
not measured. Prior Android Auto/device acceptance checks remain pending.
