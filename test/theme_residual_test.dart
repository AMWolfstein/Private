import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Names of the removed alternative design and its helpers. The app has one
/// design, so none of these may come back in the app sources.
const _removed = <String>[
  'isMornye',
  'LegacyMaterialTheme',
  'AppThemeStyle',
  'materialExpressiveEnabled',
  'DynamicColorWrapper',
  'dynamic_color_wrapper',
  'legacy_material_theme',
  'material_symbols.dart',
  'materialSymbolFor',
  'MornyeTheme',
  'mornye_theme.dart',
  'DynamicColors',
  'initialDynamicColorsProvider',
  'setUseAmoled',
  'setUseDynamicColor',
  'setSeedColor',
  'setStyle(',
];

void main() {
  test('the app sources no longer name the removed alternative design', () {
    final hits = <String>[];
    for (final entity in Directory('lib').listSync(recursive: true)) {
      if (entity is! File || !entity.path.endsWith('.dart')) continue;
      final text = entity.readAsStringSync();
      for (final name in _removed) {
        if (RegExp('\\b${RegExp.escape(name)}').hasMatch(text)) {
          hits.add('${entity.path}: $name');
        }
      }
    }
    expect(hits, isEmpty);
  });

  test('no source names the design after the product', () {
    // Product, brand and wire names that legitimately contain the product name.
    const allowed = {
      'MornyeApp',
      'mornyeLockupAsset',
      'mornyeBannerSeed',
      'mornyeBannerSeeds',
      'mornyeBannerTitleSize',
      'mornyeRaw',
    };
    final identifier = RegExp(r'\b_?k?[Mm]ornye[A-Z][A-Za-z0-9]*');
    final hits = <String>{};
    for (final root in ['lib', 'test', 'integration_test']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('theme_residual_test.dart')) continue;
        for (final m in identifier.allMatches(entity.readAsStringSync())) {
          final name = m.group(0)!;
          if (!allowed.contains(name)) hits.add('${entity.path}: $name');
        }
      }
    }
    expect(hits, isEmpty);
  });

  test('no helper or loop still switches between two designs', () {
    // A bare `mornye` identifier was the old design flag. Strings, imports,
    // scheme names and package paths are excluded by requiring a code use.
    final flag = RegExp(
      r'(\bbool mornye\b|\bmornye:\s|\bfinal mornye\b|\bmornye \?|\(mornye\b|!mornye\b)',
    );
    final hits = <String>{};
    for (final root in ['lib', 'test', 'integration_test']) {
      for (final entity in Directory(root).listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('theme_residual_test.dart')) continue;
        final text = entity.readAsStringSync();
        if (flag.hasMatch(text)) hits.add(entity.path);
      }
    }
    expect(hits, isEmpty);
  });
}
