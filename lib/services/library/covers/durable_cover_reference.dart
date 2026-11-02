import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sistrum/utils/text/string_utils.dart';

/// A stored cover must outlive the decoder/process that produced it.
/// This normalizes references only; it never loads remote artwork.
String? durableCoverReference(String? reference) {
  final value = normalizeCoverReference(reference);
  if (value == null) return null;
  final uri = Uri.tryParse(value);
  if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
    final host = uri.host.toLowerCase();
    return host == 'localhost' || host == '::1' || host.startsWith('127.')
        ? null
        : value;
  }
  final path = uri?.scheme == 'file' ? uri!.toFilePath() : value;
  if (path.startsWith('/')) {
    final normalized = p.normalize(path);
    final transient =
        p.isWithin(p.normalize(Directory.systemTemp.path), normalized) ||
        p
            .split(normalized)
            .any(
              (part) =>
                  part == 'network_metadata' ||
                  part.startsWith('download_cover_preview_'),
            );
    if (transient) return null;
  }
  return value;
}
