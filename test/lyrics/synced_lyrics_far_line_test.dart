import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics.dart';

void main() {
  testWidgets('opens on a far line taller than the estimated row', (
    tester,
  ) async {
    // A narrow view: each line wraps and carries a romanization, several
    // times the estimated row height.
    tester.view.physicalSize = const Size(340, 800);
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
      lines: List.generate(
        80,
        (index) => LyricLine(
          time: Duration(seconds: index * 3),
          end: Duration(seconds: (index + 1) * 3),
          text: 'Fixture line $index wraps across the narrow panel twice',
          romanization: 'Romanized line $index also wraps across the panel',
        ),
      ),
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
              showPronunciation: true,
              showTranslation: false,
            ),
          ),
        ),
      ),
    );
    // Halfway through the song, as when the lyrics open mid-track.
    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 181),
      ),
    );
    await tester.pumpAndSettle();
    final line = find.textContaining('Romanized line 60 ', findRichText: true);
    expect(line, findsOneWidget);
    // Upstream 6a3e9ab7's case: the line is centred, not left off screen.
    expect(tester.getCenter(line).dy, inInclusiveRange(300, 560));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('reaches a very tall line far past the measured rows', (
    tester,
  ) async {
    // Past the measure-everything threshold, so rows beyond the viewport use
    // the estimated extent until they are built.
    tester.view.physicalSize = const Size(340, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final playback = StreamController<PlaybackState>.broadcast();
    final seek = ValueNotifier<Duration?>(null);
    addTearDown(playback.close);
    addTearDown(seek.dispose);
    final theme = AppTheme.build(Brightness.dark);
    const tallIndex = 220;
    final tallText = List.generate(70, (word) => 'word$word').join(' ');
    final lyrics = ParsedLyrics(
      synced: true,
      wordSynced: false,
      plainText: '',
      lines: List.generate(
        300,
        (index) => LyricLine(
          time: Duration(seconds: index * 3),
          end: Duration(seconds: (index + 1) * 3),
          text: index == tallIndex ? 'Tall $tallText' : 'Short line $index',
        ),
      ),
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
    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: tallIndex * 3 + 1),
      ),
    );
    await tester.pumpAndSettle();
    final line = find.textContaining('Tall word0', findRichText: true);
    expect(line, findsOneWidget);
    // Taller than the viewport, so it starts at the upper focus position.
    expect(tester.getTopLeft(line).dy, inInclusiveRange(16, 200));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
