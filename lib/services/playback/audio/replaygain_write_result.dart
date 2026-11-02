/// Why a ReplayGain tag change did not reach the file.
enum ReplayGainWriteFailure {
  /// The file's container has no native or stream-copy writer for its tags.
  unsupportedFormat,

  /// The loudness scan produced no usable result.
  scanFailed,

  /// The native or FFmpeg writer rejected the change.
  writeFailed,

  /// The file was written, but reading the tags back did not match.
  verificationFailed,

  /// Copying from, or writing back to, the SAF document failed.
  storageFailed,

  /// The audio stream or the file size changed by more than tags explain, so
  /// the original was restored and nothing was published.
  audioChanged,
}

/// Decides whether a tag write left the file safe to keep. Tags never touch
/// the audio packets, so their hash must match, and the size may only move by
/// a small amount for tags and artwork.
abstract final class ReplayGainIntegrity {
  static const int maxSizeDelta = 1024 * 1024;

  /// Null when the write is safe to keep, otherwise the reason to restore.
  static ReplayGainWriteFailure? check({
    required String? beforeHash,
    required String? afterHash,
    required int sizeBefore,
    required int sizeAfter,
  }) {
    if (beforeHash == null || afterHash == null) {
      return ReplayGainWriteFailure.verificationFailed;
    }
    if (beforeHash != afterHash) return ReplayGainWriteFailure.audioChanged;
    final limit = maxSizeDelta > sizeBefore ~/ 100
        ? maxSizeDelta
        : sizeBefore ~/ 100;
    if ((sizeAfter - sizeBefore).abs() > limit) {
      return ReplayGainWriteFailure.audioChanged;
    }
    return null;
  }
}

/// Outcome of a ReplayGain tag change on a single file.
final class ReplayGainWriteResult {
  const ReplayGainWriteResult.written() : failure = null, error = null;

  const ReplayGainWriteResult.failed(
    ReplayGainWriteFailure this.failure, {
    this.error,
  });

  final ReplayGainWriteFailure? failure;
  final Object? error;

  bool get isWritten => failure == null;
}
