import 'dart:async';

/// How precisely a lyrics text is timed. Ordered from best to worst so the
/// results can be grouped in that order.
enum LyricsTiming {
  wordSynced,
  lineSynced,
  plain;

  /// Classifies a stored lyrics text from its own timing tags, never from the
  /// name of the provider that returned it.
  static LyricsTiming detect(String text) {
    if (_wordTag.hasMatch(text)) return LyricsTiming.wordSynced;
    if (_lineTag.hasMatch(text)) return LyricsTiming.lineSynced;
    return LyricsTiming.plain;
  }
}

final _wordTag = RegExp(r'<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>');
final _lineTag = RegExp(
  r'^\s*\[\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?\]',
  multiLine: true,
);

/// The song a lookup is for. [durationSeconds] is null when unknown.
class OnlineLyricsQuery {
  const OnlineLyricsQuery({
    required this.title,
    required this.artist,
    this.album,
    this.durationSeconds,
    this.isrc,
  });

  final String title;
  final String artist;
  final String? album;
  final double? durationSeconds;

  /// Recording code when the file carries one; sources use it for exact hits.
  final String? isrc;
}

/// One source's match for the query.
class OnlineLyricsCandidate {
  const OnlineLyricsCandidate({
    required this.provider,
    required this.timing,
    required this.text,
    this.title,
    this.artist,
    this.durationSeconds,
  });

  final String provider;
  final LyricsTiming timing;
  final String text;

  /// The song the source matched. Null when the source does not report it.
  final String? title;
  final String? artist;
  final double? durationSeconds;
}

/// One lyrics source. [find] returns null when the source has no lyrics that
/// match the song. It throws when the source is unreachable, so the search can
/// report that separately from "not found".
abstract class OnlineLyricsProvider {
  String get id;

  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query);
}

class OnlineLyricsSearchResult {
  const OnlineLyricsSearchResult({
    required this.candidates,
    required this.failedProviders,
  });

  /// One match per source that found the song, in source order.
  final List<OnlineLyricsCandidate> candidates;

  /// Sources that could not be reached. Shown so a dead source is not
  /// confused with a song that has no lyrics.
  final List<String> failedProviders;

  /// The matches with [timing], in source order.
  List<OnlineLyricsCandidate> withTiming(LyricsTiming timing) =>
      candidates.where((candidate) => candidate.timing == timing).toList();
}

/// Cancels result delivery. The owner also closes its shared HTTP client.
class LyricsSearchCancellation {
  final _cancelled = Completer<void>();
  bool get isCancelled => _cancelled.isCompleted;
  Future<void> get whenCancelled => _cancelled.future;
  void cancel() {
    if (!isCancelled) _cancelled.complete();
  }
}

/// Asks every source once, in parallel, and exposes stable partial snapshots.
class OnlineLyricsSearch {
  OnlineLyricsSearch(this.providers);
  final List<OnlineLyricsProvider> providers;

  Future<OnlineLyricsSearchResult> searchAll(
    OnlineLyricsQuery query, {
    void Function(OnlineLyricsSearchResult)? onProgress,
    LyricsSearchCancellation? cancellation,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final candidates = <int, OnlineLyricsCandidate>{};
    final failed = <int>{};
    OnlineLyricsSearchResult snapshot() => OnlineLyricsSearchResult(
      candidates: List.unmodifiable([
        for (var i = 0; i < providers.length; i++)
          if (candidates.containsKey(i)) candidates[i]!,
      ]),
      failedProviders: List.unmodifiable([
        for (var i = 0; i < providers.length; i++)
          if (failed.contains(i)) providers[i].id,
      ]),
    );
    await Future.wait([
      for (var i = 0; i < providers.length; i++)
        () async {
          final deadline = Completer<OnlineLyricsCandidate?>();
          final timer = Timer(
            timeout,
            () => deadline.completeError(
              TimeoutException('Lyrics source deadline'),
            ),
          );
          try {
            final result = await Future.any<OnlineLyricsCandidate?>([
              Future.sync(() => providers[i].find(query)),
              deadline.future,
              if (cancellation != null)
                cancellation.whenCancelled.then((_) => null),
            ]);
            if (cancellation?.isCancelled == true) return;
            if (result != null) candidates[i] = result;
          } catch (_) {
            if (cancellation?.isCancelled != true) failed.add(i);
          } finally {
            timer.cancel();
          }
          if (cancellation?.isCancelled != true) onProgress?.call(snapshot());
        }(),
    ]);
    return snapshot();
  }
}
