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
}
