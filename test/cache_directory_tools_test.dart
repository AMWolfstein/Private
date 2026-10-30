import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/screens/settings/cache_directory_tools.dart';

void main() {
  late Directory root;

  setUp(() => root = Directory.systemTemp.createTempSync('cache-tools-'));
  tearDown(() => root.deleteSync(recursive: true));

  test('a missing cache folder has no files', () async {
    final stats = await scanCacheDirectory(Directory('${root.path}/missing'));
    expect(stats.fileCount, 0);
    expect(stats.totalSizeBytes, 0);
  });

  test('the scan counts nested files and sums their sizes', () async {
    File('${root.path}/a.bin').writeAsBytesSync(Uint8List(10));
    Directory('${root.path}/sub').createSync();
    File('${root.path}/sub/b.bin').writeAsBytesSync(Uint8List(25));
    final stats = await scanCacheDirectory(root);
    expect(stats.fileCount, 2);
    expect(stats.totalSizeBytes, 35);
  });

  test('clearing removes every entry and leaves the folder in place', () async {
    File('${root.path}/a.bin').writeAsBytesSync([1]);
    Directory('${root.path}/sub').createSync();
    File('${root.path}/sub/b.bin').writeAsBytesSync([2]);
    await clearCacheDirectoryContents(root.path);
    expect(root.existsSync(), isTrue);
    expect(root.listSync(), isEmpty);
  });

  test('clearing a missing folder does nothing and reports no error', () async {
    final path = '${root.path}/missing';
    await clearCacheDirectoryContents(path);
    expect(Directory(path).existsSync(), isFalse);
  });
}
