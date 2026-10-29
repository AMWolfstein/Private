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
}

/// Outcome of a ReplayGain tag change on a single file.
final class ReplayGainWriteResult {
  const ReplayGainWriteResult.written()
    : failure = null,
      error = null;

  const ReplayGainWriteResult.failed(this.failure, {this.error});

  final ReplayGainWriteFailure? failure;
  final Object? error;

  bool get isWritten => failure == null;
}
