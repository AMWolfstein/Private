import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/widgets/player/app_player_lyrics_viewport.dart';

void main() {
  testWidgets('the lyrics viewport keeps its child on screen', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => SizedBox(
              height: 300,
              child: appLyricsViewport(
                context,
                const Center(child: Text('Lyric line')),
                visibleHeight: 200,
                lyricsControlsHidden: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lyric line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('hiding the controls reveals the viewport over time', (
    tester,
  ) async {
    Widget viewport({required bool hidden}) => MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => SizedBox(
            height: 300,
            child: appLyricsViewport(
              context,
              const Center(child: Text('Lyric line')),
              visibleHeight: 200,
              lyricsControlsHidden: hidden,
            ),
          ),
        ),
      ),
    );
    await tester.pumpWidget(viewport(hidden: false));
    await tester.pumpWidget(viewport(hidden: true));
    await tester.pumpAndSettle();
    expect(find.text('Lyric line'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
