import 'package:sistrum/models/library_collections.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/services/library/library_database_models.dart';

/// A local-library track in the shape shared by library lists, selection and
/// batch actions. The scan record is the single source of track metadata; only
/// the stable selection key and the display label are derived here.
class UnifiedLibraryItem {
  const UnifiedLibraryItem(this.localItem);

  factory UnifiedLibraryItem.fromLocalLibrary(LocalLibraryItem item) =>
      UnifiedLibraryItem(item);

  final LocalLibraryItem localItem;

  /// Stable list and selection key, distinct from the scan record id.
  String get id => 'local_${localItem.id}';

  String get trackName => localItem.trackName;

  String get artistName => localItem.artistName;

  String get albumName => localItem.albumName;

  String? get localCoverPath => localItem.coverPath;

  String get filePath => localItem.filePath;

  DateTime get addedAt => localItem.fileModTime != null
      ? DateTime.fromMillisecondsSinceEpoch(localItem.fileModTime!)
      : localItem.scannedAt;

  String get albumKey =>
      '${albumName.toLowerCase()}|${artistName.toLowerCase()}';

  /// Returns the collection key used to match this item against playlist
  /// entries: prefer ISRC, fall back to source:id.
  String get collectionKey => libraryTrackCollectionKey(
    id: localItem.id,
    source: 'local',
    isrc: localItem.isrc,
  );

  Track toTrack() => Track(
    id: localItem.id,
    name: localItem.trackName,
    artistName: localItem.artistName,
    albumName: localItem.albumName,
    albumArtist: localItem.albumArtist,
    coverUrl: localItem.coverPath,
    isrc: localItem.isrc,
    duration: localItem.duration ?? 0,
    trackNumber: localItem.trackNumber,
    discNumber: localItem.discNumber,
    releaseDate: localItem.releaseDate,
    source: 'local',
    explicit: localItem.explicit,
  );
}
