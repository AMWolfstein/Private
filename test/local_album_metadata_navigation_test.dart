import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/screens/local_album_screen.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'support/material_test_theme.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/album_track_tile.dart';

class _Playback extends PlaybackController {
  final played = <String>[];

  @override
  Future<void> playLocalLibraryQueue(
    List<LocalLibraryItem> items, {
    required LocalLibraryItem startItem,
  }) async {
    played.add(startItem.id);
  }
}

void main() {
  for (final mornye in [false, true]) {
    testWidgets('album row and Play both play ($mornye)', (tester) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = const Size(430, 1200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final playback = _Playback();
      final navigator = GlobalKey<NavigatorState>();
      final tracks = [
        for (final number in [2, 1])
          LocalLibraryItem(
            id: '$number',
            trackName: 'Song $number',
            artistName: 'Artist',
            albumName: 'Album',
            filePath: '/missing/song-$number.flac',
            trackNumber: number,
            scannedAt: DateTime(2026),
          ),
      ];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [playbackProvider.overrideWith(() => playback)],
          child: MaterialApp(
            navigatorKey: navigator,
            theme: mornye
                ? MornyeTheme.build(Brightness.light)
                : AppTheme.light(),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: LocalAlbumScreen(
              albumName: 'Album',
              artistName: 'Artist',
              tracks: tracks,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(find.text('Song 2'), 150);
      await tester.tap(find.text('Song 2'));
      await tester.pumpAndSettle();
      expect(playback.played, ['2']);
      final row = find.byWidgetPredicate(
        (widget) => widget is AlbumTrackTile && widget.trackName == 'Song 2',
      );
      await tester.tap(
        find.descendant(of: row, matching: find.byTooltip('Play')),
      );
      await tester.pumpAndSettle();
      expect(playback.played, ['2', '2']);
      expect(tester.takeException(), isNull);
    });
  }
}
