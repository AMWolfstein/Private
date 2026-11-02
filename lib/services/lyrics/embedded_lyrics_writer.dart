import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/metadata/local_song_edit_values.dart';
import 'package:sistrum/services/library/metadata/metadata_cover_resources.dart';
import 'package:sistrum/services/library/metadata/track_metadata_persistence.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/utils/logging/logger.dart';

final _log = AppLogger('EmbeddedLyrics');

/// Result of writing lyrics into a song's own file. Backup and restore inside
/// the persistence service protect the file; lyrics are never stored anywhere
/// else.
class EmbeddedLyricsWriteResult {
  const EmbeddedLyricsWriteResult.saved() : saved = true, failure = null;
  const EmbeddedLyricsWriteResult.failed(MetadataSaveFailure this.failure)
    : saved = false;

  final bool saved;
  final MetadataSaveFailure? failure;
}

/// The part of the lyrics flow that touches files, behind an interface so the
/// flow can be tested without a device.
abstract interface class EmbeddedLyricsStore {
  /// The lyrics the file carries now, or an empty string.
  Future<String> existingLyrics(LocalLibraryItem item);

  /// Writes [lyrics] into the file. Every other tag is kept.
  Future<EmbeddedLyricsWriteResult> write(LocalLibraryItem item, String lyrics);
}

/// Writes lyrics through the same persistence path as Edit Metadata. The file's
/// current tags are read first and sent with the lyrics, so no other tag is
/// dropped when FFmpeg rewrites the file.
class MetadataEmbeddedLyricsStore implements EmbeddedLyricsStore {
  MetadataEmbeddedLyricsStore({
    this.readTags = MediaFileBridge.readFileMetadata,
    MetadataPersistenceService Function(MetadataCoverResources covers)?
    persistence,
    this.refreshIndex,
  }) : _persistence =
           persistence ??
           ((covers) => MetadataPersistenceService(covers: covers));

  final Future<Map<String, dynamic>> Function(String) readTags;
  final MetadataPersistenceService Function(MetadataCoverResources covers)
  _persistence;

  /// Re-reads the file into the library index after a successful write, so
  /// the song's lyrics state updates at once.
  final Future<void> Function(LocalLibraryItem item)? refreshIndex;

  @override
  Future<String> existingLyrics(LocalLibraryItem item) async {
    final tags = await readTags(item.filePath);
    return tags['lyrics']?.toString() ?? '';
  }

  @override
  Future<EmbeddedLyricsWriteResult> write(
    LocalLibraryItem item,
    String lyrics,
  ) async {
    final covers = MetadataCoverResources();
    try {
      final tags = await readTags(item.filePath);
      final values = localSongEditValues(item, tags)..['lyrics'] = lyrics;
      final result = await _persistence(
        covers,
      ).save(MetadataSaveRequest(filePath: item.filePath, metadata: values));
      if (result.failure != null) {
        return EmbeddedLyricsWriteResult.failed(result.failure!);
      }
      // The file is already written; a failed index refresh only leaves the
      // lyrics state stale until the next scan, so it does not fail the save.
      try {
        await refreshIndex?.call(item);
      } catch (error) {
        _log.w('Saved lyrics but could not refresh the index: $error');
      }
      return const EmbeddedLyricsWriteResult.saved();
    } catch (_) {
      return const EmbeddedLyricsWriteResult.failed(
        MetadataSaveFailure.unexpected,
      );
    } finally {
      await covers.dispose();
    }
  }
}
