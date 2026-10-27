import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/theme/cover_palette.dart';
import 'package:sistrum/widgets/album_detail_header.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final brightness in Brightness.values) {
    for (final (width, scale, direction) in [
      (320.0, 1.0, TextDirection.ltr),
      (393.0, 1.0, TextDirection.rtl),
      (320.0, 2.0, TextDirection.rtl),
    ]) {
      testWidgets(
        'four collection actions fit and stay ordered ($brightness, $width, $scale, $direction)',
        (tester) async {
          tester.view.physicalSize = Size(width, 600);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          final calls = <String>[];
          await tester.pumpWidget(
            ProviderScope(
              child: MaterialApp(
                theme: SistrumTheme.build(brightness),
                home: MediaQuery(
                  data: MediaQueryData(
                    size: Size(width, 600),
                    textScaler: TextScaler.linear(scale),
                  ),
                  child: Directionality(
                    textDirection: direction,
                    child: Scaffold(
                      body: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          child: AlbumPlayActions(
                            playLabel: 'Play',
                            shuffleTooltip: 'Shuffle',
                            onPlay: () => calls.add('play'),
                            onShuffle: () => calls.add('shuffle'),
                            leadingAction: HeaderCircleButton(
                              icon: CupertinoIcons.heart,
                              tooltip: 'Loved',
                              buttonSize: 48,
                              onPressed: () => calls.add('loved'),
                            ),
                            trailingAction: HeaderCircleButton(
                              icon: CupertinoIcons.text_badge_plus,
                              tooltip: 'Add to playlist',
                              buttonSize: 48,
                              onPressed: () => calls.add('playlist'),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          final loved = find.byTooltip('Loved');
          final playlist = find.byTooltip('Add to playlist');
          Finder pill(String label) => find.ancestor(
            of: scale >= 1.3 ? find.byTooltip(label) : find.text(label),
            matching: find.byType(CupertinoButton),
          );
          if (scale >= 1.3) {
            expect(find.text('Play'), findsNothing);
            expect(find.text('Shuffle'), findsNothing);
          }
          final play = pill('Play');
          final shuffle = pill('Shuffle');
          final rects = [
            loved,
            play,
            shuffle,
            playlist,
          ].map(tester.getRect).toList();
          for (var i = 0; i < rects.length; i++) {
            final bounds = rects[i];
            expect(bounds.width, greaterThanOrEqualTo(48));
            expect(bounds.height, greaterThanOrEqualTo(48));
            expect(bounds.left, greaterThanOrEqualTo(20));
            expect(bounds.right, lessThanOrEqualTo(width - 20));
            expect(bounds.center.dy, closeTo(rects.first.center.dy, .1));
            if (i > 0) expect(bounds.left, greaterThan(rects[i - 1].right));
          }
          expect(rects[1].width, closeTo(rects[2].width, .1));
          final scheme = HeaderPalette.of(tester.element(play));
          expect(tester.widget<CupertinoButton>(play).color, scheme.primary);
          expect(
            tester.widget<CupertinoButton>(shuffle).color,
            isNot(scheme.primary),
          );
          for (final button in [loved, play, shuffle, playlist]) {
            await tester.tap(button);
          }
          expect(calls, ['loved', 'play', 'shuffle', 'playlist']);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
