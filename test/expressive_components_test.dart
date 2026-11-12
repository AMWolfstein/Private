import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mornye/l10n/l10n.dart';
import 'package:mornye/theme/app_theme.dart';
import 'package:mornye/theme/material_expressive.dart';
import 'package:mornye/widgets/app_action_button.dart';
import 'package:mornye/widgets/app_choice_chip.dart';
import 'package:mornye/widgets/app_content_card.dart';
import 'package:mornye/widgets/app_switch.dart';
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

  testWidgets('Keeps Cupertino actions and its own surfaces', (tester) async {
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
