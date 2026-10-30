import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyric_strip.dart';

const _lyrics = ParsedLyrics(
  synced: true,
  wordSynced: false,
  plainText: '',
  lines: [
    LyricLine(time: Duration(seconds: 1), text: 'First line'),
    LyricLine(time: Duration(seconds: 4), text: 'مرحبا بالعالم'),
  ],
);

Future<void> _pump(
  WidgetTester tester,
  ParsedLyrics lyrics,
  ValueNotifier<Duration> position,
) => tester.pumpWidget(
  ProviderScope(
    overrides: [playbackPositionProvider.overrideWith((ref) => position.value)],
    child: MaterialApp(
      home: Scaffold(
        body: PlayerLyricStrip(lyrics: lyrics, color: Colors.white),
      ),
    ),
  ),
);

void main() {
  testWidgets('shows the line whose time has passed', (tester) async {
    final position = ValueNotifier(const Duration(seconds: 2));
    await _pump(tester, _lyrics, position);
    expect(find.text('First line'), findsOneWidget);
  });

  testWidgets('shows nothing before the first line', (tester) async {
    final position = ValueNotifier(Duration.zero);
    await _pump(tester, _lyrics, position);
    expect(find.text('First line'), findsNothing);
    expect(find.byType(Text), findsOneWidget);
  });

  testWidgets('a right-to-left line is laid out right to left', (tester) async {
    final position = ValueNotifier(const Duration(seconds: 5));
    await _pump(tester, _lyrics, position);
    final text = tester.widget<Text>(find.text('مرحبا بالعالم'));
    expect(text.textDirection, TextDirection.rtl);
  });

  testWidgets('plain lyrics keep the strip space but show no text', (
    tester,
  ) async {
    const plain = ParsedLyrics(
      synced: false,
      wordSynced: false,
      plainText: 'Verse',
      lines: [LyricLine(time: Duration.zero, text: 'Verse')],
    );
    final position = ValueNotifier(const Duration(seconds: 2));
    await _pump(tester, plain, position);
    expect(find.text('Verse'), findsNothing);
    expect(find.byType(Text), findsNothing);
    expect(
      tester.getSize(find.byType(PlayerLyricStrip)).height,
      kPlayerLyricStripHeight,
    );
  });

  testWidgets('a song without lyrics keeps the strip space', (tester) async {
    final position = ValueNotifier(const Duration(seconds: 2));
    await _pump(tester, ParsedLyrics.empty, position);
    expect(
      tester.getSize(find.byType(PlayerLyricStrip)).height,
      kPlayerLyricStripHeight,
    );
  });
}
