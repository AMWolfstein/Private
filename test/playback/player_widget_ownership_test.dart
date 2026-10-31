import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/providers/playback/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/core/navigation/now_playing_route.dart';
import 'package:sistrum/utils/playback/playback_seek_preview.dart';
import 'package:sistrum/widgets/status/audio_quality_badges.dart';
import 'package:sistrum/widgets/player/layout/app_player_layout.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/player/sheets/player_details_sheet.dart';
import 'package:sistrum/widgets/player/layout/player_gesture_regions.dart';

MediaItem _item(String id, {String? source}) => MediaItem(
  id: id,
  title: id,
  artist: 'Artist',
  album: 'Album',
  duration: const Duration(minutes: 3),
  extras: {'source': source ?? '/music/$id.flac'},
);

class _FooterRoute extends NowPlayingRoute {
  _FooterRoute(this.onOpenQueue) : super(child: const SizedBox());

  final VoidCallback onOpenQueue;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => PlayerQueueSwipeRegion(
    onOpenQueue: onOpenQueue,
    child: const ColoredBox(
      key: ValueKey('gesture-player'),
      color: Colors.black,
    ),
  );
}

void main() {
  testWidgets('metadata and mode changes leave the player visual intact', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(430, 932);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final read = Completer<Map<String, dynamic>>();
    final metadata = PlayerMetadataController(readMetadata: (_) => read.future);
    final seekPreview = PlaybackSeekPreview();
    final playback = StreamController<PlaybackState>.broadcast();
    addTearDown(metadata.dispose);
    addTearDown(seekPreview.dispose);
    addTearDown(playback.close);
    final artworkForeground = ValueNotifier<Map<String, Color>>({});
    addTearDown(artworkForeground.dispose);
    final item = _item('First');
    final pending = metadata.load(item);
    var visualBuilds = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          playbackStateProvider.overrideWith((ref) => playback.stream),
          playerCollectionTrackProvider.overrideWith(
            (ref, item) async => Track(
              id: item.id,
              name: item.title,
              artistName: item.artist ?? '',
              albumName: item.album ?? '',
              duration: 180,
              source: 'local',
            ),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: AppPlayerLayout(
                mediaItem: item,
                metadata: metadata,
                seekPreview: seekPreview,
                colorScheme: Theme.of(context).colorScheme,
                page: 1,
                motionArtwork: const SizedBox(),
                insetArtwork: true,
                artworkTopInset: 0,
                artworkKeys: (
                  header: GlobalKey(),
                  controls: GlobalKey(),
                  volume: GlobalKey(),
                  expanded: GlobalKey(),
                  compact: GlobalKey(),
                ),
                artworkForeground: artworkForeground,
                lyricsControlsHidden: false,
                lyricsOptionsOpen: false,
                lyricsOptions: null,
                onPageChanged: (_) {},
                onTrackNavigation: (_, _) async {},
                onMoreActions: (_, _, _) async {},
                lyricsBuilder: (_) {
                  visualBuilds++;
                  return const SizedBox.expand(key: ValueKey('lyrics-visual'));
                },
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final visualElement = tester.element(
      find.byKey(const ValueKey('lyrics-visual')),
    );
    read.complete({
      'explicit': true,
      'format': 'FLAC',
      'sample_rate': 48000,
      'bit_depth': 24,
    });
    await pending;
    await tester.pumpAndSettle();
    expect(
      tester.element(find.byKey(const ValueKey('lyrics-visual'))),
      same(visualElement),
    );
    expect(
      tester
          .widget<ExplicitTrackTitle>(find.byType(ExplicitTrackTitle))
          .explicit,
      isTrue,
    );
    final beforeClock = visualBuilds;
    const quality = 'FLAC  ·  24-bit  ·  48 kHz';
    final qualityWidget = tester.widget<Text>(find.text(quality));

    playback.add(
      PlaybackState(
        processingState: AudioProcessingState.ready,
        updatePosition: const Duration(seconds: 45),
        shuffleMode: AudioServiceShuffleMode.all,
        repeatMode: AudioServiceRepeatMode.one,
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(visualBuilds, beforeClock);
    expect(find.bySemanticsLabel('0:45'), findsOneWidget);
    expect(
      identical(tester.widget<Text>(find.text(quality)), qualityWidget),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('details retain their captured item when playback changes', (
    tester,
  ) async {
    final read = Completer<Map<String, dynamic>>();
    final metadata = PlayerMetadataController(
      readMetadata: (path) => path.startsWith('content://')
          ? read.future
          : Future.value({'title': 'Second tags'}),
    );
    addTearDown(metadata.dispose);
    final first = _item('First', source: 'content://library/first.flac');
    await metadata.load(first);
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showPlayerDetailsSheet(
                  context,
                  Theme.of(context).colorScheme,
                  metadata: metadata,
                  mediaItem: first,
                ),
                child: const Text('Details'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Details'));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNWidgets(2));
    await metadata.load(_item('Second'));
    read.complete({'title': 'First tags'});
    await tester.pumpAndSettle();
    expect(find.text('First tags'), findsOneWidget);
    expect(find.text('Second tags'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('footer opens the queue upwards and dismisses downwards', (
    tester,
  ) async {
    final navigator = GlobalKey<NavigatorState>();
    var queueOpens = 0;
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(navigatorKey: navigator, home: const SizedBox()),
      ),
    );
    navigator.currentState!.push(_FooterRoute(() => queueOpens++));
    await tester.pumpAndSettle();
    final footer = find.byKey(const ValueKey('gesture-player'));
    await tester.fling(footer, const Offset(0, -80), 600);
    await tester.pumpAndSettle();
    expect(queueOpens, 1);
    expect(footer, findsOneWidget);
    await tester.fling(footer, const Offset(0, 240), 1000);
    await tester.pumpAndSettle();
    expect(queueOpens, 1);
    expect(footer, findsNothing);
    expect(tester.takeException(), isNull);
  });
}
