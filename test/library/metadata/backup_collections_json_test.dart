import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/backup/backup_service.dart';

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
