import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/lyrics/embedded_lyrics_writer.dart';
import 'package:sistrum/services/lyrics/lyrics_timing_store.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

/// The user's answers during a Fetch lyrics run. Each question is asked only
/// at the point it matters, and nothing is written before a result exists.
abstract interface class LyricsFetchPrompts {
  /// The file already has lyrics. True replaces them.
  Future<bool> confirmReplaceExisting();

  /// No synced lyrics were found. True continues with plain-text sources.
  Future<bool> confirmPlainLyrics();
}

enum LyricsFetchOutcome {
  /// Lyrics were found and written into the file.
  saved,

  /// The file had lyrics and the user kept them.
  keptExisting,

  /// No synced lyrics were found and the user did not want plain text.
  declinedPlain,

  /// Neither synced nor plain lyrics were found.
  notFound,

  /// The user cancelled while the search ran.
  cancelled,

  /// Lyrics were found but the file could not be written.
  writeFailed,
}

class LyricsFetchReport {
  const LyricsFetchReport({
    required this.outcome,
    this.provider,
    this.timing,
    this.failedProviders = const [],
    this.writeFailure,
  });

  final LyricsFetchOutcome outcome;
  final String? provider;
  final LyricsTiming? timing;

  /// Sources that could not be reached. Shown so an outage is not mistaken
  /// for a song without lyrics.
  final List<String> failedProviders;
  final Object? writeFailure;
}

/// Runs one Fetch lyrics action: check the file, search in stages, ask before
/// replacing or using plain text, then write the lyrics into the file.
class LyricsFetchController {
  LyricsFetchController({
    required this.search,
    required this.store,
    required this.prompts,
    required this.timings,
  });

  /// Built fresh for each run, so the synced and plain steps share requests.
  final OnlineLyricsSearch Function() search;
  final EmbeddedLyricsStore store;
  final LyricsFetchPrompts prompts;
  final LyricsTimingState timings;

  Future<LyricsFetchReport> run(
    LocalLibraryItem item, {
    bool Function()? isCancelled,
  }) async {
    final existing = await store.existingLyrics(item);
    if (existing.trim().isNotEmpty) {
      if (!await prompts.confirmReplaceExisting()) {
        return const LyricsFetchReport(
          outcome: LyricsFetchOutcome.keptExisting,
        );
      }
    }

    final query = OnlineLyricsQuery(
      title: item.trackName,
      artist: item.artistName,
      album: item.albumName,
      durationSeconds: item.duration?.toDouble(),
      isrc: item.isrc,
    );
    final run = search();

    final failed = <String>{};
    var result = await run.findSynced(query, isCancelled: isCancelled);
    failed.addAll(result.failedProviders);
    if (result.outcome == OnlineLyricsOutcome.cancelled) {
      return _report(LyricsFetchOutcome.cancelled, failed);
    }
    if (!result.found) {
      if (!await prompts.confirmPlainLyrics()) {
        return _report(LyricsFetchOutcome.declinedPlain, failed);
      }
      result = await run.findPlain(query, isCancelled: isCancelled);
      failed.addAll(result.failedProviders);
      if (result.outcome == OnlineLyricsOutcome.cancelled) {
        return _report(LyricsFetchOutcome.cancelled, failed);
      }
      if (!result.found) {
        return _report(LyricsFetchOutcome.notFound, failed);
      }
    }

    final candidate = result.candidate!;
    final written = await store.write(item, candidate.text);
    if (!written.saved) {
      return LyricsFetchReport(
        outcome: LyricsFetchOutcome.writeFailed,
        provider: candidate.provider,
        timing: candidate.timing,
        failedProviders: failed.toList(),
        writeFailure: written.failure,
      );
    }
    await timings.put(
      item.id,
      LyricsTimingRecord(
        fingerprint: lyricsFingerprint(item.filePath, item.fileModTime),
        timing: candidate.timing,
      ),
    );
    return LyricsFetchReport(
      outcome: LyricsFetchOutcome.saved,
      provider: candidate.provider,
      timing: candidate.timing,
      failedProviders: failed.toList(),
    );
  }

  static LyricsFetchReport _report(
    LyricsFetchOutcome outcome,
    Set<String> failed,
  ) => LyricsFetchReport(outcome: outcome, failedProviders: failed.toList());
}
