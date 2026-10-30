import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics_controls.dart';

void main() {
  for (final hidden in [false, true]) {
    testWidgets(
      'lyrics controls ${hidden ? 'hide' : 'show'} with their state',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: PlayerLyricsControlsVisibility(
                hidden: hidden,
                child: const ElevatedButton(
                  onPressed: null,
                  child: Text('Lyrics button'),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final opacity = tester.widget<AnimatedOpacity>(
          find.byType(AnimatedOpacity),
        );
        expect(opacity.opacity, hidden ? 0 : 1);
        final ignored = tester.widget<IgnorePointer>(
          find
              .descendant(
                of: find.byType(PlayerLyricsControlsVisibility),
                matching: find.byType(IgnorePointer),
              )
              .first,
        );
        expect(ignored.ignoring, hidden);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
