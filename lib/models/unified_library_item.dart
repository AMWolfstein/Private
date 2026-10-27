import 'package:sistrum/models/library_collections.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/services/library_database_models.dart';
import 'package:sistrum/utils/audio_quality_badge_policy.dart';
import 'package:sistrum/utils/string_utils.dart';

enum LibraryItemSource { local }

/// A library track backed by a local-library scan record, unified for shared
/// list and batch handling.
class UnifiedLibraryItem {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? coverUrl;
  final String? localCoverPath;
  final String filePath;
  final String? quality;
  final DateTime addedAt;
  final LibraryItemSource source;

  final LocalLibraryItem? localItem;

  UnifiedLibraryItem({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.coverUrl,
    this.localCoverPath,
    required this.filePath,
    this.quality,
    required this.addedAt,
    required this.source,
    this.localItem,
  });

  factory UnifiedLibraryItem.fromLocalLibrary(LocalLibraryItem item) {
    String? quality;
    if (item.bitrate != null && item.bitrate! > 0) {
      quality = buildDisplayAudioQuality(
        bitrateKbps: item.bitrate,
        format: item.format,
      );
    } else if (item.bitDepth != null &&
        item.bitDepth! > 0 &&
        item.sampleRate != null) {
      quality = buildDisplayAudioQuality(
        bitDepth: item.bitDepth,
        sampleRate: item.sampleRate,
      );
    }
    return UnifiedLibraryItem(
      id: 'local_${item.id}',
      trackName: item.trackName,
      artistName: item.artistName,
      albumName: item.albumName,
      coverUrl: null,
      localCoverPath: item.coverPath,
      filePath: item.filePath,
      quality: quality,
      addedAt: item.fileModTime != null
          ? DateTime.fromMillisecondsSinceEpoch(item.fileModTime!)
          : item.scannedAt,
      source: LibraryItemSource.local,
      localItem: item,
    );
  }

  bool get hasCover =>
      coverUrl != null ||
      (localCoverPath != null && localCoverPath!.isNotEmpty);

  String? get displayQuality {
    final local = localItem;
    if (local != null) {
      return buildLibraryAudioQualityLabel(
        format: local.format,
        filePath: local.filePath,
        bitrateKbps: local.bitrate,
        storedQuality: quality,
      );
    }

    return quality;
  }

  String? get albumArtist => localItem?.albumArtist;

  String? get releaseDate => localItem?.releaseDate;

  String? get genre => localItem?.genre;

  int? get trackNumber => localItem?.trackNumber;

  int? get discNumber => localItem?.discNumber;

  String? get isrc => localItem?.isrc;

  String? get label => localItem?.label;

  String get searchKey =>
      '${trackName.toLowerCase()}|${artistName.toLowerCase()}|${albumName.toLowerCase()}';
  String get albumKey =>
      '${albumName.toLowerCase()}|${artistName.toLowerCase()}';

  /// Returns the collection key used to match this item against playlist
  /// entries: prefer ISRC, fall back to source:id.
  String get collectionKey {
    if (localItem != null) {
      return libraryTrackCollectionKey(
        id: localItem!.id,
        source: 'local',
        isrc: localItem!.isrc,
      );
    }
    return libraryTrackCollectionKey(id: id);
  }

  Track toTrack() {
    if (localItem != null) {
      final l = localItem!;
      return Track(
        id: l.id,
        name: l.trackName,
        artistName: l.artistName,
        albumName: l.albumName,
        albumArtist: l.albumArtist,
        coverUrl: l.coverPath,
        isrc: l.isrc,
        duration: l.duration ?? 0,
        trackNumber: l.trackNumber,
        discNumber: l.discNumber,
        releaseDate: l.releaseDate,
        source: 'local',
        explicit: l.explicit,
      );
    }
    return Track(
      id: id,
      name: trackName,
      artistName: artistName,
      albumName: albumName,
      coverUrl: coverUrl,
      duration: 0,
    );
  }
}
