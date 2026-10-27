import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/services/backup_service.dart';
import 'package:spotiflac_android/services/history_database.dart';

class _AtomicHistory implements HistoryDatabase {
  List<Map<String, dynamic>> rows = [
    {'id': 'old'},
  ];
  @override
  Future<void> replaceAll(Stream<Map<String, dynamic>> items) async {
    final prepared = await items.toList();
    rows = prepared;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('non-atomic method called: ${invocation.memberName}');
}

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'backup-collections-json-',
    );
  });
  tearDown(() => directory.delete(recursive: true));

  test('fallback history restore delegates one atomic replacement', () async {
    final history = _AtomicHistory();
    final bundle = BackupBundle(
      formatVersion: 1,
      appVersion: 'old',
      createdAt: null,
      settings: null,
      history: [
        {'id': 'new'},
      ],
      collections: const {},
      playlistCovers: const {},
      extensions: const {},
    );
    await BackupService.restoreHistory(bundle, historyDatabase: history);
    expect(history.rows, [
      {'id': 'new'},
    ]);
    final corrupt = File('${directory.path}/history.ndjson');
    await corrupt.writeAsString('{"id":"partial"}\ninvalid JSON');
    final broken = BackupBundle(
      formatVersion: 2,
      appVersion: 'old',
      createdAt: null,
      settings: null,
      history: const [],
      collections: const {},
      playlistCovers: const {},
      extensions: const {},
      historyNdjsonPath: corrupt.path,
    );
    await expectLater(
      BackupService.restoreHistory(broken, historyDatabase: history),
      throwsFormatException,
    );
    expect(history.rows, [
      {'id': 'new'},
    ]);
  });

  for (final producer in ['SpotiFLAC Mobile', 'Sistrum']) {
    for (final version in [1, 2]) {
      test('$producer v$version backup still restores history', () async {
        final metadata = {
          'magic': 'spotiflac-backup',
          'format_version': version,
          'app': producer,
          'app_version': '5.1.0',
          'history_count': 1,
          'data': {
            'settings': {'theme': 'dark', 'locale': 'id'},
            'collections': {
              'loved': [
                {'key': 'local:legacy-song'},
              ],
            },
            if (version == 1)
              'history': [
                {'id': 'legacy-song', 'title': 'Still here'},
              ],
          },
        };
        final path =
            '${directory.path}/spotiflac_mobile_backup_old.'
            '${version == 1 ? 'json' : 'sflb'}';
        if (version == 1) {
          await File(path).writeAsString(jsonEncode(metadata));
        } else {
          final metadataBytes = utf8.encode(jsonEncode(metadata));
          final historyBytes = utf8.encode(
            '${jsonEncode({'id': 'legacy-song', 'title': 'Still here'})}\n',
          );
          final archive = Archive()
            ..addFile(
              ArchiveFile('metadata.json', metadataBytes.length, metadataBytes),
            )
            ..addFile(
              ArchiveFile('history.ndjson', historyBytes.length, historyBytes),
            );
          await File(path).writeAsBytes(ZipEncoder().encode(archive));
        }

        final bundle = await BackupService.parseFile(
          path,
          temporaryDirectory: directory,
        );
        expect(bundle, isNotNull);
        addTearDown(bundle!.cleanup);
        expect(bundle.settings, {'theme': 'dark', 'locale': 'id'});
        expect(bundle.likedCount, 1);
        expect(bundle.collections['loved'], [
          {'key': 'local:legacy-song'},
        ]);
        final history = _AtomicHistory();
        await BackupService.restoreHistory(bundle, historyDatabase: history);
        expect(history.rows, [
          {'id': 'legacy-song', 'title': 'Still here'},
        ]);
      });
    }
  }

  test('legacy JSON cannot select a local cover source path', () {
    final bundle = BackupService.parse(
      jsonEncode({
        'magic': BackupService.magic,
        'data': {
          'playlist_covers': {
            'unsafe': {'path': '/dev/zero', 'ext': '.jpg'},
            'embedded': {
              'data': 'Y292ZXI=',
              'path': '/private/avatar.png',
              'ext': '.jpg',
            },
          },
        },
      }),
    );
    expect(bundle!.playlistCovers['unsafe'], {'ext': '.jpg'});
    expect(bundle.playlistCovers['embedded'], {
      'data': 'Y292ZXI=',
      'ext': '.jpg',
    });
  });

  test(
    'direct collections JSON keeps exact metadata bytes for v2 and v3',
    () async {
      final collections = <String, dynamic>{
        'loved': [
          {
            'key': 'example:track',
            'track': {
              'name': '日本語 "quoted" \\ slash\nline',
              'comment': null,
              'unknown': {
                'array': [null, true, -0.0, 1.25],
              },
            },
          },
        ],
        'playlists': [
          {
            'id': 'playlist',
            'name': 'Emoji 🎵',
            'coverImagePath': null,
            'tracks': <dynamic>[],
          },
        ],
        'favoriteArtists': <dynamic>[],
        'unknown"key': {'collections': '__raw_collections__', 'nested': null},
      };
      for (final version in [2, 3]) {
        final metadata = <String, dynamic>{
          'magic': BackupService.magic,
          'format_version': version,
          'app': 'SpotiFLAC Mobile',
          'app_version': '5.1.0',
          'created_at': '2026-10-07T00:00:00.000Z',
          'history_count': 0,
          'unknown_root': {'preserved': true},
          'data': <String, dynamic>{
            'settings': {
              'quote': '"',
              'slash': '\\',
              'line': '\n',
              'nil': null,
            },
            'profile': {'name': '日本語 🎵'},
            'collections': collections,
            'playlist_covers': <String, dynamic>{},
            'extensions': {'items': <dynamic>[], 'nil': null},
            'unknown_data': {'preserved': true},
          },
        };
        final path = '${directory.path}/metadata-$version.json';
        final original = jsonEncode(metadata);
        await BackupService.writeBackupMetadata(path, metadata);
        expect(await File(path).readAsBytes(), utf8.encode(original));
        final placeholder = Map<String, dynamic>.of(metadata)
          ..['data'] = (Map<String, dynamic>.of(
            metadata['data'] as Map<String, dynamic>,
          )..['collections'] = <String, dynamic>{});
        await BackupService.writeBackupMetadata(
          path,
          placeholder,
          collectionsJson: jsonEncode(collections),
        );
        expect(await File(path).readAsBytes(), utf8.encode(original));
        final parsed = BackupService.parse(await File(path).readAsString());
        expect(parsed, isNotNull);
        expect(parsed!.formatVersion, version);
        expect(parsed.collections, collections);
      }
    },
  );

  test(
    'direct JSON archive round trips and retains category presence',
    () async {
      for (final collections in <Map<String, dynamic>>[
        {'playlists': <dynamic>[], 'favoriteArtists': <dynamic>[]},
        {
          'loved': [
            {'opaque': '日本語 🎵 \\ "\n', 'nil': null},
          ],
          'future': {'value': true},
        },
      ]) {
        final archiveFile = await BackupService.writeBackupArchive(
          settings: const {'theme': 'mornye'},
          collections: const {},
          collectionsJson: jsonEncode(collections),
          playlistCoverFiles: const {},
          extensions: const {},
          loadHistoryPage: (_, _) async => [],
          includeHistory: false,
          outputDirectory: directory,
          temporaryDirectory: directory,
        );
        final archive = ZipDecoder().decodeBytes(
          await archiveFile.readAsBytes(),
        );
        final metadata =
            jsonDecode(utf8.decode(archive.find('metadata.json')!.content))
                as Map<String, dynamic>;
        expect(metadata['app'], 'Sistrum');
        expect(metadata['magic'], 'spotiflac-backup');
        expect(
          archiveFile.uri.pathSegments.last,
          startsWith('spotiflac_mobile_backup_'),
        );
        final data = metadata['data'] as Map<String, dynamic>;
        expect(data.keys, ['settings', 'collections']);
        expect(data['collections'], collections);
        final bundle = await BackupService.parseFile(
          archiveFile.path,
          temporaryDirectory: directory,
        );
        expect(bundle, isNotNull);
        expect(bundle!.hasCollections, isTrue);
        expect(bundle.collections, collections);
        await bundle.cleanup();
      }
    },
  );

  test('oversized metadata cannot publish an unrestorable archive', () async {
    await expectLater(
      BackupService.writeBackupArchive(
        settings: null,
        collections: const {},
        collectionsJson: jsonEncode({'padding': 'x' * (32 << 20)}),
        playlistCoverFiles: const {},
        extensions: const {},
        loadHistoryPage: (_, _) async => [],
        includeHistory: false,
        outputDirectory: directory,
        temporaryDirectory: directory,
      ),
      throwsA(isA<BackupTooLargeException>()),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('collections above the former 8 MiB cap still round trip', () async {
    final collections = {'padding': 'x' * ((8 << 20) + 1024)};
    final archiveFile = await BackupService.writeBackupArchive(
      settings: null,
      collections: const {},
      collectionsJson: jsonEncode(collections),
      playlistCoverFiles: const {},
      extensions: const {},
      loadHistoryPage: (_, _) async => [],
      includeHistory: false,
      outputDirectory: directory,
      temporaryDirectory: directory,
    );
    final bundle = await BackupService.parseFile(
      archiveFile.path,
      temporaryDirectory: directory,
    );
    expect(bundle, isNotNull);
    expect(bundle!.collections, collections);
    await bundle.cleanup();
  });

  test('map and encoded collections are mutually exclusive', () async {
    await expectLater(
      BackupService.writeBackupArchive(
        settings: null,
        collections: {'loved': <dynamic>[]},
        collectionsJson: '{}',
        playlistCoverFiles: const {},
        extensions: const {},
        loadHistoryPage: (_, _) async => [],
        includeHistory: false,
        outputDirectory: directory,
        temporaryDirectory: directory,
      ),
      throwsArgumentError,
    );
    expect(await directory.list().toList(), isEmpty);
  });
}
