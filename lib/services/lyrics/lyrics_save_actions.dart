import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/lyrics/embedded_lyrics_writer.dart';
import 'package:sistrum/services/lyrics/lrc_sidecar_store.dart';
import 'package:sistrum/services/lyrics/lyrics_timing_store.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

enum LyricsSaveOutcome {
  /// The lyrics were written.
  saved,

  /// The song already had lyrics or a .lrc file and the user kept it.
  keptExisting,

  /// The song is not a plain file path, so no .lrc file can sit beside it.
  unsupported,

  /// The write failed.
  failed,
}

/// Saves one chosen lyrics result from the Find lyrics screen. Nothing is
/// written before the user picks a result, and an existing lyrics text or
/// .lrc file is replaced only after [confirmReplace] returns true.
class LyricsSaveActions {
  LyricsSaveActions({
    required this.embedded,
    required this.sidecar,
    required this.timings,
  });

  final EmbeddedLyricsStore embedded;
  final LrcSidecarStore sidecar;
  final LyricsTimingState timings;

  /// Writes the lyrics into the song's own file and records their timing.
  Future<LyricsSaveOutcome> embed(
    LocalLibraryItem item,
    OnlineLyricsCandidate candidate, {
    required Future<bool> Function() confirmReplace,
  }) async {
    try {
      final existing = await embedded.existingLyrics(item);
      if (existing.trim().isNotEmpty && !await confirmReplace()) {
        return LyricsSaveOutcome.keptExisting;
      }
      final written = await embedded.write(item, candidate.text);
      if (!written.saved) return LyricsSaveOutcome.failed;
    } catch (error) {
      AppLogger('LyricsSave').w('Lyrics file save failed: $error');
      return LyricsSaveOutcome.failed;
    }
    // The file has been saved. A cache failure must not turn this into a
    // failed file operation or cause the user to write the audio file twice.
    try {
      await timings.put(
        item.id,
        LyricsTimingRecord(
          fingerprint: lyricsFingerprint(item.filePath, item.fileModTime),
          timing: LyricsTiming.detect(candidate.text),
        ),
      );
    } catch (error) {
      AppLogger(
        'LyricsSave',
      ).w('Lyrics saved; timing cache update failed: $error');
    }
    return LyricsSaveOutcome.saved;
  }

  /// Writes the lyrics to a .lrc file beside the audio file. The file's own
  /// tags are not touched.
  Future<LyricsSaveOutcome> downloadLrc(
    LocalLibraryItem item,
    OnlineLyricsCandidate candidate, {
    required Future<bool> Function() confirmReplace,
  }) async {
    var result = await sidecar.write(
      item.filePath,
      candidate.text,
      replace: false,
    );
    if (result.outcome == LrcSidecarOutcome.exists) {
      if (!await confirmReplace()) return LyricsSaveOutcome.keptExisting;
      result = await sidecar.write(
        item.filePath,
        candidate.text,
        replace: true,
      );
    }
    return switch (result.outcome) {
      LrcSidecarOutcome.saved => LyricsSaveOutcome.saved,
      LrcSidecarOutcome.unsupported => LyricsSaveOutcome.unsupported,
      LrcSidecarOutcome.exists ||
      LrcSidecarOutcome.failed => LyricsSaveOutcome.failed,
    };
  }
}
