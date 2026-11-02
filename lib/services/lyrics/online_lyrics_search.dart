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

/// Asks every source once for a query and collects their matches.
class OnlineLyricsSearch {
  OnlineLyricsSearch(this.providers);

  final List<OnlineLyricsProvider> providers;

  /// All sources are asked at the same time. A failing source is listed as
  /// failed and the others still answer.
  Future<OnlineLyricsSearchResult> searchAll(OnlineLyricsQuery query) async {
    final answers = await Future.wait(
      providers.map((provider) async {
        try {
          return (candidate: await provider.find(query), failed: false);
        } catch (_) {
          return (candidate: null, failed: true);
        }
      }),
    );
    final candidates = <OnlineLyricsCandidate>[];
    final failed = <String>[];
    for (var i = 0; i < providers.length; i++) {
      final answer = answers[i];
      if (answer.failed) {
        failed.add(providers[i].id);
      } else if (answer.candidate != null) {
        candidates.add(answer.candidate!);
      }
    }
    return OnlineLyricsSearchResult(
      candidates: candidates,
      failedProviders: failed,
    );
  }
}
