// Adapted for Sistrum from Mornye and Mornye-Extension (LGPL-3.0-only,
// Copyright 2026 zarzet and contributors); see assets/licenses/animated_artwork.txt.
import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:sistrum/services/animated_artwork/apple_artwork_parse.dart';

/// Reads Apple Music catalog metadata for artwork only. The developer token
/// is the web player's own short-lived token, which Apple does not document
/// for third-party use; nothing here is a stable public API.
///
/// Tokens live in memory only: never written to disk, logged or committed.
class AppleArtworkClient {
  AppleArtworkClient({
    required this.client,
    this.storefront = 'us',
    this.attempts = 3,
    this.requestTimeout = const Duration(seconds: 12),
    Future<void> Function(Duration delay)? pause,
    DateTime Function()? clock,
  }) : _pause = pause ?? Future<void>.delayed,
       _clock = clock ?? DateTime.now;

  final http.Client client;
  final String storefront;
  final int attempts;
  final Duration requestTimeout;
  final Future<void> Function(Duration delay) _pause;
  final DateTime Function() _clock;

  String? _token;
  int _tokenExpiresAtMs = 0;

  static const _maxPageBytes = 2 * 1024 * 1024;
  static const _maxBundleBytes = 12 * 1024 * 1024;
  static const _maxBundles = 3;
  static const _userAgent =
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
      'Chrome/124.0 Safari/537.36';

  /// The developer token, fetched once and reused until shortly before it
  /// expires. Call [forgetToken] after a 401 to fetch a fresh one.
  Future<String> _ensureToken() async {
    final now = _clock().millisecondsSinceEpoch;
    final token = _token;
    if (token != null && now < _tokenExpiresAtMs) return token;
    final fresh = await _fetchToken();
    _token = fresh;
    final exp = appleTokenExpiryMillis(fresh);
    // Five minutes early, like the reference source. Without an exp claim,
    // the token is treated as valid for one hour only.
    _tokenExpiresAtMs = exp != null
        ? exp - const Duration(minutes: 5).inMilliseconds
        : now + const Duration(hours: 1).inMilliseconds;
    return fresh;
  }

  void forgetToken() {
    _token = null;
    _tokenExpiresAtMs = 0;
  }

  Future<String> _fetchToken() async {
    final page = await _getText(
      Uri.parse('https://music.apple.com/us/browse'),
      maxBytes: _maxPageBytes,
      headers: {'User-Agent': _userAgent},
    );
    final direct = extractAppleDeveloperToken(page);
    if (direct != null) return direct;

    final scripts = RegExp(r'src="(/assets/[^"]*\.js)"')
        .allMatches(page)
        .map((m) => m.group(1)!)
        .where((path) => !path.contains('-legacy'))
        .take(_maxBundles);
    for (final path in scripts) {
      final bundle = await _getText(
        Uri.parse('https://music.apple.com$path'),
        maxBytes: _maxBundleBytes,
        headers: {'User-Agent': _userAgent},
      );
      final token = extractAppleDeveloperToken(bundle);
      if (token != null) return token;
    }
    throw const AppleArtworkUnavailable('developer token not found');
  }

  /// `GET` a catalog path, e.g. `albums/123?extend=editorialVideo`. Retries
  /// once after a token refresh when Apple rejects the token.
  Future<Map<String, dynamic>> _catalog(String path) async {
    for (var refreshed = 0; refreshed < 2; refreshed++) {
      final token = await _ensureToken();
      final uri = Uri.parse(
        'https://amp-api.music.apple.com/v1/catalog/$storefront/$path',
      );
      final response = await _send(
        uri,
        headers: {
          'Authorization': 'Bearer $token',
          'Origin': 'https://music.apple.com',
          'Referer': 'https://music.apple.com/',
          'User-Agent': _userAgent,
        },
      );
      if (response.statusCode == 401 && refreshed == 0) {
        forgetToken();
        continue;
      }
      if (response.statusCode != 200) {
        throw AppleArtworkUnavailable('HTTP ${response.statusCode}');
      }
      final decoded = _decodeJson(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const AppleArtworkUnavailable('catalog response is not an object');
      }
      return decoded;
    }
    throw const AppleArtworkUnavailable('token rejected');
  }

  /// Album and artist search. Returns every usable entry, possibly none.
  Future<List<AppleArtworkCandidate>> search(String term) async {
    final query = term.trim();
    if (query.isEmpty) return const [];
    final json = await _catalog(
      'search?term=${Uri.encodeQueryComponent(query)}'
      '&types=albums,artists&limit=10',
    );
    return parseAppleSearchResults(json);
  }

  /// The motion video for an album, using tall variants only, or null when
  /// Apple has none. Throws when the catalog cannot answer.
  Future<AppleMotionVideo?> albumVideo(String id) async {
    final json = await _catalog(
      'albums/$id?extend=editorialVideo,upc,trackCount',
    );
    return _videoFromDetail(json, tallOnly: true);
  }

  /// The motion video for an artist, any variant, or null.
  Future<AppleMotionVideo?> artistVideo(String id) async {
    final json = await _catalog('artists/$id?extend=editorialVideo');
    return _videoFromDetail(json, tallOnly: false);
  }

  /// Album details needed for matching a direct link or search result.
  Future<AppleArtworkCandidate?> albumDetails(String id) async {
    final json = await _catalog('albums/$id?extend=upc,trackCount');
    final item = _firstItem(json);
    if (item == null) return null;
    final attributes = _attributes(item);
    final name = attributes?['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const AppleArtworkUnavailable('album has no name');
    }
    return AppleArtworkCandidate(
      kind: AppleArtworkKind.album,
      id: id,
      name: name.trim(),
      artistName: attributes?['artistName'] as String?,
      upc: attributes?['upc'] as String?,
      trackCount: attributes?['trackCount'] as int?,
      previewUrl: appleStaticPreview(attributes),
    );
  }

  /// Artist details for a direct link, or null when Apple has no such artist.
  Future<AppleArtworkCandidate?> artistDetails(String id) async {
    final json = await _catalog('artists/$id');
    final item = _firstItem(json);
    if (item == null) return null;
    final attributes = _attributes(item);
    final name = attributes?['name'];
    if (name is! String || name.trim().isEmpty) {
      throw const AppleArtworkUnavailable('artist has no name');
    }
    return AppleArtworkCandidate(
      kind: AppleArtworkKind.artist,
      id: id,
      name: name.trim(),
      previewUrl: appleStaticPreview(attributes),
    );
  }

  AppleMotionVideo? _videoFromDetail(
    Map<String, dynamic> json, {
    required bool tallOnly,
  }) {
    final item = _firstItem(json);
    if (item == null) return null;
    final attributes = _attributes(item);
    final editorial = attributes?['editorialVideo'];
    if (editorial != null && editorial is! Map) {
      throw const AppleArtworkUnavailable('editorialVideo has the wrong shape');
    }
    return pickAppleMotionVideo(
      editorial is Map ? Map<String, dynamic>.from(editorial) : null,
      tallOnly: tallOnly,
    );
  }

  Map<String, dynamic>? _firstItem(Map<String, dynamic> json) {
    final data = json['data'];
    if (data is! List) {
      throw const AppleArtworkUnavailable('catalog response has no data list');
    }
    if (data.isEmpty) return null;
    final first = data.first;
    if (first is! Map) {
      throw const AppleArtworkUnavailable('catalog item has the wrong shape');
    }
    return Map<String, dynamic>.from(first);
  }

  Map<String, dynamic>? _attributes(Map<String, dynamic> item) {
    final attributes = item['attributes'];
    if (attributes is! Map) return null;
    return Map<String, dynamic>.from(attributes);
  }

  Future<String> _getText(
    Uri uri, {
    required int maxBytes,
    required Map<String, String> headers,
  }) async {
    final response = await _send(uri, headers: headers);
    if (response.statusCode != 200) {
      throw AppleArtworkUnavailable('HTTP ${response.statusCode}');
    }
    if (response.bodyBytes.length > maxBytes) {
      throw const AppleArtworkUnavailable('page exceeds size limit');
    }
    return response.body;
  }

  /// One GET with a timeout. Retries only transient failures, with bounded
  /// backoff that honours a short Retry-After.
  Future<http.Response> _send(
    Uri uri, {
    required Map<String, String> headers,
  }) async {
    http.Response? last;
    Object? lastError;
    for (var attempt = 0; attempt < attempts; attempt++) {
      try {
        last = await client.get(uri, headers: headers).timeout(requestTimeout);
        lastError = null;
      } on Object catch (error) {
        last = null;
        lastError = error;
      }
      final status = last?.statusCode;
      final transient =
          last == null || status == 408 || status == 425 || status == 429 ||
          (status != null && status >= 500);
      if (!transient || attempt == attempts - 1) break;
      final retryAfter = int.tryParse(_header(last, 'retry-after') ?? '');
      final seconds = (retryAfter ?? (attempt + 1)).clamp(0, 10);
      await _pause(Duration(seconds: seconds));
    }
    if (last == null) {
      throw AppleArtworkUnavailable(
        'request failed: ${lastError.runtimeType}',
      );
    }
    return last;
  }

  static String? _header(http.Response? response, String name) {
    if (response == null) return null;
    for (final entry in response.headers.entries) {
      if (entry.key.toLowerCase() == name) return entry.value;
    }
    return null;
  }

  static Object? _decodeJson(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      throw const AppleArtworkUnavailable('response is not JSON');
    }
  }
}
