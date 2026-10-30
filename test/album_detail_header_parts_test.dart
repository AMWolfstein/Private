import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/cover_palette_provider.dart';
import 'package:sistrum/services/library/cover_palette.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/collection_scaffold.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/header/album_play_actions.dart';

void main() {
  final palette = CoverPaletteCache();

  for (final reduceMotion in [false, true]) {
    testWidgets('pulling the album stretches its artwork only with motion '
        '(reduced motion: $reduceMotion)', (tester) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      tester.view.padding = FakeViewPadding(top: 59, bottom: 34);
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      const artworkKey = ValueKey('album-part-artwork');
      var plays = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [coverPaletteProvider.overrideWithValue(palette)],
          child: MaterialApp(
            theme: AppTheme.build(Brightness.dark),
            scrollBehavior: const MaterialScrollBehavior().copyWith(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
            ),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
            home: CollectionScaffold(
              scrollController: controller,
              isSelectionMode: false,
              onExitSelectionMode: () {},
              appBar: AlbumDetailHeader(
                immersive: true,
                title: 'Album',
                expandedHeight: 400,
                showTitleInAppBar: false,
                background: const ColoredBox(
                  key: artworkKey,
                  color: Colors.orange,
                ),
                actions: AlbumPlayActions(
                  playLabel: 'Play',
                  shuffleTooltip: 'Shuffle',
                  onPlay: () => plays++,
                  onShuffle: () {},
                ),
              ),
              slivers: const [
                SliverToBoxAdapter(child: Text('Track list')),
                SliverToBoxAdapter(child: SizedBox(height: 2000)),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final artwork = find.byKey(artworkKey);
      final originalArt = tester.getRect(artwork);
      final gesture = await tester.startGesture(const Offset(195, 250));
      await gesture.moveBy(const Offset(0, 150));
      await tester.pump();

      final stretched = tester.getRect(artwork);
      expect(controller.offset, lessThan(0));
      if (reduceMotion) {
        expect(stretched.size, originalArt.size);
      } else {
        expect(stretched.width, greaterThan(originalArt.width));
      }
      // The play control stays where the user can still reach it.
      expect(find.text('Play').hitTestable(), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(artwork), originalArt);
      await tester.tap(find.text('Play'));
      expect(plays, 1);
      expect(tester.takeException(), isNull);
    });
  }
}
