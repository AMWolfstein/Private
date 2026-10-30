import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/player_metadata_controller.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/utils/playback/playback_seek_preview.dart';
import 'package:sistrum/widgets/player/controls/player_playback_controls.dart';

/// Records which transport action the controls asked for.
class _RecordingController extends MusicPlayerController {
  final calls = <String>[];

  @override
  Future<void> next() async => calls.add('next');

  @override
  Future<void> previous() async => calls.add('previous');

  @override
  Future<void> togglePlayPause(bool isPlaying) async =>
      calls.add('toggle:$isPlaying');
}

Future<_RecordingController> _pump(
  WidgetTester tester, {
  required bool playing,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final controller = _RecordingController();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        musicPlayerControllerProvider.overrideWithValue(controller),
        playbackPlayingProvider.overrideWithValue(playing),
        playbackLoadingProvider.overrideWithValue(false),
        playbackPositionProvider.overrideWithValue(Duration.zero),
      ],
      child: MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: PlayerPlaybackControls(
            mediaId: 'song',
            duration: const Duration(minutes: 3),
            seekPreview: PlaybackSeekPreview(),
            colorScheme: const ColorScheme.dark(),
            metadata: PlayerMetadataController(),
          ),
        ),
      ),
    ),
  );
  // The transport animates while playing, so pump fixed frames.
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return controller;
}

AppLocalizations _l10n(WidgetTester tester) =>
    AppLocalizations.of(tester.element(find.byType(PlayerPlaybackControls)));

void main() {
  testWidgets('while playing, the middle button offers pause', (tester) async {
    await _pump(tester, playing: true);
    expect(find.byTooltip(_l10n(tester).actionPause), findsOneWidget);
  });

  testWidgets('while paused, the middle button offers play', (tester) async {
    await _pump(tester, playing: false);
    expect(find.byTooltip(_l10n(tester).tooltipPlay), findsOneWidget);
  });

  testWidgets('the middle button toggles playback from its current state', (
    tester,
  ) async {
    final controller = await _pump(tester, playing: true);
    await tester.tap(find.byTooltip(_l10n(tester).actionPause));
    await tester.pump();
    expect(controller.calls, ['toggle:true']);
  });

  testWidgets('previous and next go to the neighbouring tracks', (
    tester,
  ) async {
    final controller = await _pump(tester, playing: false);
    final l10n = _l10n(tester);
    await tester.tap(find.byTooltip(l10n.nowPlayingPreviousTrack));
    await tester.pump();
    await tester.tap(find.byTooltip(l10n.nowPlayingNextTrack));
    await tester.pump();
    expect(controller.calls, ['previous', 'next']);
  });

  testWidgets('lyrics loaded after the controls are built reach the strip', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final metadata = PlayerMetadataController(
      readMetadata: (_) async => {'lyrics': '[00:01.00]Hello'},
      parseLyrics: (_) async => const ParsedLyrics(
        synced: true,
        wordSynced: false,
        plainText: '',
        lines: [LyricLine(time: Duration(seconds: 1), text: 'Hello')],
      ),
    );
    addTearDown(metadata.dispose);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialSettingsProvider.overrideWithValue(
            const AppSettings(lyricsAboveSeekBar: true),
          ),
          playbackPlayingProvider.overrideWithValue(false),
          playbackLoadingProvider.overrideWithValue(false),
          playbackPositionProvider.overrideWithValue(
            const Duration(seconds: 2),
          ),
        ],
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: PlayerPlaybackControls(
              mediaId: 'song',
              duration: const Duration(minutes: 3),
              seekPreview: PlaybackSeekPreview(),
              colorScheme: const ColorScheme.dark(),
              metadata: metadata,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Hello'), findsNothing);

    await tester.runAsync(
      () => metadata.load(
        const MediaItem(
          id: 'song',
          title: 'Song',
          extras: {'source': '/music/song.flac'},
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Hello'), findsOneWidget);
  });
}
