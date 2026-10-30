import 'dart:io';
import 'package:sistrum/core/models/playable_media.dart';
import 'package:sistrum/utils/cover/playback_artwork.dart';

/// Resolve a saved queue in bounded groups, retaining its original order even
/// when later file checks finish first. File existence is shared across tracks
/// with the same artwork for this restore only, with a bounded LRU cache.
Future<
  ({
    List<PlayableMedia> items,
    List<int> keptOriginalIndices,
    bool artworkRelocated,
  })
>
prepareRestoredPlaybackMedia(
  List<Object?> rawMedia, {
  required Future<String?> Function(PlayableMedia) loadLibraryCoverPath,
  Future<bool> Function(String)? fileExists,
}) async {
  const batchSize = 8;
  final checks = <String, Future<bool>>{};
  Future<bool> exists(String path) {
    final pending =
        checks.remove(path) ?? (fileExists?.call(path) ?? File(path).exists());
    checks[path] = pending;
    if (checks.length > 256) checks.remove(checks.keys.first);
    return pending;
  }

  Future<(PlayableMedia, int, bool)?> resolve(int index) async {
    final entry = rawMedia[index];
    if (entry is! Map) return null;
    final media = PlayableMedia.fromJson(Map<String, dynamic>.from(entry));
    if (media == null) return null;
    if (!media.isContentUri && !await exists(media.source)) {
      return null;
    }
    final artwork = await resolveRestoredArtworkUri(
      media.artUri,
      fileExists: exists,
      loadLibraryCoverPath: () => loadLibraryCoverPath(media),
    );
    return (
      artwork == media.artUri
          ? media
          : PlayableMedia.fromJson({...media.toJson(), 'artUri': artwork})!,
      index,
      artwork != entry['artUri'],
    );
  }

  final items = <PlayableMedia>[];
  final keptOriginalIndices = <int>[];
  var artworkRelocated = false;
  for (var start = 0; start < rawMedia.length; start += batchSize) {
    final end = (start + batchSize).clamp(0, rawMedia.length);
    final batch = await Future.wait([
      for (var index = start; index < end; index++) resolve(index),
    ]);
    for (final result in batch) {
      if (result == null) continue;
      items.add(result.$1);
      keptOriginalIndices.add(result.$2);
      artworkRelocated |= result.$3;
    }
    // Cached covers and remote tracks can otherwise complete entirely through
    // microtasks and starve rendering while a very large queue is restored.
    if (end % 64 == 0) await Future<void>.delayed(Duration.zero);
  }
  return (
    items: items,
    keptOriginalIndices: keptOriginalIndices,
    artworkRelocated: artworkRelocated,
  );
}
