import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:sistrum/utils/logging/logger.dart';

/// Deletes only the app-owned cache of formerly imported fonts. Failure must
/// never prevent loading theme settings or make the old font active again.
Future<void> deleteRetiredFontCacheBestEffort({
  Future<Directory> Function()? supportDirectory,
}) async {
  try {
    final support =
        await (supportDirectory ?? getApplicationSupportDirectory)();
    final cache = Directory('${support.path}/custom_fonts');
    // Do not follow a link in place of the cache directory.
    if (await FileSystemEntity.type(cache.path, followLinks: false) ==
        FileSystemEntityType.directory) {
      await cache.delete(recursive: true);
    }
  } catch (error) {
    AppLogger('AppearanceMigration').w('Retired font cache cleanup: $error');
  }
}
