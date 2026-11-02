import 'dart:convert';

import 'package:http/http.dart' as http;

/// One artist returned by Deezer's public search.
class DeezerArtist {
  const DeezerArtist({
    required this.id,
    required this.name,
    required this.pictureUrl,
    required this.fans,
    required this.albums,
  });

  final int id;
  final String name;

  /// Large portrait. Null when Deezer has only its placeholder picture.
  final String? pictureUrl;
  final int fans;
  final int albums;
}

/// Deezer could not be reached or answered with an error. Thrown so an
/// outage is never mistaken for "no artist found".
class DeezerUnavailable implements Exception {
  const DeezerUnavailable(this.reason);
  final String reason;

  @override
  String toString() => 'DeezerUnavailable: $reason';
}

/// Searches Deezer's public artist catalogue. No key is needed.
class DeezerArtistSearch {
  DeezerArtistSearch(
    this._client, {
    this.timeout = const Duration(seconds: 12),
  });

  final http.Client _client;
  final Duration timeout;

  static final _base = Uri.parse('https://api.deezer.com/search/artist');

  /// Returns the artists matching [name], most relevant first. An empty list
  /// means Deezer has no artist with that name.
  Future<List<DeezerArtist>> search(String name) async {
    final query = name.trim();
    if (query.isEmpty) return const [];
    final uri = _base.replace(queryParameters: {'q': query, 'limit': '10'});

    final http.Response response;
    try {
      response = await _client.get(uri).timeout(timeout);
    } catch (error) {
      throw DeezerUnavailable('request failed: $error');
    }
    if (response.statusCode != 200) {
      throw DeezerUnavailable('HTTP ${response.statusCode}');
    }
    return parseDeezerArtists(utf8.decode(response.bodyBytes));
  }
}

/// Reads Deezer's search body. An `error` object is an outage (for example
/// the rate limit), not an empty result.
List<DeezerArtist> parseDeezerArtists(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    throw const DeezerUnavailable('body is not JSON');
  }
  if (json is! Map<String, dynamic>) {
    throw const DeezerUnavailable('body is not an object');
  }
  if (json['error'] != null) {
    throw DeezerUnavailable('API error: ${json['error']}');
  }
  final data = json['data'];
  if (data is! List) return const [];

  final artists = <DeezerArtist>[];
  for (final entry in data.whereType<Map<String, dynamic>>()) {
    final id = entry['id'];
    final name = entry['name']?.toString() ?? '';
    if (id is! int || name.isEmpty) continue;
    final picture = entry['picture_xl']?.toString() ?? '';
    artists.add(
      DeezerArtist(
        id: id,
        name: name,
        pictureUrl: _isPlaceholder(picture) ? null : picture,
        fans: (entry['nb_fan'] as num?)?.toInt() ?? 0,
        albums: (entry['nb_album'] as num?)?.toInt() ?? 0,
      ),
    );
  }
  return artists;
}

/// Deezer serves a generic silhouette for artists without a photo; its path
/// has an empty id segment (`/artist//`).
bool _isPlaceholder(String url) => url.isEmpty || url.contains('/artist//');

/// Compares artist names for an automatic match: case, punctuation and extra
/// spaces are ignored, but every letter and digit must agree.
String normalizeArtistName(String name) => name
    .toLowerCase()
    .replaceAll(RegExp(r'[^\p{L}\p{N}]+', unicode: true), ' ')
    .trim();

/// True when [found] is the same artist as [wanted] after normalization.
bool isExactArtistMatch(String wanted, String found) {
  final a = normalizeArtistName(wanted);
  return a.isNotEmpty && a == normalizeArtistName(found);
}
