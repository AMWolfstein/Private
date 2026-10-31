part of 'lyrics_parser.dart';

Uint8List _encodeLyricsInBackground(String raw) =>
    Uint8List.fromList(utf8.encode(raw));
ParsedLyrics _parseLyricsInBackground(String raw) => LyricsParser.parse(raw);
ParsedLyrics _hydrateParsedLyricsInBackground(Map<String, dynamic> result) {
  LyricWord word(Map<dynamic, dynamic> value) => LyricWord(
    time: Duration(milliseconds: value['timeMs'] as int),
    end: value['endMs'] == null
        ? null
        : Duration(milliseconds: value['endMs'] as int),
    text: value['text'] as String,
  );
  List<LyricWord> words(dynamic value) => (value as List)
      .map((entry) => word(entry as Map))
      .toList(growable: false);
  final lines = <LyricLine>[];
  for (final value in result['lines'] as List) {
    final row = value as Map;
    final voice = row['voice'] as Map?;
    lines.add(
      LyricLine(
        time: Duration(milliseconds: row['timeMs'] as int),
        end: row['endMs'] == null
            ? null
            : Duration(milliseconds: row['endMs'] as int),
        text: row['text'] as String,
        words: words(row['words']),
        romanization: row['romanization'] as String?,
        romanizationWords: words(row['romanizationWords']),
        translation: row['translation'] as String?,
        voice: voice == null
            ? null
            : LyricVoice(
                id: voice['id'] as String,
                index: voice['index'] as int,
                isGroup: voice['isGroup'] as bool,
              ),
        isBackground: row['isBackground'] as bool,
        vocalGroup: row['vocalGroup'] as int?,
      ),
    );
  }
  return ParsedLyrics(
    synced: result['synced'] as bool,
    wordSynced: result['wordSynced'] as bool,
    lines: lines,
    plainText: result['plainText'] as String,
    writers: result['writers'] as String?,
    provider: result['provider'] as String?,
  );
}
