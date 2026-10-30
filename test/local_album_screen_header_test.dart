import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/screens/library/local_album/local_album_screen.dart';
import 'package:sistrum/theme/app_theme.dart';

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
  testWidgets('the header names the album and Play starts its first track', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.physicalSize = const Size(430, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final playback = _Playback();
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
    expect(find.text('Album'), findsWidgets);
    expect(find.text('Artist'), findsWidgets);

    final l10n = AppLocalizations.of(
      tester.element(find.byType(LocalAlbumScreen)),
    );
    await tester.tap(find.text(l10n.tooltipPlay).first);
    await tester.pumpAndSettle();
    expect(playback.played, ['1']);
    expect(tester.takeException(), isNull);
  });
}
