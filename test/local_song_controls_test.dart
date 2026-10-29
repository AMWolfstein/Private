import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/audio_analysis/audio_analysis_widget.dart';

void main() {
  for (final numbered in [false, true]) {
    testWidgets(
      'song row uses ${numbered ? 'track number' : 'artwork'}, explicit badge and two actions',
      (tester) async {
        var plays = 0;
        final directory = Directory.systemTemp.createTempSync('song-menu-');
        addTearDown(() => directory.deleteSync(recursive: true));
        final path = '${directory.path}/song.flac';
        File(path).writeAsBytesSync([102, 76, 97, 67, 0, 0, 0, 0]);
        final item = LocalLibraryItem(
          id: 'song',
          trackName: 'Song',
          artistName: 'Artist',
          albumName: 'Album',
          filePath: path,
          scannedAt: DateTime(2026),
        );
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              theme: SistrumTheme.build(Brightness.dark),
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
                    onMenu: (anchor) =>
                        showLocalSongMenu(context, ref, item, anchor: anchor),
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
        await tester.tap(find.byTooltip('Play Song by Artist'));
        expect(plays, 2);
        await tester.tap(find.byIcon(Icons.more_horiz));
        await tester.pumpAndSettle();
        expect(find.text('Edit Metadata'), findsOneWidget);
        expect(find.text('Audio Quality Analysis'), findsOneWidget);
        final l10n = AppLocalizations.of(
          tester.element(find.byType(LocalSongRow)),
        );
        for (final label in [
          l10n.trackMetadataShare,
          l10n.trackCopyFilePath,
          l10n.trackPlayNext,
          l10n.trackAddToQueue,
          l10n.trackRemoveFromDevice,
          l10n.trackReplayGain,
          l10n.trackRemoveReplayGain,
          l10n.homeGoToAlbum,
          l10n.sistrumGoToArtist,
        ]) {
          expect(find.text(label), findsOneWidget);
        }
        await tester.ensureVisible(find.text('Audio Quality Analysis'));
        await tester.pumpAndSettle();
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
