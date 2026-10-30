import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/library/section_tab/library_section_tab.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/theme/app_theme.dart';

/// Shared harness for widget tests that drive [LibrarySectionTab] end to end.
///
/// The library's `part` files are private to that screen, so their behaviour
/// is reached through the screen with these fakes in place of the database,
/// settings and collections.

class LibrarySectionSettings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class LibrarySectionLocal extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();

  @override
  Future<void> reloadFromStorage() async {}
}

class LibrarySectionCollections extends LibraryCollectionsNotifier {
  LibrarySectionCollections([this._state]);

  final LibraryCollectionsState? _state;

  @override
  LibraryCollectionsState build() =>
      _state ?? LibraryCollectionsState(isLoaded: true);
}

/// Playlists named [names], with ids equal to the lower-cased names.
LibraryCollectionsState playlistsNamed(List<String> names) =>
    LibraryCollectionsState(
      isLoaded: true,
      playlists: [
        for (final name in names)
          UserPlaylistCollection(
            id: name.toLowerCase(),
            name: name,
            createdAt: DateTime.utc(2026),
            updatedAt: DateTime.utc(2026),
            tracks: const [],
          ),
      ],
    );

/// An album row served to the Albums section.
typedef LibraryTestAlbum = ({String name, String artist, int tracks});

/// Installs an sqflite mock that serves [songs] as the visible local library.
///
/// Call from `setUp` in a test file. The mock answers the browse count and
/// queue queries the Songs tab issues; every other query returns no rows.
void installLibrarySongsDatabase({
  required List<String> songs,
  List<LibraryTestAlbum> albums = const [],
}) {
  SharedPreferences.setMockInitialValues({});
  final previousFactory = databaseFactoryOrNull;
  databaseFactory = databaseFactorySqflitePlugin;
  addTearDownSafe(() => databaseFactory = previousFactory);

  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const paths = MethodChannel('plugins.flutter.io/path_provider');
  messenger.setMockMethodCallHandler(paths, (_) async => '/test/documents');
  addTearDownSafe(() => messenger.setMockMethodCallHandler(paths, null));

  const sqlite = MethodChannel('com.tekartik.sqflite');
  final versions = <int, int>{};
  messenger.setMockMethodCallHandler(sqlite, (call) async {
    final args = (call.arguments as Map?) ?? {};
    if (call.method == 'openDatabase') {
      final id = versions.length + 1;
      versions[id] = LibraryDatabase.schemaVersion;
      return {'id': id};
    }
    final sql = args['sql'] as String? ?? '';
    if (call.method == 'execute' && sql.contains('CREATE VIRTUAL TABLE')) {
      throw PlatformException(code: 'sqlite_error', message: 'no fts5');
    }
    if (call.method != 'query') return null;
    if (sql.toLowerCase().contains('pragma user_version')) {
      return {
        'columns': ['user_version'],
        'rows': [
          [versions[args['id']]],
        ],
      };
    }
    if (songs.isNotEmpty && sql.contains('AS all_count')) {
      return {
        'columns': ['all_count', 'single_count', 'album_count'],
        'rows': [
          [songs.length, songs.length, 0],
        ],
      };
    }
    if (albums.isNotEmpty &&
        sql.contains('album_key') &&
        sql.contains('LIMIT ?') &&
        !sql.contains('track_name')) {
      return {
        'columns': [
          'queue_source',
          'album_key',
          'album_name',
          'artist_name',
          'cover_path',
          'sample_file_path',
          'track_count',
          'album_completeness',
          'album_present_tracks',
          'album_expected_tracks',
        ],
        'rows': [
          for (final album in albums)
            [
              'local',
              album.name.toLowerCase(),
              album.name,
              album.artist,
              null,
              '',
              album.tracks,
              null,
              null,
              null,
            ],
        ],
      };
    }
    if (songs.isNotEmpty &&
        sql.contains('AS queue_source') &&
        sql.contains('track_name') &&
        sql.contains('LIMIT ?')) {
      return {
        'columns': [
          'id',
          'queue_source',
          'track_name',
          'artist_name',
          'album_name',
          'file_path',
          'scanned_at',
          'sort_added',
        ],
        'rows': [
          for (var i = 0; i < songs.length; i++)
            [
              'song-$i',
              'local',
              songs[i],
              'Artist',
              'Album',
              '',
              '2026-01-01',
              i,
            ],
        ],
      };
    }
    return {'columns': <String>[], 'rows': <List<Object?>>[]};
  });
  addTearDownSafe(() => messenger.setMockMethodCallHandler(sqlite, null));
}

/// Pumps [LibrarySectionTab] for [section] with the given collections.
Future<void> pumpLibrarySection(
  WidgetTester tester, {
  required String section,
  LibraryCollectionsState? collections,
  Brightness brightness = Brightness.dark,
}) async {
  tester.view.physicalSize = const Size(800, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDownSafe(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        settingsProvider.overrideWith(LibrarySectionSettings.new),
        localLibraryProvider.overrideWith(LibrarySectionLocal.new),
        libraryCollectionsProvider.overrideWith(
          () => LibrarySectionCollections(collections),
        ),
      ],
      child: MaterialApp(
        theme: AppTheme.build(brightness),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: LibrarySectionTab(librarySection: section)),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Registers [action] to run after the test. The harness is shared by several
/// test files, so this keeps the teardown in one place.
void addTearDownSafe(void Function() action) {
  TestWidgetsFlutterBinding.ensureInitialized();
  addTearDown(action);
}
