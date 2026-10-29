import 'dart:io';

import 'package:sistrum/models/metadata_separators.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_metadata.dart';
import 'package:sistrum/services/library/metadata_cover_resources.dart';
import 'package:sistrum/services/library/metadata_edit_result.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/utils/best_effort_delete.dart';

enum MetadataSaveFailure { backend, ffmpeg, storage, unexpected }

class MetadataSaveResult {
  final MetadataSaveFailure? failure;
  final Object? error;

  const MetadataSaveResult.saved() : failure = null, error = null;
  const MetadataSaveResult.failed(
    MetadataSaveFailure this.failure, [
    this.error,
  ]);
}

class MetadataSaveRequest {
  final String filePath;
  final Map<String, String> metadata;
  final String? selectedCoverPath;
  final String? currentCoverPath;

  MetadataSaveRequest({
    required this.filePath,
    required Map<String, String> metadata,
    this.selectedCoverPath,
    this.currentCoverPath,
  }) : metadata = Map.unmodifiable(metadata);
}

enum MetadataSaveCodec { mp3, m4a, opus }

typedef MetadataEmbed =
    Future<String?> Function(
      MetadataSaveCodec codec,
      String path,
      String? coverPath,
      Map<String, String> metadata,
    );

/// Writes tags without widget state, and owns resources until every writer ends.
class MetadataPersistenceService {
  final MetadataCoverResources covers;
  final Future<Map<String, dynamic>> Function(String, Map<String, String>) edit;
  final Future<Map<String, dynamic>> Function(String) read;
  final MetadataEmbed embed;
  final Future<SafWriteBackResult> Function(String, String) writeBack;

  const MetadataPersistenceService({
    required this.covers,
    this.edit = MediaFileBridge.editFileMetadata,
    this.read = MediaFileBridge.readFileMetadata,
    this.embed = _embed,
    this.writeBack = MediaFileBridge.writeTempToSafDetailed,
  });

  Future<MetadataSaveResult> save(MetadataSaveRequest request) async {
    final releaseLease = covers.retain();
    String? extractedCoverDir;
    String? stagedPath;
    try {
      final coverPath = request.selectedCoverPath;

      final metadata = {...request.metadata, 'cover_path': coverPath ?? ''};
      final edit = MetadataEditResult.decode(
        await this.edit(request.filePath, metadata),
      );
      stagedPath = edit.tempPath;
      if (edit.outcome == MetadataEditOutcome.failed) {
        return MetadataSaveResult.failed(
          MetadataSaveFailure.backend,
          edit.error,
        );
      }
      if (edit.outcome == MetadataEditOutcome.completed) {
        return const MetadataSaveResult.saved();
      }

      final target = stagedPath ?? request.filePath;
      final tags = _fallbackTags(metadata);
      try {
        final existing = await read(target);
        for (final key in const [
          'REPLAYGAIN_TRACK_GAIN',
          'REPLAYGAIN_TRACK_PEAK',
          'REPLAYGAIN_ALBUM_GAIN',
          'REPLAYGAIN_ALBUM_PEAK',
        ]) {
          final value = existing[key.toLowerCase()]?.toString() ?? '';
          if (value.isNotEmpty) tags[key] = value;
        }
      } catch (_) {
        // Computed ReplayGain tags are preserved when the reader is available.
      }
      var existingCover = coverPath ?? request.currentCoverPath;
      if (existingCover == null || existingCover.isEmpty) {
        final extracted = await covers.extract(target);
        existingCover = extracted?.path;
        extractedCoverDir = extracted?.tempDir;
      }

      final codec = _codec(request.filePath);
      if (codec == null) {
        return const MetadataSaveResult.failed(MetadataSaveFailure.ffmpeg);
      }
      final String? output;
      try {
        output = await embed(codec, target, existingCover, tags);
      } on FFmpegMetadataFailure catch (error) {
        return MetadataSaveResult.failed(MetadataSaveFailure.ffmpeg, error);
      }
      if (output == null) {
        return const MetadataSaveResult.failed(MetadataSaveFailure.ffmpeg);
      }
      final safUri = edit.safUri;
      if (stagedPath != null && safUri != null) {
        final written = await writeBack(output, safUri);
        if (!written.success) {
          return MetadataSaveResult.failed(
            MetadataSaveFailure.storage,
            written.error ?? written.recoveryPath,
          );
        }
      }
      return const MetadataSaveResult.saved();
    } catch (error) {
      return MetadataSaveResult.failed(MetadataSaveFailure.unexpected, error);
    } finally {
      // Android also deletes on writeback; failed FFmpeg never reaches it.
      if (stagedPath != null && stagedPath != request.filePath) {
        await deleteBestEffort(File(stagedPath));
      }
      await covers.release(extractedCoverDir);
      await releaseLease();
    }
  }

  static MetadataSaveCodec? _codec(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.mp3')) return MetadataSaveCodec.mp3;
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) {
      return MetadataSaveCodec.m4a;
    }
    if (lower.endsWith('.opus') || lower.endsWith('.ogg')) {
      return MetadataSaveCodec.opus;
    }
    return null;
  }

  static Map<String, String> _fallbackTags(Map<String, String> metadata) {
    String index(String key) {
      final number = metadata['${key}_number'] ?? '';
      final total = metadata['${key}_total'] ?? '';
      if (number.isEmpty || number == '0') return '';
      return total.isEmpty || total == '0' ? number : '$number/$total';
    }

    // Include only fields present in this request. Omitted fields are left
    // untouched by the fallback writers instead of being cleared with ''.
    final tags = <String, String>{
      for (final entry in const {
        'TITLE': 'title',
        'ARTIST': 'artist',
        'ALBUM': 'album',
        'ALBUMARTIST': 'album_artist',
        'DATE': 'date',
        'GENRE': 'genre',
        'ISRC': 'isrc',
        'LYRICS': 'lyrics',
        'UNSYNCEDLYRICS': 'lyrics',
        'ORGANIZATION': 'label',
        'COPYRIGHT': 'copyright',
        'COMPOSER': 'composer',
        'COMMENT': 'comment',
        'ITUNESADVISORY': 'explicit',
        'RELEASETYPE': 'album_type',
        'BARCODE': 'upc',
        'COMPILATION': 'compilation',
      }.entries)
        if (metadata.containsKey(entry.value))
          entry.key: metadata[entry.value] ?? '',
    };
    if (metadata.containsKey('track_number')) {
      tags['TRACKNUMBER'] = index('track');
    }
    if (metadata.containsKey('disc_number')) {
      tags['DISCNUMBER'] = index('disc');
    }
    // Per-field separators: format list values here, then pass the keys on so
    // the Vorbis mapper writes a joined artist tag instead of splitting it.
    final separators = MetadataSeparators.fromJson({
      for (final field in MetadataSeparators.fields)
        field: metadata['${field}_separator'] ?? '',
    });
    if (separators.isDefault) return tags;
    final selected = separators.toJson();
    for (final entry in const {
      'ARTIST': 'artist',
      'ALBUMARTIST': 'album_artist',
      'COMPOSER': 'composer',
      'GENRE': 'genre',
    }.entries) {
      if (!tags.containsKey(entry.key)) continue;
      tags[entry.key] = formatMetadataTagValue(
        tags[entry.key]!,
        selected[entry.value] ?? '',
      );
    }
    return {...tags, ...separators.writerFields};
  }

  static Future<String?> _embed(
    MetadataSaveCodec codec,
    String path,
    String? coverPath,
    Map<String, String> metadata,
  ) => switch (codec) {
    // A metadata edit preserves the tags it does not change. Only the Opus
    // remux can do that; the MP3 and M4A remux writers replace the whole tag
    // set, so report the unsupported preservation instead of running them.
    MetadataSaveCodec.mp3 ||
    MetadataSaveCodec.m4a => throw FFmpegMetadataFailure(
      '${codec.name.toUpperCase()} metadata preservation requires the '
      'native tag writer',
    ),
    MetadataSaveCodec.opus => FFmpegMetadata.embedMetadataToOpus(
      opusPath: path,
      coverPath: coverPath,
      metadata: metadata,
      preserveMetadata: true,
    ),
  };
}
