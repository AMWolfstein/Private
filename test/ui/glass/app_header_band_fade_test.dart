import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';

Future<void> _pumpBand(
  WidgetTester tester, {
  required bool shown,
}) => tester.pumpWidget(
  ProviderScope(
    overrides: [appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted)],
    child: MaterialApp(
      theme: AppTheme.build(Brightness.dark),
      home: Scaffold(
        body: SizedBox(height: 100, child: AppHeaderBacking(visible: shown)),
      ),
    ),
  ),
);

String _filter(WidgetTester tester) => tester
    .widget<BackdropFilter>(find.byType(BackdropFilter))
    .filter
    .toString();

void main() {
  test('a settled band reuses one plain blur per sigma', () {
    final settled = appHeaderBandFilter(6, 1);
    expect(appHeaderBandFilter(6, 1), same(settled));
    expect(settled.toString(), contains('6.0'));
    expect(settled.toString(), isNot(contains('compose')));
  });

  test('a fading band keeps its full sigma and fades by alpha', () {
    for (final amount in [0.05, 0.3, 0.6, 0.95]) {
      final fading = appHeaderBandFilter(6, amount).toString();
      // The blur inside is the settled sigma 6, never sigma x amount.
      expect(fading, contains('compose'), reason: '$amount');
      expect(fading, contains('6.0'), reason: '$amount');
    }
  });

  testWidgets('the 180 ms fade keeps the settled sigma on every frame', (
    tester,
  ) async {
    await _pumpBand(tester, shown: false);
    expect(find.byType(BackdropFilter), findsNothing);
    await _pumpBand(tester, shown: true);
    final fading = <String>[];
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      if (find.byType(BackdropFilter).evaluate().isNotEmpty) {
        fading.add(_filter(tester));
      }
    }
    await tester.pumpAndSettle();
    final settled = _filter(tester);
    // Settled: the plain blur, no alpha stage.
    expect(settled, startsWith('ImageFilter.blur('));
    final sigma = RegExp(r'blur\(([0-9.]+), ').firstMatch(settled)!.group(1);
    expect(fading, isNotEmpty);
    for (final filter in fading) {
      // Every fading frame blurs at the settled sigma; only alpha changes.
      expect(filter, contains('blur($sigma, $sigma'), reason: filter);
    }
    expect(fading.where((f) => f.contains('compose')), isNotEmpty);
    expect(tester.takeException(), isNull);
  });
}
