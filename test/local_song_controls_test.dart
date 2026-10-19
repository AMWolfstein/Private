import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/local_song_menu.dart';
import 'package:spotiflac_android/widgets/local_song_row.dart';
import 'package:spotiflac_android/widgets/audio_analysis_widget.dart';

void main() {
  for (final numbered in [false, true]) {
    testWidgets(
      'song row uses ${numbered ? 'track number' : 'artwork'}, explicit badge and two actions',
      (tester) async {
        var plays = 0;
        final item = LocalLibraryItem(
          id: 'song',
          trackName: 'Song',
          artistName: 'Artist',
          albumName: 'Album',
          filePath: '/music/song.flac',
          scannedAt: DateTime(2026),
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: MornyeTheme.build(Brightness.dark),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => LocalSongRow(
                    title: 'Song',
                    artist: 'Artist',
                    explicit: true,
                    numbered: numbered,
                    number: 2,
                    onPlay: () => plays++,
                    onMenu: () => showLocalSongMenu(context, ref, item),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('E'), findsOneWidget);
        expect(find.text('2'), numbered ? findsOneWidget : findsNothing);
        expect(
          tester.getTopLeft(find.text('Artist')).dy,
          greaterThan(tester.getTopLeft(find.text('Song')).dy),
        );
        await tester.tap(find.text('Song'));
        await tester.tap(find.byTooltip('Play'));
        expect(plays, 2);
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        expect(find.text('Edit Metadata'), findsOneWidget);
        expect(find.text('Audio Quality Analysis'), findsOneWidget);
        for (final label in [
          'Share',
          'Copy file path',
          'Play next',
          'Remove from device',
          'ReplayGain',
        ]) {
          expect(find.text(label), findsNothing);
        }
        await tester.tap(find.text('Audio Quality Analysis'));
        await tester.pumpAndSettle();
        expect(find.byType(AudioQualityAnalysisScreen), findsOneWidget);
        expect(
          tester
              .widget<AudioAnalysisCard>(find.byType(AudioAnalysisCard))
              .filePath,
          item.filePath,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
}
