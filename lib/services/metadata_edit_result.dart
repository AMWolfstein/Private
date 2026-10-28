/// One native metadata edit, decoded once from the channel response so every
/// consumer reads the same protocol instead of interpreting map keys itself.
enum MetadataEditOutcome {
  /// The native writer committed the change.
  completed,

  /// The native writer staged a temp file: Dart must run FFmpeg on it and write
  /// the result back through `writeTempToSaf` (or promote it in place).
  ffmpegStaged,

  /// The edit did not happen.
  failed,
}

class MetadataEditResult {
  const MetadataEditResult._({
    required this.outcome,
    this.method,
    this.tempPath,
    this.safUri,
    this.error,
  });

  /// Decodes the native response. A response without an error must still carry
  /// a method and must not report `success: false`; anything else is a failed
  /// edit rather than a silent success.
  factory MetadataEditResult.decode(Map<String, dynamic> response) {
    final error = (response['error']?.toString() ?? '').trim();
    final method = (response['method']?.toString() ?? '').trim();
    final nativeMethod = method.isEmpty ? null : method;
    final tempPath = response['temp_path']?.toString();
    final safUri = response['saf_uri']?.toString();
    if (error.isNotEmpty) {
      return MetadataEditResult._(
        outcome: MetadataEditOutcome.failed,
        method: nativeMethod,
        tempPath: tempPath,
        safUri: safUri,
        error: error,
      );
    }
    if (response['success'] == false) {
      return MetadataEditResult._(
        outcome: MetadataEditOutcome.failed,
        method: nativeMethod,
        tempPath: tempPath,
        safUri: safUri,
        error: 'Native metadata edit reported failure',
      );
    }
    if (nativeMethod == null) {
      return MetadataEditResult._(
        outcome: MetadataEditOutcome.failed,
        tempPath: tempPath,
        safUri: safUri,
        error: 'Native metadata edit returned no method',
      );
    }
    if (nativeMethod == 'ffmpeg') {
      return MetadataEditResult._(
        outcome: MetadataEditOutcome.ffmpegStaged,
        method: nativeMethod,
        tempPath: tempPath,
        safUri: safUri,
      );
    }
    return MetadataEditResult._(
      outcome: MetadataEditOutcome.completed,
      method: nativeMethod,
      tempPath: tempPath,
      safUri: safUri,
    );
  }

  final MetadataEditOutcome outcome;
  final String? method;
  final String? tempPath;
  final String? safUri;
  final String? error;

  /// Native writers report `native` or a `native_*` method name.
  bool get isNativeMethod =>
      method == 'native' || (method?.startsWith('native_') ?? false);
}
