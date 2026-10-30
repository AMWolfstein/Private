import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/platform/custom_font_service.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';
import 'package:sistrum/app.dart';

import '../performance/performance_probe.dart';

void main() {
  final binding = PerformanceTestBinding.ensureInitialized();
  for (final brightness in Brightness.values) {
    testWidgets('anchored squircle glass with imported font ($brightness)', (
      tester,
    ) async {
      final probe = PerformanceProbe(
        binding,
        tester,
        suite: 'menu_650_${brightness.name}',
      );
      final capture = GlobalKey();
      final button = GlobalKey();
      final temporary = await (await getTemporaryDirectory()).createTemp(
        'font-ui-test-',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final fonts = CustomFontService(directory: () async => temporary);
      final bytes = await rootBundle.load('assets/fonts/InterVariable.ttf');
      final id = await fonts.import(
        bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes),
      );
      final family = await fonts.restore(id);
      expect(family, isNotNull);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            appGlassLevelProvider.overrideWithValue(AppGlassLevel.liquid),
            appBlurEnabledProvider.overrideWithValue(true),
            appGlassClarityLevelProvider.overrideWithValue(5),
          ],
          child: MaterialApp(
            theme: AppTheme.build(brightness, fontFamily: family),
            builder: (_, child) => RepaintBoundary(
              key: capture,
              child: AppGlassPreparation(child: child!),
            ),
            home: Scaffold(
              body: Stack(
                fit: StackFit.expand,
                children: [
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xff524584),
                          Color(0xffaa6858),
                          Color(0xff355e65),
                        ],
                      ),
                    ),
                  ),
                  const Center(
                    child: Text(
                      'Your music\nYour library',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Positioned(
                    top: 120,
                    right: 24,
                    child: Builder(
                      builder: (context) => IconButton(
                        key: button,
                        icon: const Icon(Icons.more_horiz),
                        onPressed: () => showAppContextMenu<void>(
                          context: context,
                          anchor: appMenuAnchor(button.currentContext!),
                          builder: (menuContext) => AppContextMenu(
                            quickActions: [
                              AppMenuAction(
                                icon: Icons.favorite_border,
                                label: 'Favorite',
                                onPressed: () {},
                              ),
                              AppMenuAction(
                                icon: Icons.share_outlined,
                                label: 'Share',
                                onPressed: () {},
                              ),
                            ],
                            groups: [
                              [
                                AppMenuAction(
                                  icon: Icons.queue_music,
                                  label: 'Add to playlist',
                                  onPressed: () {},
                                ),
                                AppMenuAction(
                                  icon: Icons.album_outlined,
                                  label: 'Go to album',
                                  subtitle: 'Example album',
                                  onPressed: () {},
                                ),
                                AppMenuAction(
                                  icon: Icons.person_outline,
                                  label: 'Go to artist',
                                  onPressed: () {},
                                ),
                              ],
                              [
                                AppMenuAction(
                                  icon: Icons.close,
                                  label: 'Close',
                                  onPressed: () => Navigator.pop(menuContext),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await probe.wait(const Duration(milliseconds: 500));
      Future<void> open() async {
        await tester.tap(find.byKey(button));
        await probe.wait(const Duration(milliseconds: 450));
        expect(find.byType(AppContextMenu), findsOneWidget);
      }

      Future<void> close() async {
        await tester.tap(find.text('Close'));
        await probe.wait(const Duration(milliseconds: 450));
        expect(find.byType(AppContextMenu), findsNothing);
      }

      await probe.measure('open_close', () async {
        await open();
        await close();
      });
      await open();
      final menuContext = tester.element(find.byType(AppContextMenu));
      expect(Theme.of(menuContext).textTheme.bodyLarge?.fontFamily, family);
      await tester.runAsync(() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(capture),
        );
        final image = await boundary.toImage(
          pixelRatio: tester.view.devicePixelRatio,
        );
        try {
          final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
          final file = File(
            '${(await getTemporaryDirectory()).path}/menu-650-${brightness.name}.png',
          );
          await file.writeAsBytes(
            png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
          );
          debugPrint('MENU_PRESENTATION: ${file.path}');
        } finally {
          image.dispose();
        }
      });
      await close();
      await probe.finish();
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }
}
