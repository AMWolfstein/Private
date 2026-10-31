part of 'lyrics_parser.dart';

class _LyricsParserWords {
  static List<LyricWord> _parseRomanizationWords(String raw) {
    final value = jsonDecode(raw);
    if (value is! List) return const [];
    final words = <LyricWord>[];
    for (final item in value) {
      if (item case {
        'text': final String text,
        'startTimeMs': final int start,
        'endTimeMs': final int end,
      }) {
        if (text.trim().isEmpty ||
            start < 0 ||
            end < start ||
            (words.isNotEmpty && words.last.time.inMilliseconds > start)) {
          return const [];
        }
        words.add(
          LyricWord(
            time: Duration(milliseconds: start),
            end: Duration(milliseconds: end),
            text: text,
          ),
        );
      } else {
        return const [];
      }
    }
    return words;
  }

  static List<LyricWord> _shiftWords(List<LyricWord> words, int offsetMs) {
    if (offsetMs == 0 || words.isEmpty) return words;
    return words
        .map(
          (word) => LyricWord(
            time: _shift(word.time, offsetMs),
            end: word.end == null ? null : _shift(word.end!, offsetMs),
            text: word.text,
          ),
        )
        .toList(growable: false);
  }

  static Duration _shift(Duration d, int offsetMs) {
    // LRC offset: positive value shifts lyrics earlier.
    final ms = d.inMilliseconds - offsetMs;
    return Duration(milliseconds: ms < 0 ? 0 : ms);
  }

  static List<LyricWord> _parseWords(String content) {
    final matches = LyricsParser._wordTimeTag.allMatches(content).toList();
    if (matches.isEmpty) return const [];

    final words = <LyricWord>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final d = _LyricsParserSupport._toDuration(
        m.group(1),
        m.group(2),
        m.group(3),
      );
      if (d == null) continue;
      final start = m.end;
      final end = i + 1 < matches.length
          ? matches[i + 1].start
          : content.length;
      final word = content.substring(start, end);
      if (word.trim().isEmpty) {
        final previous = words.lastOrNull;
        if (previous != null && previous.end == null && d >= previous.time) {
          words[words.length - 1] = LyricWord(
            time: previous.time,
            end: d,
            text: previous.text,
          );
        }
        continue;
      }
      words.add(LyricWord(time: d, text: word));
    }
    return words;
  }

  static int? _nearestOccurrence(List<RegExpMatch> matches, int target) {
    int? nearest;
    var distance = -1;
    for (final RegExpMatch match in matches.take(
      LyricsParser._maxLineTimestamps,
    )) {
      final d = _LyricsParserSupport._toDuration(
        match.group(1),
        match.group(2),
        match.group(3),
      );
      if (d == null) continue;
      final delta = (d.inMilliseconds - target).abs();
      if (distance < 0 || delta < distance) {
        nearest = d.inMilliseconds;
        distance = delta;
      }
    }
    return nearest;
  }

  static List<LyricWord> _shiftWordTimes(List<LyricWord> words, int deltaMs) {
    int move(int ms) {
      final moved = ms + deltaMs;
      return moved < 0 ? 0 : moved;
    }

    return words
        .map(
          (word) => LyricWord(
            time: Duration(milliseconds: move(word.time.inMilliseconds)),
            end: word.end == null
                ? null
                : Duration(milliseconds: move(word.end!.inMilliseconds)),
            text: word.text,
          ),
        )
        .toList(growable: false);
  }

  static int _expandedCost(String text, List<LyricWord> words) {
    // Weighted expanded-output cost in UTF-16 code units (Dart's String
    // length) so both parsers cap identically on any Unicode input.
    var cost = text.length + words.length * 64;
    for (final word in words) {
      cost += word.text.length;
    }
    return cost;
  }
}
