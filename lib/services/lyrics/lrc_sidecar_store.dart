import 'dart:io';

import 'package:path/path.dart' as p;

/// Where a song's .lrc file lives: beside the audio file, with the same name.
String lrcSidecarPath(String audioPath) =>
    '${p.withoutExtension(audioPath)}.lrc';

enum LrcSidecarOutcome {
  /// The file was written.
  saved,

  /// A .lrc file already exists and [LrcSidecarStore.write] was not allowed
  /// to replace it.
  exists,

  /// The song is not a plain file path (for example a folder-picker URI), so
  /// a sibling file cannot be created next to it.
  unsupported,

  /// The file could not be written.
  failed,
}

class LrcSidecarResult {
  const LrcSidecarResult(this.outcome, {this.path});

  final LrcSidecarOutcome outcome;

  /// The file that was written, when [outcome] is saved.
  final String? path;
}

/// Writes the .lrc file beside an audio file as UTF-8 text.
class LrcSidecarStore {
  const LrcSidecarStore();

  Future<LrcSidecarResult> write(
    String audioPath,
    String text, {
    required bool replace,
  }) async {
    if (audioPath.startsWith('content://')) {
      return const LrcSidecarResult(LrcSidecarOutcome.unsupported);
    }
    final target = lrcSidecarPath(audioPath);
    final file = File(target);
    try {
      if (!replace && await file.exists()) {
        return const LrcSidecarResult(LrcSidecarOutcome.exists);
      }
      await file.writeAsString(text, flush: true);
      return LrcSidecarResult(LrcSidecarOutcome.saved, path: target);
    } on FileSystemException {
      return const LrcSidecarResult(LrcSidecarOutcome.failed);
    }
  }
}
