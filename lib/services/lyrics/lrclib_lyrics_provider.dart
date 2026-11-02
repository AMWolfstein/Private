import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

/// LRCLIB, the open lyrics database at lrclib.net. Returns line-synced or
/// plain text; it has no word-level timing.
class LrcLibLyricsProvider implements OnlineLyricsProvider {
  LrcLibLyricsProvider({
    http.Client? client,
    this.timeout = const Duration(seconds: 10),
  }) : _client = client ?? http.Client();

  static const _base = 'https://lrclib.net/api/get';
  static const _maxDurationDifference = 3.0;

  final http.Client _client;
  final Duration timeout;

  @override
  String get id => 'lrclib';

  @override
  LyricsTiming get bestTiming => LyricsTiming.lineSynced;

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    final uri = Uri.parse(_base).replace(
      queryParameters: {
        'track_name': query.title,
        'artist_name': query.artist,
        if (query.album != null && query.album!.trim().isNotEmpty)
          'album_name': query.album!,
        if (query.durationSeconds != null)
          'duration': query.durationSeconds!.round().toString(),
      },
    );
    final response = await _client.get(uri).timeout(timeout);
    if (response.statusCode == 404) return null;
    if (response.statusCode != 200) {
      throw http.ClientException('LRCLIB HTTP ${response.statusCode}');
    }
    final json = jsonDecode(utf8.decode(response.bodyBytes));
    if (json is! Map<String, dynamic>) return null;
    if (!_durationMatches(json['duration'], query.durationSeconds)) return null;

    final synced = (json['syncedLyrics'] as String?)?.trim() ?? '';
    final plain = (json['plainLyrics'] as String?)?.trim() ?? '';
    final text = synced.isNotEmpty ? synced : plain;
    if (text.isEmpty) return null;
    return OnlineLyricsCandidate(
      provider: id,
      timing: LyricsTiming.detect(text),
      text: text,
    );
  }

  static bool _durationMatches(Object? found, double? wanted) {
    if (wanted == null || found is! num) return true;
    return (found.toDouble() - wanted).abs() <= _maxDurationDifference;
  }
}
