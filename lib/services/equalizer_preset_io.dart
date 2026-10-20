import 'dart:convert';
import 'dart:typed_data';

/// Bound preset input before accumulation, including providers with no size.
Future<String> readEqualizerPreset(
  Stream<List<int>> chunks, {
  int? declaredSize,
}) async {
  const limit = 65536;
  if (declaredSize != null && declaredSize > limit) {
    throw const FormatException('Equalizer preset exceeds 64 KB');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in chunks) {
    if (bytes.length + chunk.length > limit) {
      throw const FormatException('Equalizer preset exceeds 64 KB');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}
