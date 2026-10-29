// Row models and query descriptors for the local library database.

// v4 records ReplayGain availability; older rows rescan once.
const libraryAudioMetadataScanVersion = 4;
const libraryLyricsMetadataScanVersion = 3;

class LocalLibrarySource {
  final String id;
  final String path;
  final String displayName;
  final String? volumeId;
  final bool isRemovable;
  final bool enabled;
  final bool available;
  final int trackCount;
  final DateTime? lastScannedAt;
  final DateTime? lastSeenAt;
  final String? lastScanError;

  const LocalLibrarySource({
    required this.id,
    required this.path,
    required this.displayName,
    this.volumeId,
    this.isRemovable = false,
    this.enabled = true,
    this.available = true,
    this.trackCount = 0,
    this.lastScannedAt,
    this.lastSeenAt,
    this.lastScanError,
  });

  bool get isIndexed => lastScannedAt != null || trackCount > 0;

  LocalLibrarySource copyWith({
    bool? enabled,
    bool? available,
    int? trackCount,
    DateTime? lastScannedAt,
    DateTime? lastSeenAt,
    String? lastScanError,
    bool clearLastScanError = false,
  }) {
    return LocalLibrarySource(
      id: id,
      path: path,
      displayName: displayName,
      volumeId: volumeId,
      isRemovable: isRemovable,
      enabled: enabled ?? this.enabled,
      available: available ?? this.available,
      trackCount: trackCount ?? this.trackCount,
      lastScannedAt: lastScannedAt ?? this.lastScannedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
      lastScanError: clearLastScanError
          ? null
          : lastScanError ?? this.lastScanError,
    );
  }
}

class LocalLibraryBatchLookupRequest {
  final String? id;
  final String? isrc;
  final String trackName;
  final String artistName;

  const LocalLibraryBatchLookupRequest({
    this.id,
    this.isrc,
    required this.trackName,
    required this.artistName,
  });
}

class IsrcDuplicateEntry {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final String filePath;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;
  final String? format;

  const IsrcDuplicateEntry({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    required this.filePath,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.format,
  });
}

class IsrcDuplicateGroup {
  final String isrc;
  final List<IsrcDuplicateEntry> entries;

  const IsrcDuplicateGroup({required this.isrc, required this.entries});
}

/// Values for the library quality filter. The database query keeps them as
/// strings at its boundary, so every caller uses these names instead of
/// repeating the literals.
abstract final class LibraryQualityFilter {
  static const hiRes = 'hires';
  static const cd = 'cd';
  static const lossy = 'lossy';
}

class LibraryBrowseDbQuery {
  final bool includeSingleTrackAlbums;
  final String? albumArtist;
  final int limit;
  final int offset;
  final String filterMode;
  final String? searchQuery;

  /// One of [LibraryQualityFilter]'s values; unknown strings do not filter.
  final String? quality;
  final String? format;
  final String? metadata;
  final String sortMode;
  final LibraryBrowseDbCursor? cursor;

  const LibraryBrowseDbQuery({
    this.includeSingleTrackAlbums = false,
    this.albumArtist,
    this.limit = 100,
    this.offset = 0,
    this.filterMode = 'all',
    this.searchQuery,
    this.quality,
    this.format,
    this.metadata,
    this.sortMode = 'latest',
    this.cursor,
  });
}

/// Opaque seek cursor for queue Library pagination.
///
/// Values follow the active SQL order (including its unique tie-breaker), so
/// later pages can seek from the last row instead of making SQLite discard an
/// ever-growing OFFSET prefix.
class LibraryBrowseDbCursor {
  final List<Object> values;

  const LibraryBrowseDbCursor(this.values);

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! LibraryBrowseDbCursor ||
        other.values.length != values.length) {
      return false;
    }
    for (var i = 0; i < values.length; i++) {
      if (values[i] != other.values[i]) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(values);
}

class LibraryBrowseDbPage {
  final List<Map<String, dynamic>> rows;
  final LibraryBrowseDbCursor? nextCursor;

  const LibraryBrowseDbPage({required this.rows, required this.nextCursor});
}

class LibraryBrowseCounts {
  final int allTrackCount;
  final int albumCount;
  final int singleTrackCount;

  const LibraryBrowseCounts({
    required this.allTrackCount,
    required this.albumCount,
    required this.singleTrackCount,
  });
}
