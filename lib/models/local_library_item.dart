import 'package:sistrum/utils/audio_format_utils.dart';
import 'package:sistrum/utils/lookup_text.dart';

class LocalLibraryItem {
  static const legacySourceId = 'legacy';

  final String id;
  final String sourceId;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumArtist;
  final String filePath;
  final String? coverPath;
  final DateTime scannedAt;
  final int? fileModTime;
  final String? isrc;
  final int? trackNumber;
  final int? totalTracks;
  final int? discNumber;
  final int? totalDiscs;
  final int? duration;
  final String? releaseDate;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate; // average kbps for both lossless and lossy audio
  final String? genre;
  final String? composer;
  final String? label;
  final String? copyright;
  final bool explicit;
  final bool hasLyrics;
  final bool hasReplayGain;
  final String? format; // flac, alac, eac3, ac3, ac4, mp3, opus, m4a

  const LocalLibraryItem({
    required this.id,
    this.sourceId = legacySourceId,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumArtist,
    required this.filePath,
    this.coverPath,
    required this.scannedAt,
    this.fileModTime,
    this.isrc,
    this.trackNumber,
    this.totalTracks,
    this.discNumber,
    this.totalDiscs,
    this.duration,
    this.releaseDate,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.genre,
    this.composer,
    this.label,
    this.copyright,
    this.explicit = false,
    this.hasLyrics = false,
    this.hasReplayGain = false,
    this.format,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sourceId': sourceId,
    'trackName': trackName,
    'artistName': artistName,
    'albumName': albumName,
    'albumArtist': albumArtist,
    'filePath': filePath,
    'coverPath': coverPath,
    'scannedAt': scannedAt.toIso8601String(),
    'fileModTime': fileModTime,
    'isrc': isrc,
    'trackNumber': trackNumber,
    'totalTracks': totalTracks,
    'discNumber': discNumber,
    'totalDiscs': totalDiscs,
    'duration': duration,
    'releaseDate': releaseDate,
    'bitDepth': bitDepth,
    'sampleRate': sampleRate,
    'bitrate': bitrate,
    'genre': genre,
    'composer': composer,
    'label': label,
    'copyright': copyright,
    'explicit': explicit,
    'hasLyrics': hasLyrics,
    'hasReplayGain': hasReplayGain,
    'format': format,
  };

  /// Decodes a `{source, item}` library row, the envelope the database returns
  /// for mixed Library collections. Bare track maps use [fromJson] directly.
  factory LocalLibraryItem.fromEnvelope(Map<String, dynamic> row) =>
      LocalLibraryItem.fromJson(Map<String, dynamic>.from(row['item'] as Map));

  factory LocalLibraryItem.fromJson(Map<String, dynamic> json) =>
      LocalLibraryItem(
        id: json['id'] as String,
        sourceId: json['sourceId'] as String? ?? legacySourceId,
        trackName: json['trackName'] as String,
        artistName: json['artistName'] as String,
        albumName: json['albumName'] as String,
        albumArtist: json['albumArtist'] as String?,
        filePath: json['filePath'] as String,
        coverPath: json['coverPath'] as String?,
        scannedAt: DateTime.parse(json['scannedAt'] as String),
        fileModTime: (json['fileModTime'] as num?)?.toInt(),
        isrc: json['isrc'] as String?,
        trackNumber: (json['trackNumber'] as num?)?.toInt(),
        totalTracks: (json['totalTracks'] as num?)?.toInt(),
        discNumber: (json['discNumber'] as num?)?.toInt(),
        totalDiscs: (json['totalDiscs'] as num?)?.toInt(),
        duration: (json['duration'] as num?)?.toInt(),
        releaseDate: json['releaseDate'] as String?,
        bitDepth: (json['bitDepth'] as num?)?.toInt(),
        sampleRate: (json['sampleRate'] as num?)?.toInt(),
        bitrate: (json['bitrate'] as num?)?.toInt(),
        genre: json['genre'] as String?,
        composer: json['composer'] as String?,
        label: json['label'] as String?,
        copyright: json['copyright'] as String?,
        explicit: json['explicit'] == true || json['explicit'] == 1,
        hasLyrics: json['hasLyrics'] == true || json['hasLyrics'] == 1,
        // Scan results carry the raw replaygain_* tags; stored rows the flag.
        hasReplayGain: metadataHasReplayGain(json),
        format: json['format'] as String?,
      );

  String get albumKey =>
      '${normalizeLookupText(albumName)}|${normalizeLookupText(albumArtist ?? artistName)}';
}
