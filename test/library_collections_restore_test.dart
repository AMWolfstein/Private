import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/services/library/collections/library_collections_playlist_covers.dart';
import 'package:sistrum/services/library/collections/library_collections_restore.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;

  setUp(() {
    support = Directory.systemTemp.createTempSync('restore-support-');
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => support.path);
  });

  tearDown(() => support.deleteSync(recursive: true));

  PlaylistCoverFiles covers() => PlaylistCoverFiles(
    probeCover: (_) async => (width: 300, height: 300),
    resizeCover:
        ({
          required inputPath,
          required outputPath,
          required maxDimension,
        }) async {
          await File(outputPath).writeAsBytes(Uint8List(16));
        },
  );

  test(
    'a backup cover is written locally and the device path is replaced',
    () async {
      final prepared = <String>[];
      final normalized = <String, dynamic>{
        'playlists': [
          {'id': 'p1', 'name': 'One', 'coverImagePath': '/old/device.jpg'},
        ],
      };
      final coversDir = Directory(p.join(support.path, 'playlist_covers'))
        ..createSync(recursive: true);

      await rewriteBackupPlaylistCovers(
        normalized: normalized,
        coverImages: {
          'p1': {
            'data': base64Encode([1, 2, 3, 4]),
            'ext': '.png',
          },
        },
        coversDir: coversDir,
        covers: covers(),
        prepared: prepared,
      );

      final playlist = (normalized['playlists'] as List).single as Map;
      expect(prepared, hasLength(1));
      expect(playlist['coverImagePath'], prepared.single);
      expect(playlist['coverImagePath'], isNot('/old/device.jpg'));
      expect(File(prepared.single).existsSync(), isTrue);
    },
  );

  test(
    'a playlist without a restorable cover loses its stale device path',
    () async {
      final prepared = <String>[];
      final normalized = <String, dynamic>{
        'playlists': [
          {'id': 'p2', 'name': 'Two', 'coverImagePath': '/old/gone.jpg'},
        ],
      };
      await rewriteBackupPlaylistCovers(
        normalized: normalized,
        coverImages: const {},
        coversDir: Directory(p.join(support.path, 'playlist_covers')),
        covers: covers(),
        prepared: prepared,
      );
      final playlist = (normalized['playlists'] as List).single as Map;
      expect(playlist.containsKey('coverImagePath'), isFalse);
      expect(prepared, isEmpty);
    },
  );
}
