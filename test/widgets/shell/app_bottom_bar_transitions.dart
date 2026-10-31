part of 'app_bottom_bar_test.dart';

void _registerAppBottomBarTransitions() {
  for (final blur in [false, true]) {
    testWidgets('active edge icons and tabs stay synchronized (glass: $blur)', (
      tester,
    ) async {
      final activeTab = ValueNotifier(0);
      addTearDown(activeTab.dispose);
      await _pumpShell(
        tester,
        blur: blur,
        activeTab: activeTab,
        brightness: Brightness.dark,
      );
      final scheme = AppTheme.build(Brightness.dark).colorScheme;
      final primary = scheme.primary;
      Color? iconColor(String key, IconData data) {
        final icon = find.descendant(
          of: find.byKey(ValueKey(key)),
          matching: find.byIcon(data),
        );
        return IconTheme.of(tester.element(icon)).color;
      }

      for (final (index, label) in [
        (1, 'Library'),
        (2, 'Repo'),
        (3, 'Search'),
        (0, 'Home'),
      ]) {
        await tester.tapAt(
          tester.getCenter(
            find
                .descendant(
                  of: find.byType(AppTabBar),
                  matching: find.text(label),
                )
                .first,
          ),
        );
        await tester.pumpAndSettle();
        expect(activeTab.value, index);
        final tabIcons = find.descendant(
          of: find.byType(AppTabBar),
          matching: find.byIcon(Icons.home),
        );
        // Edge icons stay in the glass bar's selected/unselected layers at
        // rest, so the pill can reveal their red state during a held drag.
        for (final icon in tabIcons.evaluate()) {
          for (final opacity in tester.widgetList<Opacity>(
            find.ancestor(
              of: find.byElementPredicate((e) => e == icon),
              matching: find.byType(Opacity),
            ),
          )) {
            expect(opacity.opacity, 1);
          }
        }
        expect(
          iconColor('sistrum-compact-leading', switch (index) {
            1 => Icons.music_note,
            2 => Icons.grid_view,
            _ => Icons.home,
          }),
          index == 3 ? scheme.onSurface : primary,
        );
        expect(
          iconColor('sistrum-compact-search', Icons.search),
          index == 3 ? primary : scheme.onSurface,
        );
        final movingIcon = switch (index) {
          1 => Icons.music_note,
          2 => Icons.grid_view,
          _ => Icons.home,
        };
        final leading = find.byKey(const ValueKey('sistrum-compact-leading'));
        final origin = tester.getCenter(
          find.descendant(of: leading, matching: find.byIcon(movingIcon)),
        );
        final originalTabIcon = find
            .descendant(
              of: find.byType(AppTabBar),
              matching: find.byIcon(movingIcon),
            )
            .first;
        expect(
          (origin - tester.getCenter(originalTabIcon)).distance,
          lessThan(0.5),
        );
        chrome.value = true;
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          tester.widget<AppTabBar>(find.byType(AppTabBar)).hiddenIconIndices,
          {index == 3 ? 0 : index, 3},
        );
        await tester.pumpAndSettle();
        expect(
          iconColor('sistrum-compact-leading', movingIcon),
          index == 3 ? scheme.onSurface : primary,
        );
        expect(
          iconColor('sistrum-compact-search', Icons.search),
          index == 3 ? primary : scheme.onSurface,
        );
        expect(
          tester.widget<IconButton>(leading).tooltip,
          index == 3 ? 'Home' : label,
        );
        await tester.tap(leading);
        await tester.pumpAndSettle();
        expect(activeTab.value, index == 3 ? 0 : index);
        expect(chrome.value, isFalse);
        activeTab.value = index;
        chrome.expand();
        await tester.pumpAndSettle();
        expect(
          tester.widget<AppTabBar>(find.byType(AppTabBar)).selectedIndex,
          index,
        );
      }
    });

    testWidgets(
      'edge icons travel continuously without fading (glass: $blur)',
      (tester) async {
        await _pumpShell(tester, blur: blur);
        final homeButton = find.byKey(
          const ValueKey('sistrum-compact-leading'),
        );
        final icon = find.descendant(
          of: homeButton,
          matching: find.byIcon(Icons.home),
        );
        final element = tester.element(icon);
        final tabIcon = find
            .descendant(
              of: find.byType(AppTabBar),
              matching: find.byIcon(Icons.home),
            )
            .first;
        final start = tester.getCenter(icon);
        expect((start - tester.getCenter(tabIcon)).distance, lessThan(0.5));
        chrome.value = true;
        await tester.pump();
        var previous = start;
        for (var frame = 0; frame < 12; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(tester.element(icon), same(element));
          for (final opacity in tester.widgetList<Opacity>(
            find.ancestor(of: icon, matching: find.byType(Opacity)),
          )) {
            expect(opacity.opacity, 1);
          }
          final center = tester.getCenter(icon);
          expect((center - previous).distance, lessThan(8));
          previous = center;
        }
        expect(previous.dx, lessThan(start.dx));
        chrome.expand();
        await tester.pumpAndSettle();
        expect(tester.element(icon), same(element));
        expect((tester.getCenter(icon) - start).distance, lessThan(0.5));
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'Search joins full tabs and separates when compact (glass: $blur)',
      (tester) async {
        await _pumpShell(tester, blur: blur);
        final tabs = find.byType(AppTabBar);
        final search = find.byKey(const ValueKey('sistrum-compact-search'));
        final repo = find
            .descendant(of: tabs, matching: find.text('Repo'))
            .first;
        expect(tester.widget<AppTabBar>(tabs).destinations, hasLength(4));
        final searchLabel = find
            .descendant(of: tabs, matching: find.text('Search'))
            .first;
        expect(
          find.descendant(of: tabs, matching: find.text('Search')),
          findsWidgets,
        );
        expect(
          find.descendant(of: tabs, matching: find.text('Settings')),
          findsNothing,
        );
        expect(
          tester.getCenter(search).dx,
          greaterThan(tester.getCenter(repo).dx),
        );
        expect(
          tester.getSize(tabs).width,
          tester.getSize(find.byType(AppBottomBar)).width,
        );
        final searchIcon = find
            .descendant(of: tabs, matching: find.byIcon(Icons.search))
            .first;
        expect(
          (tester.getCenter(search) - tester.getCenter(searchIcon)).distance,
          lessThan(0.5),
        );
        // The glass renderer paints the labels under a gesture overlay.
        await tester.tapAt(tester.getCenter(searchLabel));
        await tester.pumpAndSettle();
        expect(searches, 1);
        chrome.value = true;
        await tester.pumpAndSettle();
        expect(tester.getSize(search), const Size(52, 52));
        await tester.tap(search);
        expect(searches, 2);
        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final withPlayer in [false, true]) {
    testWidgets('compact transition has no height jump (player: $withPlayer)', (
      tester,
    ) async {
      await _pumpShell(tester, withPlayer: withPlayer);
      final bar = find.byType(AppBottomBar);
      var previousHeight = tester.getSize(bar).height;
      final playerState = withPlayer
          ? tester.state(find.byType(MiniPlayer))
          : null;
      chrome.value = true;
      await tester.pump();
      Offset? firstHomeCenter;
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final height = tester.getSize(bar).height;
        expect(height, lessThanOrEqualTo(previousHeight + 0.01));
        previousHeight = height;
        firstHomeCenter ??= tester.getCenter(
          find.byKey(const ValueKey('sistrum-compact-leading')),
        );
      }
      final homeCenter = tester.getCenter(
        find.byKey(const ValueKey('sistrum-compact-leading')),
      );
      expect((homeCenter.dy - firstHomeCenter!.dy).abs(), lessThan(20));
      expect(find.byTooltip('Home').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Search').hitTestable(), findsOneWidget);
      if (withPlayer) {
        expect(tester.state(find.byType(MiniPlayer)), same(playerState));
      }
      chrome.expand();
      await tester.pump();
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
        final height = tester.getSize(bar).height;
        expect(height, greaterThanOrEqualTo(previousHeight - 0.01));
        previousHeight = height;
      }
      expect(tester.takeException(), isNull);
    });
  }

  for (final brightness in Brightness.values) {
    for (final level in [1, 4, 5]) {
      for (final backdrop in [
        Colors.white,
        Colors.black,
        if (brightness == Brightness.dark) albumBlue,
      ]) {
        testWidgets(
          'floating glass stays legible in $brightness over $backdrop (level: $level)',
          (tester) async {
            await _pumpShell(
              tester,
              blur: true,
              brightness: brightness,
              glassLevel: level,
              backdrop: backdrop,
              chromeSurface: backdrop == albumBlue ? albumBlue : null,
            );
            final artist = find.text('Artist');
            final libraryIcon = find
                .descendant(
                  of: find.byType(AppTabBar),
                  matching: find.byIcon(Icons.music_note),
                )
                .first;
            final artistRect = tester.getRect(artist);
            final iconRect = tester.getRect(libraryIcon);
            final foregrounds = [
              tester.widget<Text>(artist).style!.color!,
              IconTheme.of(tester.element(libraryIcon)).color!,
            ];
            final samples = [
              Offset(artistRect.left + 8, artistRect.bottom + 2),
              Offset(iconRect.right + 8, iconRect.center.dy),
            ];
            final backgrounds = await tester.runAsync(() async {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(capture),
              );
              final image = await boundary.toImage();
              final bytes = (await image.toByteData(
                format: ui.ImageByteFormat.rawRgba,
              ))!;
              final colors = <Color>[];
              for (final point in samples) {
                final offset =
                    (point.dy.floor() * image.width + point.dx.floor()) * 4;
                colors.add(
                  Color.fromARGB(
                    bytes.getUint8(offset + 3),
                    bytes.getUint8(offset),
                    bytes.getUint8(offset + 1),
                    bytes.getUint8(offset + 2),
                  ),
                );
              }
              image.dispose();
              return colors;
            });
            for (var index = 0; index < foregrounds.length; index++) {
              if (backdrop == albumBlue) {
                final glass = HSLColor.fromColor(backgrounds![index]);
                final page = HSLColor.fromColor(albumBlue);
                expect(glass.hue, closeTo(page.hue, 8));
                expect(glass.saturation, greaterThan(page.saturation * 0.7));
              }
              final luminances = [
                foregrounds[index].computeLuminance(),
                backgrounds![index].computeLuminance(),
              ]..sort();
              final contrast =
                  (luminances.last + 0.05) / (luminances.first + 0.05);
              expect(
                contrast,
                greaterThanOrEqualTo(index == 0 ? 4.5 : 3),
                reason: index == 0 ? 'Mini-player artist' : 'Inactive tab icon',
              );
            }
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  }

  testWidgets('downward scroll folds the tabs without replacing the player', (
    tester,
  ) async {
    await _pumpShell(tester);
    final playerState = tester.state(find.byType(MiniPlayer));
    final expandedHeight = tester.getSize(find.byType(AppBottomBar)).height;
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    expect(tester.state(find.byType(MiniPlayer)), same(playerState));
    expect(tester.widget<MiniPlayer>(find.byType(MiniPlayer)).compact, isTrue);
    expect(
      tester.getSize(find.byType(AppBottomBar)).height,
      lessThan(expandedHeight - 60),
    );
    expect(find.byTooltip('Next track'), findsNothing);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);
    expect(tester.getSize(find.byType(AppBottomBar)).height, expandedHeight);
    expect(tester.takeException(), isNull);
  });
}
