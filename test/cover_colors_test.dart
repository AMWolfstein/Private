import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/hct/hct.dart';
import 'package:sistrum/services/library/covers/cover_analysis_store.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

double hueDistance(double a, double b) {
  final d = (a - b).abs() % 360;
  return d > 180 ? 360 - d : d;
}

/// Covers under test/fixtures/covers: the album from the bug report and
/// synthetic covers with the structures that went wrong.
const fixtures = [
  'qamar',
  'light_portrait',
  'dark_strip',
  'black_white',
  'saturated',
  'neutral_logo',
];

class _MemoryStore implements CoverAnalysisStore {
  final rows = <String, CoverAnalysis>{};
  int reads = 0;

  @override
  Future<CoverAnalysis?> read(String key) async {
    reads++;
    return rows[key];
  }

  @override
  Future<void> write(String key, CoverAnalysis analysis) async =>
      rows[key] = analysis;
}

void main() {
  final analyses = <String, CoverAnalysis>{};
  final palette = CoverPaletteCache();

  setUpAll(() async {
    final binding = TestWidgetsFlutterBinding.ensureInitialized();
    await binding.runAsync(() async {
      for (final name in fixtures) {
        final path = File('test/fixtures/covers/$name.png').absolute.path;
        analyses[name] = (await palette.resolveAnalysis(path))!;
      }
    });
  });

  test('every screen takes its colour from one base, by tone only', () {
    for (final name in fixtures) {
      final analysis = analyses[name]!;
      final colors = appCoverColors(analysis);
      final roles = {
        'surface (album and artist)': colors.surface,
        'player top': colors.playerStops[0],
        'player middle': colors.playerStops[1],
        'player bottom': colors.playerStops[2],
        'lyrics top': colors.playerPlainStops[0],
        'lyrics bottom': colors.playerPlainStops[1],
        'menu': colors.menuSurface,
      };
      for (final MapEntry(key: role, value: color) in roles.entries) {
        final hct = Hct.fromInt(color.toARGB32());
        final reason = '$name $role';
        // Never more colourful than the cover's bottom edge really is.
        expect(
          hct.chroma,
          lessThanOrEqualTo(analysis.bottomChroma + 0.5),
          reason: reason,
        );
        if (colors.chroma == 0) {
          // Pure gray (HCT reads gray as chroma ~2 under its viewing
          // conditions).
          expect(color.r, color.g, reason: reason);
          expect(color.g, color.b, reason: reason);
        } else if (hct.chroma >= 3) {
          // 8-bit output moves a low chroma's hue by a few degrees.
          expect(
            hueDistance(hct.hue, colors.hue),
            lessThan(math.max(4, 48 / hct.chroma)),
            reason: reason,
          );
        }
      }
    }
  });

  test('text, icons and accents meet WCAG AA on their backgrounds', () {
    for (final name in fixtures) {
      final colors = appCoverColors(analyses[name]);
      void aa(Color fg, Color bg, double ratio, String what) => expect(
        contrast(fg, bg),
        greaterThanOrEqualTo(ratio),
        reason: '$name $what',
      );
      final surface = colors.surface;
      aa(colors.onTone(colors.surfaceTone), surface, 4.5, 'body text');
      aa(colors.onToneVariant(colors.surfaceTone), surface, 4.5, 'secondary');
      aa(colors.accent, surface, 3, 'accent icons');
      aa(colors.onAccent, colors.accent, 4.5, 'text on accent');
      final player = colors.playerStops;
      aa(Colors.white, player[2], 4.5, 'player controls');
      aa(Colors.white, player[1], 3, 'player large text');
      for (final stop in colors.playerPlainStops) {
        aa(Colors.white, stop, 4.5, 'lyrics text');
      }
      aa(Colors.white, colors.menuSurface, 4.5, 'menu text');
    }
  });

  test('the accent stays in harmony with the background', () {
    for (final name in fixtures) {
      final analysis = analyses[name]!;
      final colors = appCoverColors(analysis);
      if (!colors.hasAccent) continue;
      final references = [
        if (colors.chroma != 0) colors.hue,
        if (Hct.fromInt(analysis.dominant).chroma >= CoverColors.chromaFloor)
          Hct.fromInt(analysis.dominant).hue,
      ];
      expect(
        Hct.fromInt(colors.accent.toARGB32()).chroma,
        lessThanOrEqualTo(analysis.sourceChroma + 0.5),
        reason: name,
      );
      if (references.isEmpty) continue;
      final near = references.any(
        (hue) => hueDistance(hue, colors.accentHue) <= 60,
      );
      expect(
        near || analysis.seedShare >= CoverAnalysis.meaningfulArea,
        isTrue,
        reason: name,
      );
    }
  });

  test('covers keep their character', () {
    CoverColors of(String name) => appCoverColors(analyses[name]);
    // The report's cover: a warm gray continuation, not deep rust.
    final qamar = of('qamar');
    expect(qamar.chroma, lessThan(16));
    expect(qamar.chroma, greaterThan(0));
    // A small vivid logo does not tint a neutral cover.
    expect(of('neutral_logo').chroma == 0, isTrue);
    expect(of('black_white').chroma == 0, isTrue);
    expect(of('black_white').hasAccent, isFalse);
    // A red cover stays red, below the background cap.
    final red = of('saturated');
    expect(hueDistance(red.hue, Hct.fromInt(0xffe8112d).hue), lessThan(4));
    expect(red.chroma, CoverColors.maxBackgroundChroma);
    // The pale strip on black shows in the accent; the black bottom edge
    // keeps the background neutral.
    final strip = of('dark_strip');
    expect(strip.chroma == 0, isTrue);
    expect(strip.hasAccent, isTrue);
    expect(
      hueDistance(strip.accentHue, Hct.fromInt(0xffd4ddac).hue),
      lessThan(10),
    );
  });

  test('no cover or an unreadable one stays neutral gray', () {
    final colors = appCoverColors(null);
    expect(colors.chroma == 0, isTrue);
    expect(colors.hasAccent, isFalse);
    expect(colors.accent, Colors.white);
    final surface = colors.surface;
    expect(surface.r, surface.g);
    expect(surface.g, surface.b);
  });

  test('analyses round-trip through their stored form', () {
    for (final analysis in analyses.values) {
      expect(CoverAnalysis.fromJson(analysis.toJson()), analysis);
    }
    expect(
      CoverAnalysis.fromJson({...analyses['qamar']!.toJson(), 'v': 0}),
      isNull,
    );
  });

  testWidgets('a stored analysis is used without decoding the cover', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final directory = await Directory.systemTemp.createTemp('cover-store-');
      final store = _MemoryStore();
      try {
        final file = File('${directory.path}/cover.png');
        await File('test/fixtures/covers/qamar.png').copy(file.path);
        final first = await CoverPaletteCache(
          store: store,
        ).resolveAnalysis(file.path);
        expect(store.rows.values.single, first);
        // A later session: a new cache has no memory, and the stored row
        // answers for the same file version.
        final reads = store.reads;
        expect(
          await CoverPaletteCache(store: store).resolveAnalysis(file.path),
          first,
        );
        expect(store.reads, reads + 1);
        expect(store.rows, hasLength(1));
      } finally {
        await directory.delete(recursive: true);
      }
    });
  });
}
