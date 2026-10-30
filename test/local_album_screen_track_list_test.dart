import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/screens/library/local_album_screen.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/library/album_track_tile.dart';

void main() {
  testWidgets('tracks are listed in track-number order, not scan order', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final tracks = [
      for (final number in [3, 1, 2])
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
        child: MaterialApp(
          theme: AppTheme.build(Brightness.light),
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

    final names = tester
        .widgetList<AlbumTrackTile>(find.byType(AlbumTrackTile))
        .map((tile) => tile.trackName)
        .toList();
    expect(names, ['Song 1', 'Song 2', 'Song 3']);
    expect(tester.takeException(), isNull);
  });
}
