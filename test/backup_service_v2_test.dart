import 'dart:io';
import 'dart:convert';

import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/services/backup_service.dart';

class _UnreadableArchiveFile extends ArchiveFile {
  _UnreadableArchiveFile(this.failure) : super('covers/cover.bin', 0, <int>[]);

  final FormatException failure;

  @override
  void writeContent(OutputStream output, {bool freeMemory = true}) {
    output.writeBytes([1, 2, 3]);
    throw failure;
  }
}

void main() {
  test('archive output closes when reading its payload throws', () async {
    final root = await Directory.systemTemp.createTemp('unreadable-backup-');
    addTearDown(() => root.delete(recursive: true));
    final path = p.join(root.path, 'cover.bin');
    final output = OutputFileStream(path);
    const failure = FormatException('Invalid compressed archive payload');

    expect(
      () => BackupService.writeArchiveEntry(
        _UnreadableArchiveFile(failure),
        output,
      ),
      throwsA(same(failure)),
    );

    expect(output.isOpen, isFalse);
    expect(await File(path).readAsBytes(), [1, 2, 3]);
  });

  test('ZIP backup streams cover files during restore', () async {
    final root = await Directory.systemTemp.createTemp('sistrum-backup-test-');
    addTearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });
    final output = await Directory(p.join(root.path, 'output')).create();
    final temporary = await Directory(p.join(root.path, 'temporary')).create();
    final cover = File(p.join(root.path, 'cover.jpg'));
    await cover.writeAsBytes([0xff, 0xd8, 0xff, 0xd9]);

    final file = await BackupService.writeBackupArchive(
      settings: const {'theme': 'dark'},
      collections: const {'loved': <dynamic>[], 'playlists': <dynamic>[]},
      playlistCoverFiles: {
        'playlist-1': {'ext': '.jpg', 'path': cover.path},
      },
      outputDirectory: output,
      temporaryDirectory: temporary,
    );

    expect(file.path, endsWith('.${BackupService.fileExtension}'));
    final bundle = await BackupService.parseFile(
      file.path,
      temporaryDirectory: temporary,
    );
    expect(bundle, isNotNull);
    expect(bundle!.formatVersion, 3);
    final restoredCover = bundle.playlistCovers['playlist-1'];
    expect(restoredCover, isA<Map<String, dynamic>>());
    final restoredCoverPath =
        (restoredCover as Map<String, dynamic>)['path'] as String;
    expect(await File(restoredCoverPath).readAsBytes(), [
      0xff,
      0xd8,
      0xff,
      0xd9,
    ]);

    await bundle.cleanup();
    expect(await File(restoredCoverPath).exists(), isFalse);
  });

  test('older or foreign backup envelopes are rejected', () async {
    final root = await Directory.systemTemp.createTemp('old-backup-');
    addTearDown(() => root.delete(recursive: true));
    for (final (magic, version) in [
      (BackupService.magic, 2),
      ('other-backup', BackupService.formatVersion),
    ]) {
      final metadata = utf8.encode(
        jsonEncode({
          'magic': magic,
          'format_version': version,
          'data': <String, dynamic>{},
        }),
      );
      final archive = Archive()
        ..addFile(ArchiveFile('metadata.json', metadata.length, metadata));
      final file = File(p.join(root.path, 'old.sbk'));
      await file.writeAsBytes(ZipEncoder().encode(archive));
      expect(
        await BackupService.parseFile(file.path, temporaryDirectory: root),
        isNull,
      );
    }
  });

  test('profile archive rejects foreign paths and missing photos', () async {
    final root = await Directory.systemTemp.createTemp('profile-backup-');
    addTearDown(() => root.delete(recursive: true));
    for (final photo in ['../avatar.png', 'profile/avatar.png']) {
      final metadata = utf8.encode(
        jsonEncode({
          'magic': BackupService.magic,
          'format_version': BackupService.formatVersion,
          'data': {
            'profile': {'name': 'Listener', 'photo': photo},
          },
        }),
      );
      final archive = Archive()
        ..addFile(ArchiveFile('metadata.json', metadata.length, metadata));
      final file = File(p.join(root.path, 'invalid.sbk'));
      await file.writeAsBytes(ZipEncoder().encode(archive));
      expect(
        await BackupService.parseFile(file.path, temporaryDirectory: root),
        isNull,
      );
      expect(
        await root.list().where((entry) => entry is Directory).isEmpty,
        isTrue,
      );
    }
  });
}
