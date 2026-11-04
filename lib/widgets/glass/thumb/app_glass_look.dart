import 'dart:ui' show ColorFilter, ImageFilter;

import 'package:flutter/painting.dart' show Color;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart' show GlassFinish, GlassOptics;
import 'package:sistrum/core/theme/app_glass_levels.dart';

/// The visual identity Glass Engine V2 draws with. Both looks use the same
/// four modes, the same host capture and the same shaders; only parameters
/// differ.
enum AppGlassLook {
  /// Sistrum's own glass: the default.
  sistrum,

  /// Inspired by BitChord's liquid glass (`ui/components/LiquidGlass.kt`):
  /// a deeper lens at the rim, a lighter blur, BitChord's 0.4 surface tint,
  /// a saturation lift under frosted glass, a light hairline edge and a
  /// chromatic fringe at the rim.
  bitchord,
}

/// Developer-only for now: switched from the performance HUD and never
/// persisted, because Appearance has no glass controls (AGENTS.md). Every
/// launch starts at [AppGlassLook.sistrum].
class AppGlassLookNotifier extends Notifier<AppGlassLook> {
  @override
  AppGlassLook build() => AppGlassLook.sistrum;

  void toggle() => state = state == AppGlassLook.sistrum
      ? AppGlassLook.bitchord
      : AppGlassLook.sistrum;
}

final appGlassLookProvider =
    NotifierProvider<AppGlassLookNotifier, AppGlassLook>(
      AppGlassLookNotifier.new,
    );

/// BitChord's lens, in g1455's terms: it refracts a band 0.5 x 48 dp in from
/// the rim (`LENS_HEIGHT * LENS_MAX_DP`), against g1455's default 21, and
/// displaces up to 24 dp there, which on g1455's own falloff is about
/// six sevenths of its default strength (~28 pt at 3 pt in). A translation of
/// the behaviour, not a copy of its shader.
const _bitChordOptics = GlassOptics(thickness: 24, strength: -50);

/// BitChord's blur: `BLUR_RADIUS_DP = 8`, a radius in Android's
/// `RenderEffect` terms, which is sigma 0.57735 r + 0.5 = 5.1 dp (sampled
/// at a third of the resolution, which does not change its logical size).
/// The owner allowed this below Sistrum's sigma 6 for this look only
/// (2026-11-04).
const kAppBitChordBlurSigma = 5.0;

/// The blur sigma of FROSTED and LIQUID glass for [look].
double appGlassBlurSigma(AppGlassLook look) => switch (look) {
  AppGlassLook.sistrum => kAppGlassStyle.blurSigma,
  AppGlassLook.bitchord => kAppBitChordBlurSigma,
};

/// BitChord's surface tint (`SURFACE_OPACITY = 0.4` of `#121212` dark or
/// `#FAFAFA` light), or null for Sistrum, whose own fills apply.
Color? appGlassLookFill(AppGlassLook look, {required bool dark}) =>
    switch (look) {
      AppGlassLook.sistrum => null,
      AppGlassLook.bitchord =>
        dark
            ? const Color.fromRGBO(0x12, 0x12, 0x12, 0.4)
            : const Color.fromRGBO(0xFA, 0xFA, 0xFA, 0.4),
    };

/// Whether the rim draws a chromatic fringe: BitChord's lens disperses red
/// and blue apart at the edge, most at the corners; g1455's shader cannot, so
/// the rim paints it (see `AppGlass`).
bool appGlassChromaticRim(AppGlassLook look) => look == AppGlassLook.bitchord;

/// The finish of every LIQUID surface for [look]; the fill above it sets the
/// colour in both looks.
GlassFinish appLiquidGlassFinish(AppGlassLook look) => switch (look) {
  AppGlassLook.sistrum => _sistrumFinish,
  AppGlassLook.bitchord => _bitChordFinish,
};

final GlassFinish _sistrumFinish = GlassFinish(
  name: 'clear',
  blurSigmaLogical: kAppGlassStyle.blurSigma,
  tint: const Color(0x00000000),
);

final GlassFinish _bitChordFinish = GlassFinish(
  name: 'clear',
  blurSigmaLogical: kAppBitChordBlurSigma,
  tint: const Color(0x00000000),
  optics: _bitChordOptics,
);

/// BitChord's vibrancy (`colorControls(saturation = 1.5)`), as a colour
/// matrix: Rec. 709 luminance weights.
const _saturation = 1.5;
const _lr = 0.2126 * (1 - _saturation);
const _lg = 0.7152 * (1 - _saturation);
const _lb = 0.0722 * (1 - _saturation);
const _vibrancy = ColorFilter.matrix(<double>[
  _lr + _saturation, _lg, _lb, 0, 0, //
  _lr, _lg + _saturation, _lb, 0, 0, //
  _lr, _lg, _lb + _saturation, 0, 0, //
  0, 0, 0, 1, 0, //
]);

final ImageFilter _sistrumFrost = ImageFilter.blur(
  sigmaX: kAppGlassStyle.blurSigma,
  sigmaY: kAppGlassStyle.blurSigma,
);

// One filter object per look, never rebuilt per frame: grouped reads compare
// filters to share one blur.
final ImageFilter _bitChordFrost = ImageFilter.compose(
  outer: _vibrancy,
  inner: ImageFilter.blur(
    sigmaX: kAppBitChordBlurSigma,
    sigmaY: kAppBitChordBlurSigma,
  ),
);

/// The FROSTED backdrop filter for [look]: the same single read either way;
/// BitChord's adds the saturation lift to the blurred pixels.
ImageFilter appFrostFilter(AppGlassLook look) => switch (look) {
  AppGlassLook.sistrum => _sistrumFrost,
  AppGlassLook.bitchord => _bitChordFrost,
};

/// The rim's thin contact edge for [look]: Sistrum's dark hairline, or
/// BitChord's white one at 10% (`GLASS_EDGE_COLOR`).
Color appGlassContactEdge(AppGlassLook look, {required bool dark}) =>
    switch (look) {
      AppGlassLook.sistrum => Color.fromRGBO(0, 0, 0, dark ? 0.5 : 0.16),
      AppGlassLook.bitchord => const Color.fromRGBO(255, 255, 255, 0.10),
    };
