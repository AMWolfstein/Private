import 'dart:ui' as ui;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/theme/material_expressive.dart';
import 'package:mornye/widgets/app_action_button.dart';
import 'package:mornye/widgets/app_choice_chip.dart';
import 'package:mornye/widgets/app_content_card.dart';
import 'package:mornye/widgets/app_switch.dart';
import 'package:mornye/widgets/expressive_navigation_bar.dart';
import 'package:mornye/widgets/selection_action_button.dart';
import 'package:mornye/widgets/settings_group.dart';

import 'support/app_icon_finder.dart';

Widget _host(
  Widget child, {
  ThemeData? theme,
  bool reduceMotion = false,
  double textScale = 1,
  Locale locale = const Locale('en'),
}) => ProviderScope(
  child: MaterialApp(
    theme: theme ?? AppTheme.build(Brightness.light),
    locale: locale,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(context).copyWith(
        disableAnimations: reduceMotion,
        textScaler: TextScaler.linear(textScale),
      ),
      child: child!,
    ),
    home: Scaffold(body: Center(child: child)),
  ),
);

void main() {
  testWidgets('chips preserve select and deselect callbacks', (tester) async {
    var selected = false;
    await tester.pumpWidget(
      _host(
        StatefulBuilder(
          builder: (context, setState) => AppChoiceChip(
            label: const Text('Albums'),
            icon: const Icon(Icons.album_outlined),
            count: 12,
            selected: selected,
            singleChoice: true,
            onSelected: (next) => setState(() => selected = next),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('12'), findsOneWidget);
    expect(findAppIcon(Icons.album_outlined), findsOneWidget);
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(selected, isTrue);
    await tester.tap(find.text('Albums'));
    await tester.pumpAndSettle();
    expect(selected, isFalse);
  });

  testWidgets('large labels fit narrow settings and selection actions', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SettingsGroup(
              children: [
                AppSwitchListTile(
                  value: true,
                  onChanged: (_) {},
                  title: const Text('Continue playing music from your Library'),
                ),
              ],
            ),
            Row(
              children: [
                for (final label in [
                  'Remove ReplayGain (10)',
                  'Convert 10 tracks',
                ])
                  Expanded(
                    child: SelectionActionButton(
                      icon: Icons.music_note,
                      label: label,
                      onPressed: () {},
                      colorScheme: AppTheme.build(Brightness.light).colorScheme,
                    ),
                  ),
              ],
            ),
          ],
        ),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  for (final dark in [false, true]) {
    for (final reduceMotion in [false, true]) {
      testWidgets('navigation tint continues through system insets '
          '(dark: $dark, reduced motion: $reduceMotion)', (tester) async {
        final capture = GlobalKey();
        const backdrop = Color(0xff725ca8);
        final theme = dark
            ? AppTheme.build(Brightness.dark)
            : AppTheme.build(Brightness.light);
        final tint = theme.colorScheme.surfaceContainer.withValues(alpha: 0.72);
        for (final bottomInset in [24.0, 48.0]) {
          await tester.pumpWidget(
            _host(
              Builder(
                builder: (context) => MediaQuery(
                  data: MediaQuery.of(
                    context,
                  ).copyWith(padding: EdgeInsets.only(bottom: bottomInset)),
                  child: RepaintBoundary(
                    key: capture,
                    child: SizedBox(
                      width: 320,
                      child: ColoredBox(
                        color: backdrop,
                        child: ExpressiveNavigationBar(
                          selectedIndex: 0,
                          onDestinationSelected: (_) {},
                          backgroundColor: tint,
                          destinations: const [
                            NavigationDestination(
                              icon: Icon(Icons.home),
                              label: 'Home',
                            ),
                            NavigationDestination(
                              icon: Icon(Icons.settings),
                              label: 'Settings',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              theme: theme,
              reduceMotion: reduceMotion,
            ),
          );
          await tester.pumpAndSettle();
          final colors = await tester.runAsync(() async {
            final boundary = tester.renderObject<RenderRepaintBoundary>(
              find.byKey(capture),
            );
            final image = await boundary.toImage();
            try {
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              return [
                // Sample between destinations and at the physical bottom.
                for (final y in [32, image.height - 1])
                  Color.fromARGB(
                    bytes.getUint8((y * image.width + 160) * 4 + 3),
                    bytes.getUint8((y * image.width + 160) * 4),
                    bytes.getUint8((y * image.width + 160) * 4 + 1),
                    bytes.getUint8((y * image.width + 160) * 4 + 2),
                  ),
              ];
            } finally {
              image.dispose();
            }
          });
          expect(colors![0], colors[1]);
          final expected = Color.alphaBlend(tint, backdrop);
          expect(colors[0].r, closeTo(expected.r, 1 / 255));
          expect(colors[0].g, closeTo(expected.g, 1 / 255));
          expect(colors[0].b, closeTo(expected.b, 1 / 255));
          expect(
            tester.getSize(find.byType(ExpressiveNavigationBar)).height,
            64 + bottomInset,
          );
          expect(tester.takeException(), isNull);
        }
      });
    }
  }

  testWidgets('Mornye keeps Cupertino actions and its own surfaces', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppActionButton(
              onPressed: () {},
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play'),
            ),
            AppChoiceChip(
              label: const Text('Albums'),
              selected: true,
              onSelected: (_) {},
            ),
            const AppContentCard(child: Text('Details')),
            AppSwitch(value: true, onChanged: (_) {}),
          ],
        ),
        theme: AppTheme.build(Brightness.dark),
        reduceMotion: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(MaterialExpressiveScope), findsNothing);
    expect(find.byType(CupertinoButton), findsAtLeast(2));
    expect(tester.takeException(), isNull);
  });
}
