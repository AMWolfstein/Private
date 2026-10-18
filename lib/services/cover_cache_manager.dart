import 'dart:io';
import 'package:flutter/painting.dart';
import 'package:path_provider/path_provider.dart';

/// Allows users upgrading from the online app to remove its retired image cache.
class CoverCacheManager {
  static Future<Directory> _directory() async =>
      Directory('${(await getApplicationSupportDirectory()).path}/cover_cache');
  static Future<CacheStats> getStats() async {
    final directory = await _directory();
    var count = 0;
    var bytes = 0;
    if (await directory.exists()) {
      await for (final entry in directory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entry is File) {
          count++;
          bytes += await entry.length();
        }
      }
    }
    return CacheStats(fileCount: count, totalSizeBytes: bytes);
  }

  static Future<void> clearCache() async {
    final directory = await _directory();
    if (await directory.exists()) await directory.delete(recursive: true);
    final cache = PaintingBinding.instance.imageCache;
    cache.clear();
    cache.clearLiveImages();
  }
}

class CacheStats {
  final int fileCount;
  final int totalSizeBytes;
  const CacheStats({required this.fileCount, required this.totalSizeBytes});
}
