import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/services/library/collections/library_collections_playlist_covers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory support;
  late List<int> resizedDimensions;

  setUp(() {
    support = Directory.systemTemp.createTempSync('playlist-covers-');
    resizedDimensions = [];
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(paths, (_) async => support.path);
  });

  tearDown(() => support.deleteSync(recursive: true));

  /// Writes bytes proportional to the dimension, so a large cover must shrink.
  PlaylistCoverFiles covers({
    ({int width, int height})? probed = (width: 2000, height: 1000),
    int bytesPerDimension = 10,
  }) => PlaylistCoverFiles(
    probeCover: (_) async => probed,
    resizeCover:
        ({
          required inputPath,
          required outputPath,
          required maxDimension,
        }) async {
          resizedDimensions.add(maxDimension);
          await File(
            outputPath,
          ).writeAsBytes(Uint8List(maxDimension * bytesPerDimension));
        },
  );

  test('a cover is normalized into the playlist covers folder', () async {
    final source = File(p.join(support.path, 'source.png'))
      ..writeAsBytesSync([1, 2, 3]);
    final stored = await covers().normalizePlaylistCoverFile(source.path);

    expect(p.isWithin(p.join(support.path, 'playlist_covers'), stored), isTrue);
    expect(p.basename(stored), 'image.jpg');
    expect(File(stored).existsSync(), isTrue);
  });

  test('the longest edge of the source sets the target dimension', () async {
    final source = File(p.join(support.path, 'wide.png'))
      ..writeAsBytesSync([1]);
    await covers(
      probed: (width: 2000, height: 1000),
    ).normalizePlaylistCoverFile(source.path);
    expect(resizedDimensions, [1024]);
  });

  test('a small source keeps its own size instead of being upscaled', () async {
    final source = File(p.join(support.path, 'small.png'))
      ..writeAsBytesSync([1]);
    await covers(
      probed: (width: 200, height: 100),
    ).normalizePlaylistCoverFile(source.path);
    expect(resizedDimensions, [200]);
  });

  test('an unreadable size falls back to the maximum dimension', () async {
    final source = File(p.join(support.path, 'unknown.png'))
      ..writeAsBytesSync([1]);
    await covers(probed: null).normalizePlaylistCoverFile(source.path);
    expect(resizedDimensions, [1024]);
  });

  test('an oversized cover is shrunk until it fits the stored limit', () async {
    final source = File(p.join(support.path, 'huge.png'))
      ..writeAsBytesSync([1]);
    // 1024 * 3000 bytes is over the 2 MB limit; 768 * 3000 still is not, but
    // 576 * 3000 fits.
    final stored = await covers(
      bytesPerDimension: 3000,
    ).normalizePlaylistCoverFile(source.path);
    expect(resizedDimensions.last, lessThan(1024));
    expect(resizedDimensions.length, greaterThan(1));
    expect(File(stored).lengthSync(), lessThanOrEqualTo(2 * 1024 * 1024));
  });

  test('a JPEG within the limits needs no normalization', () async {
    final stored = File(p.join(support.path, 'ok.jpg'))
      ..writeAsBytesSync([1, 2]);
    expect(
      await covers(
        probed: (width: 500, height: 500),
      ).playlistCoverNeedsNormalization(stored.path),
      isFalse,
    );
  });

  test('a PNG or an oversized JPEG needs normalization', () async {
    final png = File(p.join(support.path, 'cover.png'))..writeAsBytesSync([1]);
    expect(await covers().playlistCoverNeedsNormalization(png.path), isTrue);

    final big = File(p.join(support.path, 'big.jpg'))
      ..writeAsBytesSync(Uint8List(2 * 1024 * 1024 + 1));
    expect(await covers().playlistCoverNeedsNormalization(big.path), isTrue);
  });

  test('a missing cover file needs no normalization', () async {
    expect(
      await covers().playlistCoverNeedsNormalization(
        p.join(support.path, 'missing.jpg'),
      ),
      isFalse,
    );
  });

  test(
    'deleting a private cover removes it and its empty version folder',
    () async {
      final dir = Directory(p.join(support.path, 'playlist_covers', 'cover-1'))
        ..createSync(recursive: true);
      final file = File(p.join(dir.path, 'image.jpg'))..writeAsBytesSync([1]);
      await covers().deletePrivatePlaylistCover(file.path);
      expect(file.existsSync(), isFalse);
      expect(dir.existsSync(), isFalse);
    },
  );

  test('a file outside the covers folder is never deleted', () async {
    final outside = File(p.join(support.path, 'keep.jpg'))
      ..writeAsBytesSync([1]);
    await covers().deletePrivatePlaylistCover(outside.path);
    expect(outside.existsSync(), isTrue);
  });
}
