import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mini_player.dart';

void main() {
  Future<void> pumpPlayer(
    WidgetTester tester,
    StreamController<MediaItem?> media,
  ) async {
    SharedPreferences.setMockInitialValues({});
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          currentMediaItemProvider.overrideWithBuild(
            (ref, notifier) => media.stream,
          ),
          playbackStateProvider.overrideWith(
            (ref) => Stream.value(PlaybackState(playing: true)),
          ),
          lowEndDeviceProvider.overrideWithValue(true),
          mornyeLiquidGlassProvider.overrideWithValue(false),
        ],
        child: MaterialApp(
          theme: MornyeTheme.build(Brightness.light),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: Align(alignment: Alignment.bottomCenter, child: MiniPlayer()),
          ),
        ),
      ),
    );
  }

  testWidgets('mounted mini player follows track and metadata changes', (
    tester,
  ) async {
    final media = StreamController<MediaItem?>();
    addTearDown(media.close);
    await pumpPlayer(tester, media);
    const first = MediaItem(id: 'first', title: 'First', artist: 'Artist A');
    const second = MediaItem(id: 'second', title: 'Second', artist: 'Artist B');
    State? playerState;
    String? previousTitle;
    String? previousArtist;
    for (final item in [
      first,
      second,
      second.copyWith(title: 'Revised', artist: 'Artist C'),
      first,
    ]) {
      media.add(item);
      await tester.pumpAndSettle();
      expect(find.text(item.title), findsWidgets);
      expect(find.text(item.artist!), findsWidgets);
      if (previousTitle != null) {
        expect(find.text(previousTitle), findsNothing);
        expect(find.text(previousArtist!), findsNothing);
      }
      playerState ??= tester.state(find.byType(MiniPlayer));
      expect(tester.state(find.byType(MiniPlayer)), same(playerState));
      expect(tester.takeException(), isNull);
      previousTitle = item.title;
      previousArtist = item.artist;
    }
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('returning to the mini player shows the latest song', (
    tester,
  ) async {
    final media = StreamController<MediaItem?>();
    addTearDown(media.close);
    await pumpPlayer(tester, media);
    media.add(const MediaItem(id: 'first', title: 'First', artist: 'Artist A'));
    await tester.pumpAndSettle();
    final playerState = tester.state(find.byType(MiniPlayer));
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push<void>(
        MaterialPageRoute(
          builder: (_) => const Scaffold(body: Text('Another screen')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    media.add(
      const MediaItem(id: 'second', title: 'Second', artist: 'Artist B'),
    );
    await tester.pumpAndSettle();
    media.add(const MediaItem(id: 'third', title: 'Third', artist: 'Artist C'));
    await tester.pumpAndSettle();
    navigator.pop();
    await tester.pumpAndSettle();
    expect(find.text('Third'), findsWidgets);
    expect(find.text('Artist C'), findsWidgets);
    expect(find.text('First'), findsNothing);
    expect(find.text('Second'), findsNothing);
    expect(tester.state(find.byType(MiniPlayer)), same(playerState));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
