import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_color_utilities/contrast/contrast.dart';
import 'package:material_color_utilities/hct/cam16.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:material_color_utilities/score/score.dart';
import 'package:material_color_utilities/utils/color_utils.dart';

/// What one cover sample contains, independent of how a screen uses it.
/// Colours are ARGB; chroma values are HCT chroma.
@immutable
class CoverAnalysis {
  const CoverAnalysis({
    required this.dominant,
    required this.bottomEdge,
    required this.bottomHue,
    required this.topEdge,
    required this.seed,
    required this.seedShare,
    required this.sourceChroma,
    required this.bottomChroma,
    required this.topLightness,
  });

  /// Bump when the analysis changes, so stored results are recomputed.
  static const version = 1;

  /// Area-weighted colour of the whole image.
  final int dominant;

  /// Area-weighted colour of the bottom [bottomFraction], where the player
  /// and artist backgrounds continue the artwork.
  final int bottomEdge;

  /// The hue a tint of the bottom band takes: [bottomEdge]'s, or when that
  /// is nearly gray (its hue is noise), the hue of the band's coloured
  /// pixels, such as a gold stroke on a gray sweater.
  final double bottomHue;

  /// Area-weighted colour of the top [topFraction], under transparent headers.
  final int topEdge;

  /// Material's Score seed over the quantized colours.
  final int seed;

  /// Share of the image near [seed]'s hue (0..1).
  final double seedShare;

  /// Highest chroma that covers a meaningful area of the whole image.
  final double sourceChroma;

  /// The same for the bottom band.
  final double bottomChroma;

  /// Mean CIE L* (0..1) of the top band.
  final double topLightness;

  static const bottomFraction = 0.2;
  static const topFraction = 0.25;

  /// The smallest area a chroma counts for: a thin stroke or a small logo
  /// may not lift a background.
  static const meaningfulArea = 0.10;

  Map<String, Object> toJson() => {
    'v': version,
    'dominant': dominant,
    'bottomEdge': bottomEdge,
    'bottomHue': bottomHue,
    'topEdge': topEdge,
    'seed': seed,
    'seedShare': seedShare,
    'sourceChroma': sourceChroma,
    'bottomChroma': bottomChroma,
    'topLightness': topLightness,
  };

  static CoverAnalysis? fromJson(Object? json) {
    if (json is! Map || json['v'] != version) return null;
    int? color(String key) => (json[key] as num?)?.toInt();
    double? number(String key) => (json[key] as num?)?.toDouble();
    final dominant = color('dominant');
    final bottomEdge = color('bottomEdge');
    final bottomHue = number('bottomHue');
    final topEdge = color('topEdge');
    final seed = color('seed');
    final seedShare = number('seedShare');
    final sourceChroma = number('sourceChroma');
    final bottomChroma = number('bottomChroma');
    final topLightness = number('topLightness');
    if (dominant == null ||
        bottomEdge == null ||
        bottomHue == null ||
        topEdge == null ||
        seed == null ||
        seedShare == null ||
        sourceChroma == null ||
        bottomChroma == null ||
        topLightness == null) {
      return null;
    }
    return CoverAnalysis(
      dominant: dominant,
      bottomEdge: bottomEdge,
      bottomHue: bottomHue,
      topEdge: topEdge,
      seed: seed,
      seedShare: seedShare,
      sourceChroma: sourceChroma,
      bottomChroma: bottomChroma,
      topLightness: topLightness,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CoverAnalysis &&
      other.dominant == dominant &&
      other.bottomEdge == bottomEdge &&
      other.bottomHue == bottomHue &&
      other.topEdge == topEdge &&
      other.seed == seed &&
      other.seedShare == seedShare &&
      other.sourceChroma == sourceChroma &&
      other.bottomChroma == bottomChroma &&
      other.topLightness == topLightness;

  @override
  int get hashCode => Object.hash(
    dominant,
    bottomEdge,
    bottomHue,
    topEdge,
    seed,
    seedShare,
    sourceChroma,
    bottomChroma,
    topLightness,
  );
}

/// Score's seed over quantized colour counts. Quantizer output is ABGR (the
/// native worker and Flutter's readback share that order); Score wants ARGB.
int paletteSeedFromColorCounts(List<List<int>> colors) {
  final populations = <int, int>{};
  for (final pair in colors) {
    final abgr = pair[0];
    final argb =
        (abgr & 0xff00ff00) | ((abgr & 255) << 16) | ((abgr >> 16) & 255);
    populations[argb] = pair[1];
  }
  return Score.score(populations, desired: 1).first;
}

/// One analysis of a cover sample: [rgba] is premultiplied RGBA of
/// [width] x [height] pixels and [colors] its quantized colour counts.
CoverAnalysis analyzeCover(
  Uint8List rgba,
  int width,
  int height,
  List<List<int>> colors,
) {
  final seed = paletteSeedFromColorCounts(colors);
  final seedHue = Hct.fromInt(seed).hue;
  final bottomStart = (height * (1 - CoverAnalysis.bottomFraction)).floor();
  final topEnd = (height * CoverAnalysis.topFraction).ceil().clamp(1, height);
  final whole = _Region();
  final bottom = _Region();
  final top = _Region();
  // CAM16 is costly; covers repeat colours, so memoize per 5-bit channel.
  final pixelOf = <int, _Pixel>{};
  var lightness = 0.0;
  var lightnessWeight = 0.0;
  var nearSeed = 0.0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final index = (y * width + x) * 4;
      if (index + 3 >= rgba.length) break;
      final alpha = rgba[index + 3];
      if (alpha == 0) continue;
      final a = alpha / 255;
      // Premultiplied channels back to straight sRGB.
      final r = (rgba[index] / a).round().clamp(0, 255);
      final g = (rgba[index + 1] / a).round().clamp(0, 255);
      final b = (rgba[index + 2] / a).round().clamp(0, 255);
      final key = (r >> 3) << 10 | (g >> 3) << 5 | b >> 3;
      final pixel = pixelOf.putIfAbsent(
        key,
        () => _Pixel(ColorUtils.argbFromRgb(r, g, b)),
      );
      whole.add(pixel, a);
      if (y >= bottomStart) bottom.add(pixel, a);
      if (y < topEnd) {
        top.add(pixel, a);
        // Exact L*, not the memoized bucket's: headers switch on it.
        lightness +=
            ColorUtils.lstarFromArgb(ColorUtils.argbFromRgb(r, g, b)) / 100 * a;
        lightnessWeight += a;
      }
      if (pixel.chroma >= 8 && _hueDistance(pixel.hue, seedHue) <= 20) {
        nearSeed += a;
      }
    }
  }
  return CoverAnalysis(
    dominant: whole.color,
    bottomEdge: bottom.color,
    bottomHue: bottom.tintHue,
    topEdge: top.color,
    seed: seed,
    seedShare: whole.weight == 0 ? 0 : nearSeed / whole.weight,
    sourceChroma: whole.chromaCeiling,
    bottomChroma: bottom.chromaCeiling,
    topLightness: lightnessWeight == 0
        ? 0
        : (lightness / lightnessWeight).clamp(0.0, 1.0),
  );
}

class _Pixel {
  _Pixel(int argb) {
    final cam = Cam16.fromInt(argb);
    final hct = Hct.fromInt(argb);
    // Near black, a hue is not visible: such pixels count as neutral.
    final visible = hct.tone >= 12;
    hue = hct.hue;
    chroma = visible ? hct.chroma : 0;
    jstar = cam.jstar;
    astar = visible ? cam.astar : 0;
    bstar = visible ? cam.bstar : 0;
  }

  late final double hue, chroma, jstar, astar, bstar;
}

class _Region {
  // Perceptual (CAM16-UCS) sums, so a thin vivid stroke counts as much as
  // it shows and a mix with black, white or gray keeps its hue.
  double jstar = 0, astar = 0, bstar = 0, weight = 0;
  double tintA = 0, tintB = 0;
  final chroma = <double, double>{};

  void add(_Pixel pixel, double alpha) {
    jstar += pixel.jstar * alpha;
    astar += pixel.astar * alpha;
    bstar += pixel.bstar * alpha;
    weight += alpha;
    if (pixel.chroma >= CoverColors.neutralChroma) {
      tintA += pixel.astar * alpha;
      tintB += pixel.bstar * alpha;
    }
    final bucket = pixel.chroma.floorToDouble();
    chroma[bucket] = (chroma[bucket] ?? 0) + alpha;
  }

  int get color => weight == 0
      ? 0xff808080
      : Cam16.fromUcs(jstar / weight, astar / weight, bstar / weight).toInt();

  /// See [CoverAnalysis.bottomHue].
  double get tintHue {
    final average = Hct.fromInt(color);
    if (average.chroma >= 3 || (tintA == 0 && tintB == 0)) return average.hue;
    // In CAM16-UCS the angle of (a*, b*) is the CAM16 (and HCT) hue.
    return (math.atan2(tintB, tintA) * 180 / math.pi) % 360;
  }

  /// The highest chroma reached by at least [CoverAnalysis.meaningfulArea]
  /// of this region.
  double get chromaCeiling {
    if (weight == 0) return 0;
    final buckets = chroma.keys.toList()..sort((a, b) => b.compareTo(a));
    var covered = 0.0;
    for (final bucket in buckets) {
      covered += chroma[bucket]!;
      if (covered >= weight * CoverAnalysis.meaningfulArea) return bucket;
    }
    return 0;
  }
}

double _hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// Every colour Mornye derives from one cover. Build it only through
/// [mornyeCoverColors]: screens differ by tone, never by hue or chroma.
@immutable
class CoverColors {
  const CoverColors._({
    required this.hue,
    required this.chroma,
    required this.bottomTone,
    required this.accentHue,
    required this.accentChroma,
    required this.dominantColor,
    required this.topLightness,
    required this.seed,
  });

  /// Base hue and chroma, from the cover's bottom edge.
  final double hue;
  final double chroma;

  /// Tone of the bottom edge itself.
  final double bottomTone;
  final double accentHue;

  /// Zero when the cover has no usable accent.
  final double accentChroma;

  /// Whole-image colour, e.g. for a lyrics card without a gradient.
  final Color dominantColor;

  /// Mean L* (0..1) of the top band, or null without a cover.
  final double? topLightness;

  /// The harmonized seed for generated [ColorScheme]s.
  final Color seed;

  /// Above this chroma a background stops reading as a continuation and
  /// starts competing with the artwork.
  static const maxBackgroundChroma = 36.0;

  /// The least chroma a tinted cover keeps, never above what it contains.
  static const chromaFloor = 6.0;

  /// Below this ceiling a cover is treated as neutral.
  static const neutralChroma = 6.0;

  bool get neutral => chroma == 0;

  /// The base colour at [tone] (L*, 0..100).
  Color tone(double tone) => Color(Hct.from(hue, chroma, tone).toInt());

  /// Detail pages (album and artist) under and below the header artwork.
  double get surfaceTone => (16 + bottomTone * 0.2).clamp(18.0, 34.0);
  Color get surface => tone(surfaceTone);

  /// Player gradient over the full-bleed artwork, top to bottom.
  List<double> get playerTones {
    final first = bottomTone.clamp(30.0, 64.0);
    final second = (first - 8).clamp(26.0, 56.0);
    return [first, second, math.min(30.0, second)];
  }

  List<Color> get playerStops => [for (final t in playerTones) tone(t)];

  /// Player gradient behind lyrics and the queue.
  List<double> get playerPlainTones {
    final first = (22 + bottomTone * 0.2).clamp(24.0, 40.0);
    return [first, (first - 12).clamp(12.0, 28.0)];
  }

  List<Color> get playerPlainStops => [
    for (final t in playerPlainTones) tone(t),
  ];

  /// Player menus and sheets.
  static const menuTone = 28.0;
  Color get menuSurface => tone(menuTone);

  /// Text on a surface of [backgroundTone]: AA for body text.
  Color onTone(double backgroundTone) => Color(
    Hct.from(hue, math.min(chroma, 4), _lighter(backgroundTone, 7, 96)).toInt(),
  );

  /// Secondary text on [backgroundTone], still AA for body text.
  Color onToneVariant(double backgroundTone) => Color(
    Hct.from(
      hue,
      math.min(chroma, 8),
      math.max(_lighter(backgroundTone, 4.6, 100), 72),
    ).toInt(),
  );

  bool get hasAccent => accentChroma >= 8;

  static const accentTone = 80.0;

  /// The accent on dark surfaces; white when the cover has none.
  Color get accent => hasAccent
      ? Color(Hct.from(accentHue, accentChroma, accentTone).toInt())
      : Colors.white;

  /// Text and icons on [accent]: AA for body text.
  Color get onAccent => hasAccent
      ? Color(
          Hct.from(
            accentHue,
            math.min(accentChroma, 16),
            _darker(accentTone, 4.6, 20),
          ).toInt(),
        )
      : Colors.black;

  /// A generated scheme that keeps the cover's chroma (fidelity).
  ColorScheme scheme(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    dynamicSchemeVariant: DynamicSchemeVariant.fidelity,
  );

  static double _lighter(double tone, double ratio, double fallback) {
    final value = Contrast.lighter(tone: tone, ratio: ratio);
    return value < 0 ? fallback : math.max(value, fallback);
  }

  static double _darker(double tone, double ratio, double fallback) {
    final value = Contrast.darker(tone: tone, ratio: ratio);
    return value < 0 ? fallback : math.min(value, fallback);
  }
}

/// Neutral gray: no cover, or one that could not be read.
const _neutralAnalysis = CoverAnalysis(
  dominant: 0xff808080,
  bottomEdge: 0xff808080,
  bottomHue: 0,
  topEdge: 0xff808080,
  seed: 0xff808080,
  seedShare: 0,
  sourceChroma: 0,
  bottomChroma: 0,
  topLightness: 0.5,
);

/// The one place cover colours are derived. Every screen and the artwork
/// glass grounds use it, so one cover looks the same everywhere.
CoverColors mornyeCoverColors(CoverAnalysis? analysis) {
  final source = analysis ?? _neutralAnalysis;
  final bottom = Hct.fromInt(source.bottomEdge);
  final dominant = Hct.fromInt(source.dominant);
  // The background never gains chroma the bottom of the cover lacks.
  final ceiling = source.bottomChroma;
  final double chroma = ceiling < CoverColors.neutralChroma
      ? 0.0
      : math
            .max(bottom.chroma, math.min(CoverColors.chromaFloor, ceiling))
            .clamp(0.0, math.min(ceiling, CoverColors.maxBackgroundChroma))
            .toDouble();
  final seed = Hct.fromInt(source.seed);
  final references = [
    if (chroma > 0) source.bottomHue,
    if (dominant.chroma >= CoverColors.chromaFloor) dominant.hue,
  ];
  final far =
      references.isNotEmpty &&
      references.every((hue) => _hueDistance(hue, seed.hue) > 60);
  // A small vivid region far from the background's hue is not the cover's
  // accent; a muted version of the background hue is.
  final fallback = far && source.seedShare < CoverAnalysis.meaningfulArea;
  final accentHue = fallback ? references.first : seed.hue;
  final double accentChroma = analysis == null || source.sourceChroma < 8
      ? 0.0
      : fallback
      ? math.min(16.0, math.max(ceiling, CoverColors.chromaFloor))
      : math.min(seed.chroma, source.sourceChroma);
  return CoverColors._(
    hue: chroma == 0 ? 0 : source.bottomHue,
    chroma: chroma,
    bottomTone: bottom.tone,
    accentHue: accentHue,
    accentChroma: accentChroma,
    dominantColor: Color(source.dominant),
    topLightness: analysis?.topLightness,
    seed: accentChroma == 0
        ? const Color(0xff808080)
        : Color(Hct.from(accentHue, accentChroma, seed.tone).toInt()),
  );
}
