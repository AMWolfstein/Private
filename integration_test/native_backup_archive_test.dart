import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:sistrum/services/backup/backup_service.dart';
import 'package:sistrum/services/user_profile_store.dart';

Future<void> _dartWrite(String path, List<Map<String, dynamic>> files) =>
    Isolate.run(() async {
      final encoder = ZipFileEncoder()..create(path);
      try {
        for (final file in files) {
          await encoder.addFile(
            File(file['path'] as String),
            file['name'] as String,
            file['store'] == true ? ZipFileEncoder.store : null,
          );
        }
      } finally {
        await encoder.close();
      }
    });

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('native-backup-archive-');
  });
  tearDown(() => root.delete(recursive: true));

  testWidgets('production backup routes every category through native ZIP', (
    tester,
  ) async {
    final cover = await File(
      '${root.path}/cover.jpg',
    ).writeAsBytes([255, 216, 255, 217]);
    final photo = await File('${root.path}/avatar.png').writeAsBytes([1, 2, 3]);
    for (var mask = 1; mask < 8; mask++) {
      final hasSettings = mask & 1 != 0;
      final hasCollections = mask & 2 != 0;
      final output = await Directory('${root.path}/backup-$mask').create();
      final backup = await BackupService.writeBackupArchive(
        settings: hasSettings ? {'theme': 'sistrum'} : null,
        collections: hasCollections
            ? {
                'playlists': [
                  {'id': 'playlist', 'name': '音楽'},
                ],
              }
            : {},
        playlistCoverFiles: hasCollections
            ? {
                'playlist': {'ext': '.jpg', 'path': cover.path},
              }
            : {},
        profile: UserProfile(name: 'Listener', photoPath: photo.path),
        outputDirectory: output,
        temporaryDirectory: root,
      );
      final bundle = await BackupService.parseFile(
        backup.path,
        temporaryDirectory: root,
      );
      expect(bundle, isNotNull, reason: 'mask $mask');
      expect(bundle.formatVersion, 3);
      expect(bundle.hasSettings, hasSettings);
      expect(bundle.hasCollections, hasCollections);
      expect(bundle.profile!.name, 'Listener');
      expect(await File(bundle.profile!.photoPath!).readAsBytes(), [1, 2, 3]);
      if (hasCollections) {
        final playlists = bundle.collections['playlists'] as List;
        expect((playlists.single as Map)['name'], '音楽');
        final restoredCover = bundle.playlistCovers['playlist'] as Map;
        expect(await File(restoredCover['path'] as String).readAsBytes(), [
          255,
          216,
          255,
          217,
        ]);
      }
      final stagedPhoto = bundle.profile!.photoPath!;
      await bundle.cleanup();
      expect(await File(stagedPhoto).exists(), false);
    }
  });

  testWidgets('Dart v3 archives remain readable by the native parser', (
    tester,
  ) async {
    final metadata = await File('${root.path}/metadata.json').writeAsString(
      jsonEncode({
        'magic': BackupService.magic,
        'format_version': 3,
        'data': {
          'settings': {'theme': 'light'},
        },
      }),
    );
    final path = '${root.path}/dart-3.sbk';
    await _dartWrite(path, [
      {'path': metadata.path, 'name': 'metadata.json', 'store': false},
    ]);
    final bundle = await BackupService.parseFile(
      path,
      temporaryDirectory: root,
    );
    expect(bundle, isNotNull);
    expect(bundle.formatVersion, 3);
    expect(bundle.settings, {'theme': 'light'});
    await bundle.cleanup();
  });

  testWidgets(
    'direct JSON archive round trips and retains category presence',
    (tester) async {
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
          outputDirectory: root,
          temporaryDirectory: root,
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
          temporaryDirectory: root,
        );
        expect(bundle, isNotNull);
        expect(bundle.hasCollections, isTrue);
        expect(bundle.collections, collections);
        await bundle.cleanup();
      }
    },
  );

  testWidgets('collections above 8 MiB still round trip', (tester) async {
    final collections = {'padding': 'x' * ((8 << 20) + 1024)};
    final archiveFile = await BackupService.writeBackupArchive(
      settings: null,
      collections: const {},
      collectionsJson: jsonEncode(collections),
      playlistCoverFiles: const {},
      outputDirectory: root,
      temporaryDirectory: root,
    );
    final bundle = await BackupService.parseFile(
      archiveFile.path,
      temporaryDirectory: root,
    );
    expect(bundle, isNotNull);
    expect(bundle.collections, collections);
    await bundle.cleanup();
  });

  testWidgets('native parser rejects foreign or older envelopes', (
    tester,
  ) async {
    for (final (magic, version) in [
      (BackupService.magic, 2),
      ('other-backup', BackupService.formatVersion),
    ]) {
      final metadata = await File('${root.path}/metadata.json').writeAsString(
        jsonEncode({
          'magic': magic,
          'format_version': version,
          'data': <String, dynamic>{},
        }),
      );
      final path = '${root.path}/rejected-$version.sbk';
      await _dartWrite(path, [
        {'path': metadata.path, 'name': 'metadata.json', 'store': false},
      ]);
      await expectLater(
        BackupService.parseFile(path, temporaryDirectory: root),
        throwsA(isA<BackupParseException>()),
      );
    }
  });

  testWidgets('native parser rejects foreign profile photo paths', (
    tester,
  ) async {
    for (final (index, photo) in [
      '../avatar.png',
      'profile/avatar.png',
    ].indexed) {
      final metadata = await File('${root.path}/metadata.json').writeAsString(
        jsonEncode({
          'magic': BackupService.magic,
          'format_version': BackupService.formatVersion,
          'data': {
            'profile': {'name': 'Listener', 'photo': photo},
          },
        }),
      );
      final path = '${root.path}/profile-$index.sbk';
      await _dartWrite(path, [
        {'path': metadata.path, 'name': 'metadata.json', 'store': false},
      ]);
      await expectLater(
        BackupService.parseFile(path, temporaryDirectory: root),
        throwsA(isA<BackupParseException>()),
      );
    }
  });

  testWidgets(
    'direct collection JSON round trips through production native ZIP',
    (tester) async {
      final cover = await File(
        '${root.path}/raw-cover.jpg',
      ).writeAsBytes([255, 216, 255, 217]);
      final photo = await File(
        '${root.path}/raw-avatar.png',
      ).writeAsBytes([1, 2, 3]);
      for (final collections in <Map<String, dynamic>>[
        {
          'loved': <dynamic>[],
          'playlists': <dynamic>[],
          'favoriteArtists': <dynamic>[],
        },
        {
          'loved': [
            {'opaque': '日本語 🎵 \\ "\n', 'nil': null},
          ],
          'playlists': [
            {'id': 'playlist', 'name': '音楽 "quoted"', 'unknown': null},
          ],
          'future"key': {'collections': '__raw_collections__', 'value': true},
        },
      ]) {
        final archiveFile = await BackupService.writeBackupArchive(
          settings: const {'theme': 'sistrum', 'nil': null},
          collections: const {},
          collectionsJson: jsonEncode(collections),
          playlistCoverFiles: {
            'playlist': {'ext': '.jpg', 'path': cover.path},
          },
          profile: UserProfile(name: '日本語 🎵', photoPath: photo.path),
          outputDirectory: root,
          temporaryDirectory: root,
        );
        final archive = ZipDecoder().decodeBytes(
          await archiveFile.readAsBytes(),
        );
        final metadata =
            jsonDecode(utf8.decode(archive.find('metadata.json')!.content))
                as Map<String, dynamic>;
        final data = metadata['data'] as Map<String, dynamic>;
        expect(data.keys, [
          'settings',
          'profile',
          'collections',
          'playlist_covers',
        ]);
        expect(data['collections'], collections);
        final bundle = await BackupService.parseFile(
          archiveFile.path,
          temporaryDirectory: root,
        );
        expect(bundle, isNotNull);
        expect(bundle.formatVersion, 3);
        expect(bundle.hasCollections, isTrue);
        expect(bundle.collections, collections);
        expect(bundle.profile!.name, '日本語 🎵');
        expect(await File(bundle.profile!.photoPath!).readAsBytes(), [1, 2, 3]);
        final restoredCover = bundle.playlistCovers['playlist'] as Map;
        expect(await File(restoredCover['path'] as String).readAsBytes(), [
          255,
          216,
          255,
          217,
        ]);
        await bundle.cleanup();
      }
    },
  );
}
