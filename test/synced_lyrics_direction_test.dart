import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/widgets/player/player_lyrics.dart';

void main() {
  testWidgets('Arabic lines run right to left in a left-to-right app', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final playback = StreamController<PlaybackState>.broadcast();
    final seek = ValueNotifier<Duration?>(null);
    addTearDown(playback.close);
    addTearDown(seek.dispose);
    final theme = AppTheme.build(Brightness.dark);
    final lyrics = ParsedLyrics(
      synced: true,
      wordSynced: false,
      plainText: '',
      lines: const [
        LyricLine(
          time: Duration.zero,
          end: Duration(seconds: 3),
          text: 'Hello',
        ),
        LyricLine(
          time: Duration(seconds: 3),
          end: Duration(seconds: 6),
          text: 'مرحبا',
        ),
      ],
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackStateProvider.overrideWith((ref) => playback.stream),
        ],
        child: MaterialApp(
          theme: theme,
          home: Scaffold(
            body: SyncedLyricsView(
              lyrics: lyrics,
              seekPreview: seek,
              colorScheme: theme.colorScheme,
              isActive: true,
              showPronunciation: false,
              showTranslation: false,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final english = find.textContaining('Hello', findRichText: true);
    final arabic = find.textContaining('مرحبا', findRichText: true);
    expect(english, findsOneWidget);
    expect(arabic, findsOneWidget);
    TextDirection directionOf(String text) => tester
        .renderObject<RenderParagraph>(
          find.textContaining(text, findRichText: true),
        )
        .textDirection;
    expect(directionOf('Hello'), TextDirection.ltr);
    expect(directionOf('مرحبا'), TextDirection.rtl);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
