import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/backup_service.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'backup-collections-json-',
    );
  });
  tearDown(() => directory.delete(recursive: true));

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
      for (final version in [3]) {
        final metadata = <String, dynamic>{
          'magic': BackupService.magic,
          'format_version': version,
          'app': 'Sistrum',
          'app_version': '5.1.0',
          'created_at': '2026-10-07T00:00:00.000Z',
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
          settings: const {'theme': 'sistrum'},
          collections: const {},
          collectionsJson: jsonEncode(collections),
          playlistCoverFiles: const {},
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
        expect(metadata['magic'], 'sistrum-backup');
        expect(
          archiveFile.uri.pathSegments.last,
          startsWith('sistrum_mobile_backup_'),
        );
        final data = metadata['data'] as Map<String, dynamic>;
        expect(data.keys, ['settings', 'collections']);
        expect(data['collections'], collections);
        final bundle = await BackupService.parseFile(
          archiveFile.path,
          temporaryDirectory: directory,
        );
        expect(bundle, isNotNull);
        expect(bundle.hasCollections, isTrue);
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
        outputDirectory: directory,
        temporaryDirectory: directory,
      ),
      throwsA(isA<BackupTooLargeException>()),
    );
    expect(await directory.list().toList(), isEmpty);
  });

  test('collections above 8 MiB still round trip', () async {
    final collections = {'padding': 'x' * ((8 << 20) + 1024)};
    final archiveFile = await BackupService.writeBackupArchive(
      settings: null,
      collections: const {},
      collectionsJson: jsonEncode(collections),
      playlistCoverFiles: const {},
      outputDirectory: directory,
      temporaryDirectory: directory,
    );
    final bundle = await BackupService.parseFile(
      archiveFile.path,
      temporaryDirectory: directory,
    );
    expect(bundle, isNotNull);
    expect(bundle.collections, collections);
    await bundle.cleanup();
  });

  test('map and encoded collections are mutually exclusive', () async {
    await expectLater(
      BackupService.writeBackupArchive(
        settings: null,
        collections: {'loved': <dynamic>[]},
        collectionsJson: '{}',
        playlistCoverFiles: const {},
        outputDirectory: directory,
        temporaryDirectory: directory,
      ),
      throwsArgumentError,
    );
    expect(await directory.list().toList(), isEmpty);
  });
}
