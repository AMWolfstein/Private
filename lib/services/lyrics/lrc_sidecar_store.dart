import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:sistrum/utils/files/best_effort_delete.dart';
import 'package:sistrum/utils/logging/logger.dart';

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
  const LrcSidecarStore({this.publish});
  final Future<void> Function(File staged, String target)? publish;

  Future<LrcSidecarResult> write(
    String audioPath,
    String text, {
    required bool replace,
  }) async {
    if (audioPath.startsWith('content://')) {
      return const LrcSidecarResult(LrcSidecarOutcome.unsupported);
    }
    final target = lrcSidecarPath(audioPath);
    Directory? staging;
    var claimed = false;
    var published = false;
    try {
      // Stage on the same filesystem: a failed write cannot truncate the old
      // sidecar. Exclusive creation is the no-replace claim, not exists()+write.
      staging = await Directory(p.dirname(target)).createTemp('.lyrics-');
      final staged = await File(
        p.join(staging.path, 'new.lrc'),
      ).writeAsString(text, flush: true);
      if (!replace) {
        try {
          await File(target).create(exclusive: true);
          claimed = true;
        } on FileSystemException {
          if (await FileSystemEntity.type(target, followLinks: false) !=
              FileSystemEntityType.notFound) {
            return const LrcSidecarResult(LrcSidecarOutcome.exists);
          }
          rethrow;
        }
      }
      if (publish != null) {
        await publish!(staged, target);
      } else {
        await staged.rename(target);
      }
      published = true;
      return LrcSidecarResult(LrcSidecarOutcome.saved, path: target);
    } on FileSystemException {
      return const LrcSidecarResult(LrcSidecarOutcome.failed);
    } finally {
      if (claimed && !published) {
        try {
          // Only remove our empty reservation, never somebody else's content.
          if (await File(target).length() == 0) {
            await deleteBestEffort(File(target));
          }
        } on FileSystemException {
          /* Publication may already have removed it. */
        }
      }
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException catch (error) {
          AppLogger('LyricsSidecar').w('Staging cleanup failed: $error');
        }
      }
    }
  }
}
