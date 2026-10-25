import 'package:spotiflac_android/services/library_database_models.dart';

/// Higher quality first. Lossy sample rates do not imply higher fidelity:
/// compare their measured bitrate before rate/depth metadata.
enum DuplicateFidelity { lossless, lossy, unknown }

DuplicateFidelity duplicateFidelity(IsrcDuplicateEntry entry) {
  final declared = entry.format?.trim().toLowerCase() ?? '';
  final name = Uri.tryParse(entry.filePath)?.pathSegments.lastOrNull ?? '';
  // Do not infer AAC vs ALAC from an ambiguous M4A container. Explicit codec
  // metadata wins; an absent codec can use an unambiguous filename suffix.
  final format = declared.isNotEmpty
      ? declared
      : name.substring(name.lastIndexOf('.') + 1).toLowerCase();
  if (const {
    'flac',
    'alac',
    'wav',
    'aiff',
    'aif',
    'ape',
    'wv',
    'wavpack',
    'tta',
    'dsf',
    'dff',
  }.contains(format)) {
    return DuplicateFidelity.lossless;
  }
  if (const {
    'mp3',
    'mp2',
    'aac',
    'opus',
    'ogg',
    'vorbis',
    'ac3',
    'eac3',
    'ac4',
    'wma',
    'amr',
    'speex',
  }.contains(format)) {
    return DuplicateFidelity.lossy;
  }
  return DuplicateFidelity.unknown;
}

/// Unknown codec/quality must not authorize choosing a physical copy to erase.
bool hasComparableDuplicateQuality(IsrcDuplicateEntry entry) =>
    switch (duplicateFidelity(entry)) {
      DuplicateFidelity.lossless =>
        (entry.bitDepth ?? 0) > 0 && (entry.sampleRate ?? 0) > 0,
      DuplicateFidelity.lossy => (entry.bitrate ?? 0) > 0,
      DuplicateFidelity.unknown => false,
    };

int compareDuplicateQuality(IsrcDuplicateEntry a, IsrcDuplicateEntry b) {
  final aLossless = duplicateFidelity(a) == DuplicateFidelity.lossless;
  final bLossless = duplicateFidelity(b) == DuplicateFidelity.lossless;

  if (aLossless != bLossless) return aLossless ? -1 : 1;
  final fields = aLossless
      ? [
          (a.bitDepth, b.bitDepth),
          (a.sampleRate, b.sampleRate),
          (a.bitrate, b.bitrate),
        ]
      : [
          (a.bitrate, b.bitrate),
          (a.sampleRate, b.sampleRate),
          (a.bitDepth, b.bitDepth),
        ];
  for (final (left, right) in fields) {
    final order = (right ?? 0).compareTo(left ?? 0);
    if (order != 0) return order;
  }
  final sourceOrder = a.source.compareTo(b.source);
  return sourceOrder != 0 ? sourceOrder : a.id.compareTo(b.id);
}
