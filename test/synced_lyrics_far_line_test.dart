import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/utils/lyrics_parser.dart';
import 'package:sistrum/widgets/player_lyrics.dart';

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
    final theme = SistrumTheme.build(Brightness.dark);
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
}
