import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/platform/retired_appearance_cleanup.dart';

void main() {
  test(
    'retired font cleanup preserves unrelated app files and is idempotent',
    () async {
      final support = await Directory.systemTemp.createTemp('retired-fonts-');
      addTearDown(() => support.delete(recursive: true));
      final cache = await Directory('${support.path}/custom_fonts').create();
      await File('${cache.path}/old.font').writeAsString('old font');
      final library = await File(
        '${support.path}/library.db',
      ).writeAsString('music');
      await deleteRetiredFontCacheBestEffort(
        supportDirectory: () async => support,
      );
      await deleteRetiredFontCacheBestEffort(
        supportDirectory: () async => support,
      );
      expect(await cache.exists(), isFalse);
      expect(await library.readAsString(), 'music');
    },
  );

  test('cleanup failure does not block appearance migration', () async {
    await deleteRetiredFontCacheBestEffort(
      supportDirectory: () async => throw StateError('storage unavailable'),
    );
  });
}
