import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:sistrum/services/artist_images/artist_image_store.dart';

/// A portrait could not be downloaded. Thrown so the caller can tell an
/// outage apart from a missing photo.
class ArtistImageDownloadFailed implements Exception {
  const ArtistImageDownloadFailed(this.reason);
  final String reason;

  @override
  String toString() => 'ArtistImageDownloadFailed: $reason';
}

/// Downloads one portrait over HTTPS. Anything that is not an image of an
/// accepted size is refused.
Future<Uint8List> downloadArtistImage(
  http.Client client,
  String url, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final uri = Uri.tryParse(url);
  if (uri == null || uri.scheme != 'https') {
    throw const ArtistImageDownloadFailed('not an https address');
  }
  final http.Response response;
  try {
    response = await client.get(uri).timeout(timeout);
  } catch (error) {
    throw ArtistImageDownloadFailed('request failed: $error');
  }
  if (response.statusCode != 200) {
    throw ArtistImageDownloadFailed('HTTP ${response.statusCode}');
  }
  final type = response.headers['content-type'] ?? '';
  if (!type.startsWith('image/')) {
    throw ArtistImageDownloadFailed('not an image: $type');
  }
  final bytes = response.bodyBytes;
  if (bytes.isEmpty || bytes.length > kArtistImageMaxBytes) {
    throw ArtistImageDownloadFailed('size ${bytes.length} not accepted');
  }
  return bytes;
}
