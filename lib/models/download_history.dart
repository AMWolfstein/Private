import 'package:spotiflac_android/utils/string_utils.dart';

class DownloadHistoryItem {
  final String id;
  final String trackName;
  final String artistName;
  final String albumName;
  final String? albumArtist;
  final String? coverUrl;
  final String filePath;
  final String? storageMode;
  final String? downloadTreeUri;
  final String? safRelativeDir;
  final String? safFileName;
  final bool safRepaired;
  final String service;
  final DateTime downloadedAt;
  final String? isrc;
  final String? spotifyId;
  final int? trackNumber;
  final int? totalTracks;
  final int? discNumber;
  final int? totalDiscs;
  final int? duration;
  final String? releaseDate;
  final String? quality;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;
  final String? format;
  final String? genre;
  final String? composer;
  final String? label;
  final String? copyright;
  final bool explicit;
  final bool hasLyrics;
  final int lyricsMetadataScanVersion;
  final bool hasReplayGain;

  /// 0 until the finished file's tags were read; only then is a false
  /// [hasReplayGain] a confirmed absence.
  final int replayGainMetadataScanVersion;

  const DownloadHistoryItem({
    required this.id,
    required this.trackName,
    required this.artistName,
    required this.albumName,
    this.albumArtist,
    this.coverUrl,
    required this.filePath,
    this.storageMode,
    this.downloadTreeUri,
    this.safRelativeDir,
    this.safFileName,
    this.safRepaired = false,
    required this.service,
    required this.downloadedAt,
    this.isrc,
    this.spotifyId,
    this.trackNumber,
    this.totalTracks,
    this.discNumber,
    this.totalDiscs,
    this.duration,
    this.releaseDate,
    this.quality,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.format,
    this.genre,
    this.composer,
    this.label,
    this.copyright,
    this.explicit = false,
    this.hasLyrics = false,
    this.lyricsMetadataScanVersion = 0,
    this.hasReplayGain = false,
    this.replayGainMetadataScanVersion = 0,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'trackName': trackName,
    'artistName': artistName,
    'albumName': albumName,
    'albumArtist': albumArtist,
    'coverUrl': coverUrl,
    'filePath': filePath,
    'storageMode': storageMode,
    'downloadTreeUri': downloadTreeUri,
    'safRelativeDir': safRelativeDir,
    'safFileName': safFileName,
    'safRepaired': safRepaired,
    'service': service,
    'downloadedAt': downloadedAt.toUtc().toIso8601String(),
    'isrc': isrc,
    'spotifyId': spotifyId,
    'trackNumber': trackNumber,
    'totalTracks': totalTracks,
    'discNumber': discNumber,
    'totalDiscs': totalDiscs,
    'duration': duration,
    'releaseDate': releaseDate,
    'quality': quality,
    'bitDepth': bitDepth,
    'sampleRate': sampleRate,
    'bitrate': bitrate,
    'format': format,
    'genre': genre,
    'composer': composer,
    'label': label,
    'copyright': copyright,
    'explicit': explicit,
    'hasLyrics': hasLyrics,
    'lyricsMetadataScanVersion': lyricsMetadataScanVersion,
    'hasReplayGain': hasReplayGain,
    'replayGainMetadataScanVersion': replayGainMetadataScanVersion,
  };

  factory DownloadHistoryItem.fromJson(Map<String, dynamic> json) =>
      DownloadHistoryItem(
        id: json['id'] as String,
        trackName: json['trackName'] as String,
        artistName: json['artistName'] as String,
        albumName: json['albumName'] as String,
        albumArtist: normalizeOptionalString(json['albumArtist'] as String?),
        coverUrl: normalizeCoverReference(json['coverUrl']?.toString()),
        filePath: json['filePath'] as String,
        storageMode: json['storageMode'] as String?,
        downloadTreeUri: json['downloadTreeUri'] as String?,
        safRelativeDir: json['safRelativeDir'] as String?,
        safFileName: json['safFileName'] as String?,
        safRepaired: json['safRepaired'] == true,
        service: json['service'] as String,
        downloadedAt: DateTime.parse(json['downloadedAt'] as String).toLocal(),
        isrc: json['isrc'] as String?,
        spotifyId: json['spotifyId'] as String?,
        trackNumber: json['trackNumber'] as int?,
        totalTracks: json['totalTracks'] as int?,
        discNumber: json['discNumber'] as int?,
        totalDiscs: json['totalDiscs'] as int?,
        duration: json['duration'] as int?,
        releaseDate: json['releaseDate'] as String?,
        quality: json['quality'] as String?,
        bitDepth: json['bitDepth'] as int?,
        sampleRate: json['sampleRate'] as int?,
        bitrate: (json['bitrate'] as num?)?.toInt(),
        format: json['format'] as String?,
        genre: json['genre'] as String?,
        composer: json['composer'] as String?,
        label: json['label'] as String?,
        copyright: json['copyright'] as String?,
        explicit: parseExplicitFlag(json['explicit']) == true,
        hasLyrics: json['hasLyrics'] == true || json['hasLyrics'] == 1,
        lyricsMetadataScanVersion:
            (json['lyricsMetadataScanVersion'] as num?)?.toInt() ?? 0,
        hasReplayGain:
            json['hasReplayGain'] == true || json['hasReplayGain'] == 1,
        replayGainMetadataScanVersion:
            (json['replayGainMetadataScanVersion'] as num?)?.toInt() ?? 0,
      );

  DownloadHistoryItem copyWith({
    String? trackName,
    String? artistName,
    String? albumName,
    String? albumArtist,
    String? coverUrl,
    String? filePath,
    String? storageMode,
    String? downloadTreeUri,
    String? safRelativeDir,
    String? safFileName,
    bool? safRepaired,
    String? isrc,
    String? spotifyId,
    int? trackNumber,
    int? totalTracks,
    int? discNumber,
    int? totalDiscs,
    int? duration,
    String? releaseDate,
    String? quality,
    int? bitDepth,
    int? sampleRate,
    int? bitrate,
    String? format,
    String? genre,
    String? composer,
    String? label,
    String? copyright,
    bool? explicit,
    bool? hasLyrics,
    int? lyricsMetadataScanVersion,
    bool? hasReplayGain,
    int? replayGainMetadataScanVersion,
  }) {
    return DownloadHistoryItem(
      id: id,
      trackName: trackName ?? this.trackName,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      albumArtist: albumArtist ?? this.albumArtist,
      coverUrl: normalizeCoverReference(coverUrl ?? this.coverUrl),
      filePath: filePath ?? this.filePath,
      storageMode: storageMode ?? this.storageMode,
      downloadTreeUri: downloadTreeUri ?? this.downloadTreeUri,
      safRelativeDir: safRelativeDir ?? this.safRelativeDir,
      safFileName: safFileName ?? this.safFileName,
      safRepaired: safRepaired ?? this.safRepaired,
      service: service,
      downloadedAt: downloadedAt,
      isrc: isrc ?? this.isrc,
      spotifyId: spotifyId ?? this.spotifyId,
      trackNumber: trackNumber ?? this.trackNumber,
      totalTracks: totalTracks ?? this.totalTracks,
      discNumber: discNumber ?? this.discNumber,
      totalDiscs: totalDiscs ?? this.totalDiscs,
      duration: duration ?? this.duration,
      releaseDate: releaseDate ?? this.releaseDate,
      quality: quality ?? this.quality,
      bitDepth: bitDepth ?? this.bitDepth,
      sampleRate: sampleRate ?? this.sampleRate,
      bitrate: bitrate ?? this.bitrate,
      format: format ?? this.format,
      genre: genre ?? this.genre,
      composer: composer ?? this.composer,
      label: label ?? this.label,
      copyright: copyright ?? this.copyright,
      explicit: explicit ?? this.explicit,
      hasLyrics: hasLyrics ?? this.hasLyrics,
      lyricsMetadataScanVersion:
          lyricsMetadataScanVersion ?? this.lyricsMetadataScanVersion,
      hasReplayGain: hasReplayGain ?? this.hasReplayGain,
      replayGainMetadataScanVersion:
          replayGainMetadataScanVersion ?? this.replayGainMetadataScanVersion,
    );
  }
}
