import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/screens/local_genres_screen.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/theme/sistrum_theme.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Local extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();
}

class _Playback extends PlaybackController {
  final ids = <String>[];
  @override
  Future<void> playLocalLibraryQueue(
    List<LocalLibraryItem> items, {
    required LocalLibraryItem startItem,
  }) async => ids.add(startItem.id);
}

void main() {
  testWidgets(
    'genre opens tagged songs with artwork, explicit badge and playback',
    (tester) async {
      final player = _Playback();
      final requests = <GenrePageRequest>[];
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            localLibraryProvider.overrideWith(_Local.new),
            playbackProvider.overrideWith(() => player),
            genrePageLoaderProvider.overrideWithValue((request) async {
              requests.add(request);
              if (request.genre == null) {
                return [
                  {'genre_key': 'jazz', 'name': 'Jazz', 'track_count': 1},
                ];
              }
              return [
                LocalLibraryItem(
                  id: 'song',
                  trackName: 'Jazz song',
                  artistName: 'Artist',
                  albumName: 'Album',
                  filePath: '/music/jazz.flac',
                  scannedAt: DateTime(2026),
                  explicit: true,
                ).toJson(),
              ];
            }),
          ],
          child: MaterialApp(
            theme: SistrumTheme.build(Brightness.dark),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const LocalGenresScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Genres'), findsOneWidget);
      await tester.tap(find.text('Jazz'));
      await tester.pumpAndSettle();
      expect(find.text('Jazz song'), findsOneWidget);
      expect(find.text('E'), findsOneWidget);
      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      await tester.tap(find.text('Jazz song'));
      expect(player.ids, ['song']);
      expect(requests, [(genre: null, offset: 0), (genre: 'jazz', offset: 0)]);
      expect(tester.takeException(), isNull);
    },
  );
}
