import 'package:audio_service/audio_service.dart';
import 'package:sistrum/utils/int_utils.dart';
import 'package:sistrum/utils/string_utils.dart';

/// One queue entry. This is the serialized queue representation, so it lives
/// outside the player engine: queue restoration decodes it without importing
/// the engine implementation.
class PlayableMedia {
  final String id;
  final String source;
  final String title;
  final String artist;
  final String album;
  final String? artUri;
  final Duration? duration;
  final int? bitDepth;
  final int? sampleRate;
  final int? bitrate;
  final String? format;
  final bool explicit;
  final String? genre;
  final bool autoplay;

  const PlayableMedia({
    required this.id,
    required this.source,
    required this.title,
    required this.artist,
    this.album = '',
    this.artUri,
    this.duration,
    this.bitDepth,
    this.sampleRate,
    this.bitrate,
    this.format,
    this.explicit = false,
    this.genre,
    this.autoplay = false,
  });

  bool get isContentUri => source.startsWith('content://');

  Map<String, dynamic> toJson() => {
    'id': id,
    'source': source,
    'title': title,
    'artist': artist,
    'album': album,
    if (artUri != null && artUri!.isNotEmpty) 'artUri': artUri,
    if (duration != null) 'durationMs': duration!.inMilliseconds,
    if (bitDepth != null && bitDepth! > 0) 'bitDepth': bitDepth,
    if (sampleRate != null && sampleRate! > 0) 'sampleRate': sampleRate,
    if (bitrate != null && bitrate! > 0) 'bitrate': bitrate,
    if (format != null && format!.trim().isNotEmpty) 'format': format,
    if (explicit) 'explicit': true,
    if (genre != null) 'genre': genre,
    if (autoplay) 'autoplay': true,
  };

  static PlayableMedia? fromJson(Map<String, dynamic> json) {
    final id = json['id'] as String?;
    final source = json['source'] as String?;
    if (id == null || id.isEmpty || source == null || source.isEmpty) {
      return null;
    }
    final durationMs = (json['durationMs'] as num?)?.toInt();
    final artwork = json['artUri'] as String?;
    return PlayableMedia(
      id: id,
      source: source,
      title: json['title'] as String? ?? '',
      artist: json['artist'] as String? ?? '',
      album: json['album'] as String? ?? '',
      artUri: artwork,
      duration: (durationMs != null && durationMs > 0)
          ? Duration(milliseconds: durationMs)
          : null,
      bitDepth: readPositiveInt(json['bitDepth']),
      sampleRate: readPositiveInt(json['sampleRate']),
      bitrate: readPositiveInt(json['bitrate']),
      format: json['format']?.toString(),
      explicit: parseExplicitFlag(json['explicit']) == true,
      genre: json['genre'] as String?,
      autoplay: json['autoplay'] == true,
    );
  }

  /// Converts to the platform queue item. The player passes localized fallback
  /// strings; the literal defaults keep this model free of process-global state.
  MediaItem toMediaItem({
    String unknownTitle = 'Unknown title',
    String unknownArtist = 'Unknown artist',
    String? resolvedSource,
    String? resolvedArtwork,
  }) {
    final artwork = resolvedArtwork ?? artUri;
    return MediaItem(
      id: id,
      title: title.isEmpty ? unknownTitle : title,
      artist: artist.isEmpty ? unknownArtist : artist,
      album: album.isEmpty ? null : album,
      duration: duration,
      artUri: (artwork != null && artwork.isNotEmpty)
          ? Uri.tryParse(artwork)
          : null,
      extras: {
        'source': source,
        if (resolvedSource != null && resolvedSource.isNotEmpty)
          'resolvedSource': resolvedSource,
        if (bitDepth != null && bitDepth! > 0) 'bit_depth': bitDepth,
        if (sampleRate != null && sampleRate! > 0) 'sample_rate': sampleRate,
        if (bitrate != null && bitrate! > 0) 'bitrate': bitrate,
        if (format != null && format!.trim().isNotEmpty)
          'format': format!.trim(),
        if (explicit) 'explicit': true,
        if (autoplay) 'autoplay': true,
      },
    );
  }
}
