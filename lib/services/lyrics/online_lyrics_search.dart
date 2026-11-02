import 'dart:async';

/// How precisely a lyrics text is timed. Ordered from best to worst so a
/// stage can ask for "at least this precise".
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

  /// True when this timing is at least as precise as [required].
  bool satisfies(LyricsTiming required) => index <= required.index;
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
  });

  final String title;
  final String artist;
  final String? album;
  final double? durationSeconds;
}

class OnlineLyricsCandidate {
  const OnlineLyricsCandidate({
    required this.provider,
    required this.timing,
    required this.text,
  });

  final String provider;
  final LyricsTiming timing;
  final String text;
}

/// One lyrics source. [find] returns null when the source has no lyrics that
/// match the song. It throws when the source is unreachable, so the search can
/// report that separately from "not found".
abstract class OnlineLyricsProvider {
  String get id;

  /// The best timing this provider is known to return. Used only to decide
  /// which stage to query it in; the result's own timing is what counts.
  LyricsTiming get bestTiming;

  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query);
}

enum OnlineLyricsOutcome { found, notFound, cancelled }

class OnlineLyricsResult {
  const OnlineLyricsResult._(
    this.outcome,
    this.candidate,
    this.failedProviders,
  );

  final OnlineLyricsOutcome outcome;
  final OnlineLyricsCandidate? candidate;

  /// Providers that threw. Reported to the user so a dead source is not
  /// confused with a song that has no lyrics.
  final List<String> failedProviders;

  bool get found => outcome == OnlineLyricsOutcome.found;
}

/// Runs the staged search. Each stage asks its providers in order and accepts
/// the first result that is precise enough for that stage. A result that is
/// less precise is kept as a fallback, and the search moves on to the next
/// stage. Every provider is asked at most once per run.
class OnlineLyricsSearch {
  OnlineLyricsSearch(this.providers);

  final List<OnlineLyricsProvider> providers;

  /// Stages in order: word-synced, then line-synced. Plain text is a separate
  /// step that only runs after the user agrees, so it is not included here.
  Future<OnlineLyricsResult> findSynced(
    OnlineLyricsQuery query, {
    bool Function()? isCancelled,
  }) => _run(
    query,
    stages: const [LyricsTiming.wordSynced, LyricsTiming.lineSynced],
    isCancelled: isCancelled,
  );

  /// Plain-text search. Providers are tried in the same order.
  Future<OnlineLyricsResult> findPlain(
    OnlineLyricsQuery query, {
    bool Function()? isCancelled,
  }) =>
      _run(query, stages: const [LyricsTiming.plain], isCancelled: isCancelled);

  Future<OnlineLyricsResult> _run(
    OnlineLyricsQuery query, {
    required List<LyricsTiming> stages,
    bool Function()? isCancelled,
  }) async {
    final failed = <String>[];
    // Each provider's answer is fetched once and reused by later stages.
    final asked = <String, OnlineLyricsCandidate?>{};

    for (final stage in stages) {
      for (final provider in providers) {
        if (isCancelled?.call() ?? false) {
          return OnlineLyricsResult._(
            OnlineLyricsOutcome.cancelled,
            null,
            failed,
          );
        }
        // A source whose best output is less precise than this stage cannot
        // satisfy it, so it is not asked for this stage.
        if (!provider.bestTiming.satisfies(stage)) continue;

        if (!asked.containsKey(provider.id)) {
          try {
            asked[provider.id] = await provider.find(query);
          } catch (_) {
            failed.add(provider.id);
            asked[provider.id] = null;
          }
        }
        final result = asked[provider.id];
        if (result != null && result.timing.satisfies(stage)) {
          return OnlineLyricsResult._(
            OnlineLyricsOutcome.found,
            result,
            failed,
          );
        }
      }
    }
    return OnlineLyricsResult._(OnlineLyricsOutcome.notFound, null, failed);
  }
}
