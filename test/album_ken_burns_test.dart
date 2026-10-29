import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/widgets/header/album_ken_burns.dart';

class _Settings extends SettingsNotifier {
  _Settings(this.initial);
  final AppSettings initial;

  @override
  AppSettings build() => initial;
}

Widget _host({
  required AppSettings settings,
  bool lowEnd = false,
  bool reduceMotion = false,
  ScrollController? controller,
  Widget? scrollBelow,
}) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(() => _Settings(settings)),
    lowEndDeviceProvider.overrideWithValue(lowEnd),
  ],
  child: MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Scaffold(
        body: CustomScrollView(
          controller: controller,
          slivers: [
            const SliverToBoxAdapter(
              child: SizedBox(
                height: 300,
                child: AlbumKenBurns(child: ColoredBox(color: Colors.red)),
              ),
            ),
            SliverToBoxAdapter(
              child: SizedBox(height: 2000, child: scrollBelow),
            ),
          ],
        ),
      ),
    ),
  ),
);

Matrix4? _transform(WidgetTester tester) {
  final finder = find.descendant(
    of: find.byType(AlbumKenBurns),
    matching: find.byType(Transform),
  );
  if (finder.evaluate().isEmpty) return null;
  return tester.widget<Transform>(finder.first).transform;
}

void main() {
  test('album animation defaults on and round trips', () {
    expect(AppSettings.fromJson({}).animatedAlbumArtwork, isTrue);
    final off = const AppSettings().copyWith(animatedAlbumArtwork: false);
    expect(AppSettings.fromJson(off.toJson()).animatedAlbumArtwork, isFalse);
  });

  test('the drift never exposes the cover edges', () {
    const size = Size(400, 400);
    for (var i = 0; i <= 2000; i++) {
      final m = kenBurnsMatrix(i / 2000 * 4 * 3.14159265, size);
      final scale = m.storage[0];
      final dx = m.storage[12].abs();
      final dy = m.storage[13].abs();
      // Scale about the centre: each side hides (scale - 1) / 2 of the size.
      expect(scale, inInclusiveRange(1.04, 1.10));
      expect(dx + 0, lessThan((scale - 1) / 2 * size.width));
      expect(dy, lessThan((scale - 1) / 2 * size.height));
    }
  });

  testWidgets('drifts while enabled', (tester) async {
    await tester.pumpWidget(_host(settings: const AppSettings()));
    await tester.pump(const Duration(seconds: 2));
    final first = _transform(tester);
    await tester.pump(const Duration(seconds: 5));
    final second = _transform(tester);
    expect(first, isNotNull);
    expect(second, isNot(equals(first)));
  });

  testWidgets('stands still with the setting off, no glass or reduced motion', (
    tester,
  ) async {
    for (final host in [
      _host(settings: const AppSettings(animatedAlbumArtwork: false)),
      _host(settings: const AppSettings(glassQuality: 'off')),
      _host(settings: const AppSettings(), lowEnd: true),
      _host(settings: const AppSettings(), reduceMotion: true),
    ]) {
      await tester.pumpWidget(host);
      await tester.pump(const Duration(seconds: 3));
      expect(_transform(tester), isNull);
      expect(tester.hasRunningAnimations, isFalse);
    }
  });

  testWidgets('stops once the page is scrolled past the cover', (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      _host(settings: const AppSettings(), controller: controller),
    );
    await tester.pump(const Duration(seconds: 1));
    expect(tester.hasRunningAnimations, isTrue);
    controller.jumpTo(600);
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, isFalse);
    controller.jumpTo(0);
    await tester.pump();
    await tester.pump();
    expect(tester.hasRunningAnimations, isTrue);
  });
}
