class LyricWord {
  final Duration time;
  final Duration? end;
  final String text;

  const LyricWord({required this.time, this.end, required this.text});
}

class LyricVoice {
  final String id;
  final int index;
  final bool isGroup;

  const LyricVoice({
    required this.id,
    required this.index,
    this.isGroup = false,
  });
}

class LyricLine {
  final Duration time;
  final Duration? end;
  final String text;
  final List<LyricWord> words;
  final String? romanization;
  final List<LyricWord> romanizationWords;
  final String? translation;
  final LyricVoice? voice;
  final bool isBackground;

  /// Links backing vocals to their lead even when another singer overlaps.
  final int? vocalGroup;

  const LyricLine({
    required this.time,
    this.end,
    required this.text,
    this.words = const [],
    this.romanization,
    this.romanizationWords = const [],
    this.translation,
    this.voice,
    this.isBackground = false,
    this.vocalGroup,
  });

  bool get hasWordTiming => words.isNotEmpty;
}

class ParsedLyrics {
  final bool synced;
  final bool wordSynced;
  final List<LyricLine> lines;
  final String plainText;
  final String? writers;
  final String? provider;

  const ParsedLyrics({
    required this.synced,
    required this.wordSynced,
    required this.lines,
    required this.plainText,
    this.writers,
    this.provider,
  });

  bool get isEmpty => lines.isEmpty && plainText.trim().isEmpty;

  static const ParsedLyrics empty = ParsedLyrics(
    synced: false,
    wordSynced: false,
    lines: [],
    plainText: '',
  );
}
