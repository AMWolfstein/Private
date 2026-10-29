import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/library/library_section_tab.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'support/material_test_theme.dart';
import 'package:sistrum/theme/sistrum_theme.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

class _Local extends LocalLibraryNotifier {
  @override
  LocalLibraryState build() => LocalLibraryState();

  void publishIndexChange() {
    state = state.copyWith(loadedIndexVersion: state.loadedIndexVersion + 1);
  }

  @override
  Future<void> reloadFromStorage() async {}
}

class _SelectionCollections extends LibraryCollectionsNotifier {
  _SelectionCollections(this._record, {bool withTracks = false})
    : _withTracks = withTracks;
  final void Function(List<String>) _record;
  final bool _withTracks;

  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    playlists: [
      for (final id in ['First', 'Second', 'Keep'])
        UserPlaylistCollection(
          id: id,
          name: id,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          tracks: _withTracks
              ? [
                  for (var i = 0; i < (id == 'Second' ? 2 : 1); i++)
                    CollectionTrackEntry(
                      key: '$id-$i',
                      addedAt: DateTime.utc(2026),
                      track: Track(
                        id: '$id-$i',
                        name: '$id-$i',
                        artistName: 'Artist',
                        albumName: 'Album',
                        duration: 180,
                      ),
                    ),
                ]
              : const [],
        ),
    ],
  );

  @override
  Future<int> deletePlaylists(Iterable<String> ids) async {
    final selected = ids.toSet();
    _record(selected.toList());
    state = state.copyWith(
      playlists: state.playlists
          .where((p) => !selected.contains(p.id))
          .toList(),
    );
    return selected.length;
  }
}

class _SongsCollections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() {
    final entry = CollectionTrackEntry(
      key: 'local:song',
      track: const Track(
        id: 'song',
        source: 'local',
        name: 'Song in playlist',
        artistName: 'Artist',
        albumName: 'Album',
        duration: 180,
      ),
      addedAt: DateTime.utc(2026),
    );
    return LibraryCollectionsState(
      isLoaded: true,
      loved: [entry],
      playlists: [
        UserPlaylistCollection(
          id: 'mix',
          name: 'My hidden playlist',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          tracks: [entry],
        ),
      ],
      favoriteArtists: [
        CollectionArtistEntry(
          key: 'artist',
          artistId: 'artist',
          providerId: null,
          name: 'Favorite artist',
          addedAt: DateTime.utc(2026),
        ),
      ],
    );
  }
}

class _EditableCollections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(
    isLoaded: true,
    playlists: [
      for (final (index, name) in ['One', 'Two'].indexed)
        UserPlaylistCollection(
          id: name.toLowerCase(),
          name: name,
          createdAt: DateTime.utc(2026, 1, index + 1),
          updatedAt: DateTime.utc(2026, 1, index + 1),
          tracks: const [],
        ),
    ],
  );

  void rename(String id, String name) {
    state = state.copyWith(
      playlists: [
        for (final playlist in state.playlists)
          playlist.id == id ? playlist.copyWith(name: name) : playlist,
      ],
    );
  }
}

class _EmptyCollections extends LibraryCollectionsNotifier {
  @override
  LibraryCollectionsState build() => LibraryCollectionsState(isLoaded: true);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Local local;
  var returnSong = false;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    local = _Local();
    returnSong = false;
    final previousFactory = databaseFactoryOrNull;
    databaseFactory = databaseFactorySqflitePlugin;
    addTearDown(() => databaseFactory = previousFactory);
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    messenger.setMockMethodCallHandler(paths, (_) async => '/test/documents');
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
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
      if (returnSong && sql.contains('SUM(all_count)')) {
        return {
          'columns': ['all_count', 'single_count', 'album_count'],
          'rows': [
            [1, 1, 0],
          ],
        };
      }
      if (returnSong &&
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
            [
              'song',
              'local',
              'Song in playlist',
              'Artist',
              'Album',
              '',
              '2026-01-01',
              0,
            ],
          ],
        };
      }
      return {'columns': <String>[], 'rows': <List<Object?>>[]};
    });
    addTearDown(() => messenger.setMockMethodCallHandler(sqlite, null));
  });

  for (final sistrum in [true]) {
    testWidgets(
      'playlist selection confirms one deletion (Sistrum: $sistrum)',
      (tester) async {
        tester.view.physicalSize = const Size(800, 1200);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final calls = <List<String>>[];
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              settingsProvider.overrideWith(_Settings.new),
              localLibraryProvider.overrideWith(() => local),
              libraryCollectionsProvider.overrideWith(
                () => _SelectionCollections(calls.add),
              ),
            ],
            child: MaterialApp(
              theme: sistrum
                  ? SistrumTheme.build(Brightness.dark)
                  : AppTheme.light(),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
              home: const Scaffold(
                body: LibrarySectionTab(librarySection: 'playlists'),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final l10n = AppLocalizations.of(
          tester.element(find.byType(LibrarySectionTab)),
        );
        await tester.ensureVisible(find.text('First'));
        await tester.longPress(find.text('First'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Second'));
        await tester.tap(find.text('Second'));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.selectionDeletePlaylistsCount(2)));
        await tester.pumpAndSettle();
        expect(
          find.text(l10n.collectionDeletePlaylistsMessage(2)),
          findsOneWidget,
        );
        await tester.tap(find.text(l10n.dialogCancel));
        await tester.pumpAndSettle();
        expect(calls, isEmpty);
        expect(find.text('First'), findsOneWidget);
        await tester.tap(find.text(l10n.selectionDeletePlaylistsCount(2)));
        await tester.pumpAndSettle();
        await tester.tap(find.text(l10n.dialogDelete));
        await tester.pumpAndSettle();
        expect(calls, [
          ['First', 'Second'],
        ]);
        expect(find.text('First'), findsNothing);
        expect(find.text('Second'), findsNothing);
        expect(find.text('Keep'), findsOneWidget);
        expect(find.text(l10n.selectionDeletePlaylistsCount(2)), findsNothing);
        expect(find.text(l10n.collectionPlaylistsDeleted(2)), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets('playlist rows show renames without changing the count', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final collections = _EditableCollections();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(() => local),
          libraryCollectionsProvider.overrideWith(() => collections),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: LibrarySectionTab(librarySection: 'playlists'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // Library sections use rows, not the old album-style grid.
    expect(find.byKey(const ValueKey('plrow_one')), findsOneWidget);
    expect(find.text('One'), findsOneWidget);
    expect(find.byType(SliverGrid), findsNothing);

    // Renaming keeps the playlist count, so only a watched playlists list
    // makes the row update.
    collections.rename('one', 'Renamed');
    await tester.pumpAndSettle();
    expect(find.text('Renamed'), findsOneWidget);
    expect(find.text('One'), findsNothing);
    expect(find.text('Two'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty Playlists section offers creating one', (tester) async {
    tester.view.physicalSize = const Size(800, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(() => local),
          libraryCollectionsProvider.overrideWith(_EmptyCollections.new),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(
            body: LibrarySectionTab(librarySection: 'playlists'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Create playlist'), findsOneWidget);
    await tester.tap(find.text('Create playlist'));
    await tester.pumpAndSettle();
    expect(find.byType(AppAlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Songs contains playlist-member songs without collection rows', (
    tester,
  ) async {
    returnSong = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(() => local),
          libraryCollectionsProvider.overrideWith(_SongsCollections.new),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const Scaffold(body: LibrarySectionTab(librarySection: 'all')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Song in playlist'), findsOneWidget);
    expect(find.text('Loved Songs'), findsNothing);
    expect(find.text('Favorite Artists'), findsNothing);
    expect(find.text('My hidden playlist'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Songs header wraps each action at 360dp and 2x text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    returnSong = true;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(_Settings.new),
          localLibraryProvider.overrideWith(() => local),
          libraryCollectionsProvider.overrideWith(_SongsCollections.new),
        ],
        child: MaterialApp(
          theme: SistrumTheme.build(Brightness.dark),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: const Scaffold(body: LibrarySectionTab(librarySection: 'all')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final l10n = AppLocalizations.of(
      tester.element(find.byType(LibrarySectionTab)),
    );
    final create = find.widgetWithText(
      TextButton,
      l10n.collectionCreatePlaylist,
    );
    expect(create, findsOneWidget);
    final rect = tester.getRect(create);
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(360));
    expect(rect.height, greaterThanOrEqualTo(48));
    expect(tester.takeException(), isNull);
  });
}
