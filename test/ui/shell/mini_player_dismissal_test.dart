import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/player/mini_player.dart';

class _Controller extends MusicPlayerController {
  int stops = 0;
  final stopped = Completer<void>();

  @override
  Future<void> stop() async {
    stops++;
    await stopped.future;
  }
}

void main() {
  for (final initiallyPlaying in [false, true]) {
    for (final reset in ['null item', 'playing same ID', 'different ID']) {
      testWidgets(
        'swipe dismissal resets after $reset (playing=$initiallyPlaying)',
        (tester) async {
          SharedPreferences.setMockInitialValues({});
          final media = StreamController<MediaItem?>();
          final states = StreamController<PlaybackState>();
          addTearDown(media.close);
          addTearDown(states.close);
          final controller = _Controller();
          addTearDown(() {
            if (!controller.stopped.isCompleted) controller.stopped.complete();
          });
          const song = MediaItem(id: 'song', title: 'Song', artist: 'Artist');
          final songBar = find.byKey(const ValueKey('mini-player-song'));

          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                currentMediaItemProvider.overrideWithBuild(
                  (ref, notifier) => media.stream,
                ),
                playbackStateProvider.overrideWith((ref) => states.stream),
                musicPlayerControllerProvider.overrideWithValue(controller),
                lowEndDeviceProvider.overrideWithValue(true),
                appLiquidGlassProvider.overrideWithValue(false),
              ],
              child: MaterialApp(
                theme: AppTheme.build(Brightness.light),
                localizationsDelegates: AppLocalizations.localizationsDelegates,
                supportedLocales: AppLocalizations.supportedLocales,
                home: const Scaffold(
                  body: Align(
                    alignment: Alignment.bottomCenter,
                    child: MiniPlayer(),
                  ),
                ),
              ),
            ),
          );
          states.add(PlaybackState(playing: initiallyPlaying));
          media.add(song);
          await tester.pumpAndSettle();
          expect(songBar, findsOneWidget);
          final playerState = tester.state(find.byType(MiniPlayer));

          await tester.drag(songBar, const Offset(700, 0));
          await tester.pumpAndSettle();
          expect(controller.stops, 1);
          expect(controller.stopped.isCompleted, isFalse);
          expect(songBar, findsNothing);
          expect(tester.takeException(), isNull);

          // Stop is deliberately pending and its old playing flag is still
          // true in the initially-playing cases. A same-ID metadata rebuild
          // must not reinsert the dismissed Dismissible into the tree.
          media.add(const MediaItem(id: 'song', title: 'Song refreshed'));
          await tester.pumpAndSettle();
          expect(songBar, findsNothing);
          expect(tester.takeException(), isNull);
          controller.stopped.complete();

          switch (reset) {
            case 'null item':
              media.add(null);
              states.add(PlaybackState(playing: false));
              await tester.pumpAndSettle();
              expect(find.byType(Dismissible), findsNothing);
              media.add(song);
            case 'playing same ID':
              states.add(PlaybackState(playing: false));
              await tester.pumpAndSettle();
              expect(songBar, findsNothing);
              states.add(PlaybackState(playing: true));
              await tester.pumpAndSettle();
              expect(songBar, findsOneWidget);
              states.add(PlaybackState(playing: false));
            case 'different ID':
              states.add(PlaybackState(playing: false));
              media.add(const MediaItem(id: 'other', title: 'Other song'));
              await tester.pumpAndSettle();
              expect(
                find.byKey(const ValueKey('mini-player-other')),
                findsOneWidget,
              );
              // Returning paused to the original ID must not revive a latch.
              media.add(song);
          }
          await tester.pumpAndSettle();
          expect(songBar, findsOneWidget);
          expect(find.byTooltip('Play'), findsOneWidget);
          expect(tester.state(find.byType(MiniPlayer)), same(playerState));
          expect(controller.stops, 1);
          expect(tester.takeException(), isNull);

          // Cancel subscriptions before tearing down the stream controllers.
          await tester.pumpWidget(const SizedBox.shrink());
        },
      );
    }
  }

  testWidgets('TalkBack can dismiss the mini player', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final media = StreamController<MediaItem?>();
    final states = StreamController<PlaybackState>();
    addTearDown(media.close);
    addTearDown(states.close);
    final controller = _Controller();
    addTearDown(() {
      if (!controller.stopped.isCompleted) controller.stopped.complete();
    });
    const song = MediaItem(id: 'song', title: 'Song', artist: 'Artist');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMediaItemProvider.overrideWithBuild(
            (ref, notifier) => media.stream,
          ),
          playbackStateProvider.overrideWith((ref) => states.stream),
          musicPlayerControllerProvider.overrideWithValue(controller),
          lowEndDeviceProvider.overrideWithValue(true),
          appLiquidGlassProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer()),
          ),
        ),
      ),
    );
    states.add(PlaybackState(playing: true));
    media.add(song);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('mini-player-song')), findsOneWidget);

    final semantics = tester.widget<Semantics>(
      find.byWidgetPredicate(
        (widget) =>
            widget is Semantics &&
            widget.properties.customSemanticsActions != null &&
            widget.properties.customSemanticsActions!.isNotEmpty,
      ),
    );
    final action = semantics.properties.customSemanticsActions!.keys.single;
    expect(action.label, 'Dismiss mini player');
    semantics.properties.customSemanticsActions!.values.single();
    await tester.pumpAndSettle();

    expect(controller.stops, 1);
    expect(find.byKey(const ValueKey('mini-player-song')), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
