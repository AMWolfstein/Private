// Adapted for Sistrum from Mornye and Mornye-Extension (LGPL-3.0-only,
// Copyright 2026 zarzet and contributors); see assets/licenses/animated_artwork.txt.
import 'dart:convert';

import 'package:sistrum/services/artist_images/deezer_artist_search.dart'
    show normalizeArtistName;

/// Video artwork is only ever read from Apple Music's public catalog, which is
/// an unofficial interface: every shape below is checked, and anything
/// unexpected is reported as unavailable rather than guessed at.

/// Editorial motion keys in priority order, as Apple names them. Album covers
/// use the tall variants only; artists accept any of them.
const kAppleMotionKeys = <String>[
  'motionDetailTall',
  'motionTallVideo3x4',
  'motionArtworkTall3x4',
  'motionArtistSquare1x1',
  'motionDetailSquare',
  'motionSquareVideo1x1',
  'motionArtworkSquare1x1',
  'motionArtistFullscreen16x9',
  'motionArtistWide16x9',
  'motionArtworkWide16x9',
  'motionDetailWide',
];

enum AppleArtworkKind { album, artist }

/// A catalog result, reduced to what matching and manual choice need.
class AppleArtworkCandidate {
  const AppleArtworkCandidate({
    required this.kind,
    required this.id,
    required this.name,
    this.artistName,
    this.upc,
    this.trackCount,
    this.previewUrl,
  });

  final AppleArtworkKind kind;
  final String id;
  final String name;

  /// The album artist for albums. Null for artists.
  final String? artistName;
  final String? upc;
  final int? trackCount;

  /// A static still of the artwork, for the result list. Never animated.
  final String? previewUrl;
}

/// The motion video chosen for one entity.
class AppleMotionVideo {
  const AppleMotionVideo({
    required this.key,
    required this.url,
    this.previewUrl,
  });

  /// The Apple key the video came from, such as `motionDetailTall`.
  final String key;

  /// The HLS playlist URL. Expires eventually, so it is only used while the
  /// video is being downloaded or previewed, never for later playback.
  final String url;
  final String? previewUrl;

  bool get tall => key.contains('Tall') || key.contains('3x4');
}

/// A direct Apple Music link the user pasted, such as
/// `https://music.apple.com/us/album/name/1234567`.
class AppleArtworkLink {
  const AppleArtworkLink({required this.kind, required this.id});
  final AppleArtworkKind kind;
  final String id;
}

/// Thrown when the catalog cannot answer or answers in an unexpected shape.
/// Callers must treat it as "try later", never as "no video exists".
class AppleArtworkUnavailable implements Exception {
  const AppleArtworkUnavailable(this.message);
  final String message;

  @override
  String toString() => 'AppleArtworkUnavailable: $message';
}

/// Pulls a developer token out of the music.apple.com page or one of its
/// scripts. Returns null when no token-shaped string is present.
String? extractAppleDeveloperToken(String body) {
  final devToken = RegExp(
    r'devToken=([A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)',
  ).firstMatch(body);
  if (devToken != null) return devToken.group(1);
  final direct = RegExp(
    r'((?:eyJhbGciOiJFUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6IldlYlBsYXlLaWQifQ|'
    r'eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiIsImtpZCI6IldlYlBsYXlLaWQifQ)'
    r'\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+)',
  ).firstMatch(body);
  return direct?.group(1);
}

/// The expiry time of a token's `exp` claim, in UTC milliseconds since epoch,
/// or null when the claim is missing or malformed.
int? appleTokenExpiryMillis(String token) {
  final parts = token.split('.');
  if (parts.length != 3) return null;
  try {
    final payload = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))),
    );
    if (payload is! Map) return null;
    final exp = payload['exp'];
    if (exp is! num) return null;
    return exp.toInt() * 1000;
  } on FormatException {
    return null;
  }
}

/// Parses an Apple Music page link. Returns null for anything that is not an
/// album or artist link.
AppleArtworkLink? parseAppleArtworkUrl(String text) {
  final match = RegExp(
    r'music\.apple\.com/[a-z]{2}/(album|artist)/[^/?#]*/([0-9]+)',
    caseSensitive: false,
  ).firstMatch(text.trim());
  if (match == null) return null;
  final kind = match.group(1)!.toLowerCase() == 'album'
      ? AppleArtworkKind.album
      : AppleArtworkKind.artist;
  return AppleArtworkLink(kind: kind, id: match.group(2)!);
}

Map<String, dynamic>? _asMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : null;

String? _string(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String _artworkUrl(Map<String, dynamic>? artwork, int size) {
  final url = _string(artwork?['url']);
  if (url == null) return '';
  return url
      .replaceAll('{w}', '$size')
      .replaceAll('{h}', '$size');
}

/// The best still for a catalog entry, sized for a list row.
String? appleStaticPreview(Map<String, dynamic>? attributes) {
  final artwork = _asMap(attributes?['artwork']);
  final url = _artworkUrl(artwork, 600);
  return url.isEmpty ? null : url;
}

/// Picks the first usable motion video, or null when Apple has none.
///
/// [tallOnly] restricts the choice to the portrait variants used for albums.
AppleMotionVideo? pickAppleMotionVideo(
  Map<String, dynamic>? editorialVideo, {
  required bool tallOnly,
}) {
  if (editorialVideo == null) return null;
  for (final key in kAppleMotionKeys) {
    if (tallOnly && !(key.contains('Tall') || key.contains('3x4'))) {
      continue;
    }
    final entry = _asMap(editorialVideo[key]);
    final url = _string(entry?['video']);
    if (url == null || !_isHttps(url)) continue;
    final frame = _asMap(entry?['previewFrame']);
    final preview = _string(frame?['url']);
    return AppleMotionVideo(
      key: key,
      url: url,
      previewUrl: preview?.replaceAll('{w}', '600').replaceAll(
        '{h}',
        '${key.contains('Tall') || key.contains('3x4') ? 800 : 338}',
      ),
    );
  }
  return null;
}

bool _isHttps(String url) => Uri.tryParse(url)?.scheme == 'https';

/// Reads one page of catalog search results. The payload must have the
/// expected shape; missing sections are treated as no results only when the
/// response has a `results` object at all.
List<AppleArtworkCandidate> parseAppleSearchResults(Object? json) {
  final root = _asMap(json);
  final results = _asMap(root?['results']);
  if (results == null) {
    throw const AppleArtworkUnavailable('search response has no results');
  }
  final out = <AppleArtworkCandidate>[];
  for (final entry in [
    (kind: AppleArtworkKind.album, section: 'albums'),
    (kind: AppleArtworkKind.artist, section: 'artists'),
  ]) {
    final section = _asMap(results[entry.section]);
    if (section == null) continue;
    final data = section['data'];
    if (data is! List) {
      throw AppleArtworkUnavailable('${entry.section} has no data list');
    }
    for (final item in data) {
      final row = _asMap(item);
      final id = _string(row?['id']);
      final attributes = _asMap(row?['attributes']);
      final name = _string(attributes?['name']);
      if (id == null || name == null || !RegExp(r'^[0-9]+$').hasMatch(id)) {
        continue;
      }
      out.add(
        AppleArtworkCandidate(
          kind: entry.kind,
          id: id,
          name: name,
          artistName: entry.kind == AppleArtworkKind.album
              ? _string(attributes?['artistName'])
              : null,
          upc: _string(attributes?['upc']),
          trackCount: attributes?['trackCount'] is int
              ? attributes!['trackCount'] as int
              : null,
          previewUrl: appleStaticPreview(attributes),
        ),
      );
    }
  }
  return out;
}

/// Matching for a local album against catalog albums. Only an identical
/// title and album artist, with a compatible track count and UPC, can match.
/// Editions differ by their title (`(Deluxe)`) or track count, so they never
/// match the standard release.
enum AppleMatchOutcome { matched, noMatch, ambiguous }

class AppleAlbumMatch {
  const AppleAlbumMatch(this.outcome, [this.candidate]);
  final AppleMatchOutcome outcome;
  final AppleArtworkCandidate? candidate;
}

AppleAlbumMatch matchAppleAlbum({
  required String albumTitle,
  required String albumArtist,
  int? localTrackCount,
  String? localUpc,
  required List<AppleArtworkCandidate> candidates,
}) {
  final title = appleMatchKey(albumTitle);
  final artist = appleMatchKey(albumArtist);
  if (title.isEmpty || artist.isEmpty) return const AppleAlbumMatch(AppleMatchOutcome.noMatch);
  final exact = <AppleArtworkCandidate>[];
  for (final candidate in candidates) {
    if (candidate.kind != AppleArtworkKind.album) continue;
    if (appleMatchKey(candidate.name) != title) continue;
    if (appleMatchKey(candidate.artistName ?? '') != artist) continue;
    if (localTrackCount != null &&
        candidate.trackCount != null &&
        candidate.trackCount != localTrackCount) {
      continue;
    }
    if (localUpc != null &&
        candidate.upc != null &&
        candidate.upc!.toLowerCase() != localUpc.toLowerCase()) {
      continue;
    }
    exact.add(candidate);
  }
  if (exact.isEmpty) return const AppleAlbumMatch(AppleMatchOutcome.noMatch);
  if (exact.length == 1) {
    return AppleAlbumMatch(AppleMatchOutcome.matched, exact.single);
  }
  // Several releases share the same title and artist. A shared UPC settles
  // it; otherwise the choice would be a guess.
  if (localUpc != null) {
    final byUpc = exact
        .where((c) => c.upc?.toLowerCase() == localUpc.toLowerCase())
        .toList();
    if (byUpc.length == 1) {
      return AppleAlbumMatch(AppleMatchOutcome.matched, byUpc.single);
    }
  }
  return const AppleAlbumMatch(AppleMatchOutcome.ambiguous);
}

/// Matching for an artist: the same name after normalization, nothing looser.
AppleAlbumMatch matchAppleArtist({
  required String artistName,
  required List<AppleArtworkCandidate> candidates,
}) {
  final name = appleMatchKey(artistName);
  if (name.isEmpty) return const AppleAlbumMatch(AppleMatchOutcome.noMatch);
  final exact = candidates
      .where(
        (c) => c.kind == AppleArtworkKind.artist && appleMatchKey(c.name) == name,
      )
      .toList();
  if (exact.isEmpty) return const AppleAlbumMatch(AppleMatchOutcome.noMatch);
  if (exact.length == 1) {
    return AppleAlbumMatch(AppleMatchOutcome.matched, exact.single);
  }
  return const AppleAlbumMatch(AppleMatchOutcome.ambiguous);
}

/// The comparison key for catalog names: case, punctuation and spacing are
/// ignored, and letters from every script are kept.
String appleMatchKey(String name) => normalizeArtistName(name);
