import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart' show GlassHost, GlassSurface;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';

Future<void> _pump(
  WidgetTester tester, {
  required bool liquid,
  AppGlassLevel level = AppGlassLevel.tinted,
  bool host = true,
}) async {
  Widget surface = AppGlass(
    blurEnabled: true,
    liquid: liquid,
    child: const SizedBox(key: ValueKey('glass-child'), width: 120, height: 80),
  );
  if (host) surface = GlassHost(child: surface);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appGlassLevelProvider.overrideWithValue(level)],
      child: MaterialApp(
        theme: AppTheme.build(Brightness.dark),
        home: Scaffold(body: Center(child: surface)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('FROSTED is the default: a clipped blur, no refraction', (
    tester,
  ) async {
    await _pump(tester, liquid: false);

    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(GlassSurface), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('LIQUID refracts through GlassSurface and draws no blur', (
    tester,
  ) async {
    await _pump(tester, liquid: true);

    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const ValueKey('glass-child')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('TINT: a flat level samples nothing, in either mode', (
    tester,
  ) async {
    for (final liquid in [false, true]) {
      await _pump(tester, liquid: liquid, level: AppGlassLevel.flat);

      expect(find.byType(GlassSurface), findsNothing);
      expect(find.byType(BackdropFilter), findsNothing);
      expect(find.byKey(const ValueKey('glass-child')), findsOneWidget);
    }
  });

  testWidgets('LIQUID without a host falls back to its fill, without error', (
    tester,
  ) async {
    await _pump(tester, liquid: true, host: false);

    expect(find.byType(GlassSurface), findsOneWidget);
    expect(find.byKey(const ValueKey('glass-child')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('removing a LIQUID surface disposes its glass cleanly', (
    tester,
  ) async {
    await _pump(tester, liquid: true);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    expect(find.byType(GlassSurface), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
