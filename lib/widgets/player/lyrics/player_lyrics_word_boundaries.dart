part of 'player_lyrics.dart';

/// The next lead line or countdown after [index]; backing parts and singers
/// starting together do not end a line.
Duration? _nextBoundary(List<LyricLine> lines, int index) {
  final start = lines[index].time;
  for (var i = index + 1; i < lines.length; i++) {
    final line = lines[i];
    if (!line.isBackground && line.time > start) return line.time;
  }
  return null;
}

Duration _estimatedFinalWordEnd(
  List<LyricWord> words,
  Duration? next,
  Duration nearGap,
) {
  final start = words.last.time;
  final paces = <int>[
    for (var i = 0; i + 1 < words.length; i++)
      ((words[i].end ?? words[i + 1].time) - words[i].time).inMilliseconds,
  ].where((value) => value > 0).toList()..sort();
  final pace = paces.isEmpty ? 600 : paces[paces.length ~/ 2];
  // A final word is usually held longer than the line's typical syllable.
  final estimate =
      start + Duration(milliseconds: (pace * 2.5).clamp(700, 3000).round());
  if (next == null) return estimate;
  if (next <= start) {
    return start + Duration(milliseconds: pace.clamp(150, 400));
  }
  if (next - start <= nearGap) return next;
  return estimate;
}
