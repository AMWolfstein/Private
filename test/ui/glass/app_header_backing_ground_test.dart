import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_page_ground.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';

const _backingKey = ValueKey('sistrum-header-backing');

Future<void> _pump(
  WidgetTester tester, {
  required bool onPageGround,
  required bool groundVeil,
}) async {
  final band = AppHeaderBacking(visible: true, groundVeil: groundVeil);
  final body = Stack(
    children: [
      const AppGroundAnchor(
        layout: AppGroundLayout(),
        child: SizedBox(height: 300),
      ),
      Positioned(top: 0, left: 0, right: 0, height: 80, child: band),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appGlassLevelProvider.overrideWithValue(AppGlassLevel.tinted),
      ],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: Scaffold(
          body: onPageGround
              ? AppPageGround(
                  source: null,
                  surface: Colors.black,
                  sigma: 6,
                  enabled: true,
                  cover: null,
                  child: body,
                )
              : body,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

int _blursInBand(WidgetTester tester) => find
    .descendant(
      of: find.byKey(_backingKey),
      matching: find.byType(BackdropFilter),
    )
    .evaluate()
    .length;

void main() {
  testWidgets(
    'an artwork-page band draws no live blur: its ground is the blur',
    (tester) async {
      await _pump(tester, onPageGround: true, groundVeil: true);

      expect(find.byKey(_backingKey), findsOneWidget);
      expect(_blursInBand(tester), 0);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a band without an artwork ground keeps its live blur', (
    tester,
  ) async {
    await _pump(tester, onPageGround: false, groundVeil: true);

    expect(find.byKey(_backingKey), findsOneWidget);
    expect(_blursInBand(tester), 1);
  });

  testWidgets(
    'a band that does not opt in keeps its live blur on a page ground',
    (tester) async {
      await _pump(tester, onPageGround: true, groundVeil: false);

      expect(find.byKey(_backingKey), findsOneWidget);
      expect(_blursInBand(tester), 1);
    },
  );
}
