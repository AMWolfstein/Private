import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/widgets/shell/app_bottom_bar.dart';

Future<void> _pumpBar(
  WidgetTester tester, {
  required ValueChanged<int> onSelected,
  required VoidCallback onSearch,
  bool withPlayer = true,
  bool collapsed = false,
  int selectedIndex = 0,
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
        theme: AppTheme.build(Brightness.light),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          extendBody: true,
          body: const SizedBox.expand(),
          bottomNavigationBar: AppBottomBar(
            collapsed: collapsed,
            selectedIndex: selectedIndex,
            onSelected: onSelected,
            onHome: () => onSelected(0),
            onSearch: onSearch,
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.library_music_outlined),
                label: 'Library',
              ),
              NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('tapping a tab selects its index', (tester) async {
    int? selected;
    await _pumpBar(
      tester,
      onSelected: (index) => selected = index,
      onSearch: () {},
    );
    await tester.tap(find.text('Library'));
    await tester.pump();
    expect(selected, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the search destination calls onSearch', (tester) async {
    var searches = 0;
    await _pumpBar(tester, onSelected: (_) {}, onSearch: () => searches++);
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(searches, 1);
  });

  testWidgets('a collapsed bar builds without a playing track', (tester) async {
    await _pumpBar(
      tester,
      onSelected: (_) {},
      onSearch: () {},
      withPlayer: false,
      collapsed: true,
    );
    await tester.pump(const Duration(milliseconds: 400));
    expect(tester.takeException(), isNull);
  });
}
