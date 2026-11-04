import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/screens/settings/settings_tab.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/collection/collection_scaffold.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/widgets/player/mini_player.dart';
import 'package:sistrum/widgets/primitives/app_selection_controls.dart';
import 'package:sistrum/widgets/shell/app_bottom_bar.dart';

late AppChromeController chrome;
late ScrollController scroll;
late int searches;

Future<void> _pumpShell(
  WidgetTester tester, {
  bool withPlayer = true,
  Brightness brightness = Brightness.light,
  Widget? body,
  ValueNotifier<int>? activeTab,
}) async {
  tester.view.physicalSize = const Size(393, 760);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentMediaItemProvider.overrideWithBuild(
          (ref, notifier) => Stream.value(
            withPlayer
                ? const MediaItem(
                    id: 'track',
                    title: 'A song',
                    artist: 'Artist',
                  )
                : null,
          ),
        ),
        playbackStateProvider.overrideWith((ref) => const Stream.empty()),
      ],
      child: MaterialApp(
        theme: AppTheme.build(brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          extendBody: true,
          body: NotificationListener<ScrollNotification>(
            onNotification: chrome.handleScroll,
            child:
                body ??
                ListView.builder(
                  controller: scroll,
                  itemExtent: 60,
                  itemCount: 50,
                  itemBuilder: (_, index) => Text('Row $index'),
                ),
          ),
          bottomNavigationBar: ListenableBuilder(
            listenable: Listenable.merge([chrome, ?activeTab]),
            builder: (_, _) => AppBottomBar(
              collapsed: chrome.value,
              destinations: const [
                NavigationDestination(icon: Icon(Icons.home), label: 'Home'),
                NavigationDestination(
                  icon: Icon(Icons.music_note),
                  label: 'Library',
                ),
                NavigationDestination(
                  icon: Icon(Icons.grid_view),
                  label: 'Repo',
                ),
                NavigationDestination(
                  icon: Icon(Icons.search),
                  label: 'Search',
                ),
              ],
              selectedIndex: activeTab?.value ?? 0,
              onSelected: (index) {
                activeTab?.value = index;
                chrome.expand();
              },
              onHome: () {
                activeTab?.value = 0;
                chrome.expand();
              },
              onSearch: () {
                searches++;
                activeTab?.value = 3;
              },
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    chrome = AppChromeController();
    scroll = ScrollController();
    searches = 0;
  });
  tearDown(() {
    chrome.dispose();
    scroll.dispose();
  });

  testWidgets('tapping a tab selects it and expands the bar', (tester) async {
    final activeTab = ValueNotifier(0);
    addTearDown(activeTab.dispose);
    await _pumpShell(tester, activeTab: activeTab);
    await tester.tap(find.text('Library'));
    await tester.pumpAndSettle();
    expect(activeTab.value, 1);
    expect(chrome.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the search destination calls onSearch', (tester) async {
    await _pumpShell(tester);
    await tester.tap(find.text('Search'));
    await tester.pumpAndSettle();
    expect(searches, 1);
  });

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
      lessThan(expandedHeight),
    );
    expect(find.byTooltip('Next track'), findsNothing);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);
    expect(tester.getSize(find.byType(AppBottomBar)).height, expandedHeight);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'collapse keeps the player and tab contents out of frame rebuilds',
    (tester) async {
      await _pumpShell(tester);
      var tabBuilds = 0;
      var playerBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is AppTabBar) tabBuilds++;
        if (element.widget is MiniPlayer) playerBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      chrome.value = true;
      await tester.pump();
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tabBuilds, lessThanOrEqualTo(2));
      expect(playerBuilds, lessThanOrEqualTo(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('folding chrome updates the spacer without rebuilding Settings', (
    tester,
  ) async {
    await _pumpShell(tester, body: const SettingsTab());
    var settingsBuilds = 0;
    var spacerBuilds = 0;
    final previous = debugOnRebuildDirtyWidget;
    debugOnRebuildDirtyWidget = (element, builtOnce) {
      previous?.call(element, builtOnce);
      if (element.widget is SettingsTab) settingsBuilds++;
      if (element.widget is NavBarSliverSpacer) spacerBuilds++;
    };
    addTearDown(() => debugOnRebuildDirtyWidget = previous);

    for (final collapsed in [true, false]) {
      chrome.value = collapsed;
      await tester.pump();
      for (var frame = 0; frame < 25; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
    }

    expect(settingsBuilds, 0);
    expect(spacerBuilds, greaterThan(20));
    expect(tester.takeException(), isNull);
  });

  for (final artist in [true, false]) {
    testWidgets('folding chrome isolates header insets (artist: $artist)', (
      tester,
    ) async {
      var pageBuilds = 0;
      await _pumpShell(
        tester,
        body: Builder(
          builder: (context) {
            pageBuilds++;
            final tracks = SliverFixedExtentList.builder(
              itemExtent: 60,
              itemCount: 50,
              itemBuilder: (_, index) => Text('Track $index'),
            );
            if (artist) {
              return CustomScrollView(
                controller: scroll,
                slivers: [
                  ...const AppArtistHeader(
                    name: 'Artist',
                    showTitle: false,
                    artwork: ColoredBox(color: Colors.blue),
                    actions: [],
                  ).buildSlivers(context),
                  tracks,
                  const NavBarSliverSpacer(),
                ],
              );
            }
            return CollectionScaffold(
              scrollController: scroll,
              isSelectionMode: false,
              onExitSelectionMode: () {},
              appBar: const AlbumDetailHeader(
                title: 'Album',
                expandedHeight: 400,
                immersive: true,
                showTitleInAppBar: false,
                background: ColoredBox(color: Colors.blue),
              ),
              slivers: [tracks],
            );
          },
        ),
      );
      pageBuilds = 0;
      var collectionBuilds = 0;
      final previous = debugOnRebuildDirtyWidget;
      debugOnRebuildDirtyWidget = (element, builtOnce) {
        previous?.call(element, builtOnce);
        if (element.widget is CollectionScaffold) collectionBuilds++;
      };
      addTearDown(() => debugOnRebuildDirtyWidget = previous);
      for (final collapsed in [true, false]) {
        chrome.value = collapsed;
        await tester.pump();
        for (var frame = 0; frame < 25; frame++) {
          await tester.pump(const Duration(milliseconds: 16));
        }
      }
      expect(pageBuilds, 0);
      expect(collectionBuilds, 0);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'compact tabs survive upward scrolling until the page returns to the top',
    (tester) async {
      await _pumpShell(tester);
      scroll.jumpTo(500);
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
      await tester.drag(find.byType(ListView), const Offset(-120, 0));
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pumpAndSettle();
      expect(chrome.value, isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, 90));
      await tester.pumpAndSettle();
      expect(chrome.value, isTrue);
      await tester.drag(find.byType(ListView), const Offset(0, 900));
      await tester.pumpAndSettle();
      expect(chrome.value, isFalse);
    },
  );

  testWidgets('Library keeps compact tabs until the outer header returns', (
    tester,
  ) async {
    await _pumpShell(
      tester,
      body: NestedScrollView(
        headerSliverBuilder: (_, _) => const [
          SliverAppBar(expandedHeight: 180, title: Text('Library')),
        ],
        body: PageView(
          children: [
            ListView.builder(
              itemExtent: 60,
              itemCount: 60,
              itemBuilder: (_, index) => Text('Track $index'),
            ),
          ],
        ),
      ),
    );
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, 100));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    await tester.drag(find.byType(ListView), const Offset(0, 900));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'the tab bar stays mounted and pauses its tickers while collapsed',
    (tester) async {
      await _pumpShell(tester);
      final tabs = tester.element(find.byType(AppTabBar));
      final player = tester.state(find.byType(MiniPlayer));
      expect(TickerMode.valuesOf(tabs).enabled, isTrue);
      chrome.value = true;
      await tester.pumpAndSettle();
      expect(
        tester.element(find.byType(AppTabBar, skipOffstage: false)),
        same(tabs),
      );
      expect(TickerMode.valuesOf(tabs).enabled, isFalse);
      chrome.expand();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(AppTabBar)), same(tabs));
      expect(tester.state(find.byType(MiniPlayer)), same(player));
      expect(TickerMode.valuesOf(tabs).enabled, isTrue);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('compact navigation works without a playing track', (
    tester,
  ) async {
    await _pumpShell(tester, withPlayer: false);
    await tester.drag(find.byType(ListView), const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(chrome.value, isTrue);
    await tester.tap(find.byTooltip('Search'));
    expect(searches, 1);
    await tester.tap(find.byTooltip('Home'));
    await tester.pumpAndSettle();
    expect(chrome.value, isFalse);
    expect(tester.takeException(), isNull);
  });
}
