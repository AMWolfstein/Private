import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/utils/files/best_effort_delete.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('best_effort_delete_test');
  });

  tearDown(() {
    if (root.existsSync()) root.deleteSync(recursive: true);
  });

  test('deletes an existing file', () async {
    final file = File('${root.path}/cache.bin')..writeAsStringSync('x');

    await deleteBestEffort(file);

    expect(file.existsSync(), isFalse);
  });

  test('deletes an empty directory without recursion', () async {
    final dir = Directory('${root.path}/empty')..createSync();

    await deleteBestEffort(dir);

    expect(dir.existsSync(), isFalse);
  });

  test('removes a non-empty directory only when recursive', () async {
    final dir = Directory('${root.path}/tree')..createSync();
    final child = File('${dir.path}/child.txt')..writeAsStringSync('x');

    await deleteBestEffort(dir);
    // A non-recursive delete of a populated directory fails, and is ignored.
    expect(dir.existsSync(), isTrue);
    expect(child.existsSync(), isTrue);

    await deleteBestEffort(dir, recursive: true);
    expect(dir.existsSync(), isFalse);
  });

  test('does nothing and never throws for a missing entity', () async {
    final missingFile = File('${root.path}/missing.bin');
    final missingDir = Directory('${root.path}/missing-dir');

    await expectLater(deleteBestEffort(missingFile), completes);
    await expectLater(deleteBestEffort(missingDir, recursive: true), completes);
    expect(root.existsSync(), isTrue);
  });
}
