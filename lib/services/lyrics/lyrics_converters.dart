import 'dart:convert';

import 'package:xml/xml.dart';

/// Turns each source's payload into the LRC text the player already reads:
/// `[mm:ss.xx]` for lines and `<mm:ss.xx>` before each word.
///
/// Every function returns null for a payload with no usable lyrics, so a
/// caller can tell "empty" from "failed to parse" by the exception instead.
class LyricsFormatException implements Exception {
  const LyricsFormatException(this.message);
  final String message;
  @override
  String toString() => 'LyricsFormatException: $message';
}

/// `mm:ss.xx` for a word tag and `[mm:ss.xx]` for a line, matching the
/// upstream formatter: two fraction digits when the millisecond value allows.
String inlineTimestamp(int ms) {
  final clamped = ms < 0 ? 0 : ms;
  final seconds = clamped ~/ 1000;
  final fraction = clamped % 10 == 0
      ? (clamped % 1000 ~/ 10).toString().padLeft(2, '0')
      : (clamped % 1000).toString().padLeft(3, '0');
  final minutes = (seconds ~/ 60).toString().padLeft(2, '0');
  final secs = (seconds % 60).toString().padLeft(2, '0');
  return '$minutes:$secs.$fraction';
}

String lineTimestamp(int ms) => '[${inlineTimestamp(ms)}]';

int? _int(Object? value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value);
  return null;
}

String? _text(Object? value) {
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  return null;
}

/// Mirrors the upstream word appender: a word start is written once even if
/// repeated, a part is joined without a space, and an end time closes the word.
String _appendDetails(List<Map<String, dynamic>> details, bool wordTiming) {
  final out = StringBuffer();
  String lastStart = '';
  for (final detail in details) {
    final text = detail['text'] as String? ?? '';
    final start = _int(detail['timestamp']);
    if (wordTiming && start != null) {
      final tag = '<${inlineTimestamp(start)}>';
      if (tag != lastStart) {
        out.write(tag);
        lastStart = tag;
      }
    }
    out.write(text);
    if (detail['part'] != true) out.write(' ');
    final end = _int(detail['endtime']);
    if (wordTiming && end != null) {
      out.write('<${inlineTimestamp(end)}>');
    }
  }
  return out.toString();
}

/// A line-timed or syllable-timed proxy payload (`content` or `lyrics`).
String formatPaxLines(
  String kind,
  List<Map<String, dynamic>> lines, {
  bool wordTiming = true,
}) {
  final out = <String>[];
  final syllable =
      kind.toLowerCase() == 'syllable' || kind.toLowerCase() == 'word';
  for (final line in lines) {
    final timestamp = _int(line['timestamp']) ?? 0;
    if (syllable) {
      final details =
          (line['text'] as List?)?.whereType<Map<String, dynamic>>().toList() ??
          const <Map<String, dynamic>>[];
      out.add(
        lineTimestamp(timestamp) +
            _appendDetails(details, wordTiming).trimRight(),
      );
    } else {
      final firstList = (line['text'] as List?)
          ?.whereType<Map<String, dynamic>>()
          .toList();
      final text =
          (firstList != null && firstList.isNotEmpty
                  ? firstList.first['text']
                  : null)
              as String? ??
          '';
      if (text.trim().isNotEmpty) out.add('${lineTimestamp(timestamp)}$text');
    }
  }
  return out.join('\n').trim();
}

/// Reads one of the proxy services' JSON responses. A bare JSON string or a
/// plain text body is also accepted, as the upstream parser does.
String parseProxyPayload(String body) {
  final trimmed = body.trim();
  if (trimmed.isEmpty) throw const LyricsFormatException('empty payload');
  if (!trimmed.startsWith('{') &&
      !trimmed.startsWith('[') &&
      !trimmed.startsWith('"')) {
    return trimmed;
  }
  final Object? json;
  try {
    json = jsonDecode(trimmed);
  } on FormatException {
    throw const LyricsFormatException('not JSON');
  }
  if (json is String) {
    final text = _text(json);
    if (text == null) throw const LyricsFormatException('empty lyrics');
    return text;
  }
  if (json is! Map<String, dynamic>) {
    throw const LyricsFormatException('unexpected payload');
  }
  for (final key in const ['lyrics', 'lyric', 'lyrics_text', 'plain_lyrics']) {
    final text = _text(json[key]);
    if (text != null) return text;
  }
  final lyrics = json['lyrics'];
  if (lyrics is List && lyrics.isNotEmpty) {
    final text = formatPaxLines(
      'syllable',
      lyrics.whereType<Map<String, dynamic>>().toList(),
    );
    if (text.isNotEmpty) return text;
  }
  final content = json['content'];
  if (content is List && content.isNotEmpty) {
    final text = formatPaxLines(
      json['type'] as String? ?? 'syllable',
      content.whereType<Map<String, dynamic>>().toList(),
    );
    if (text.isNotEmpty) return text;
  }
  final plain = _text(json['plain_lyrics']);
  if (plain != null) return plain;
  throw const LyricsFormatException('no usable lyrics');
}

/// LyricsPlus (KPOE). Words are kept for `word` and `syllable` kinds; other
/// kinds keep each line's text. Background syllables are dropped, as the
/// upstream does when multi-person output is off.
String formatKpoe(Map<String, dynamic> response, {bool wordTiming = true}) {
  final kind = (response['type'] as String? ?? '').toLowerCase();
  final words = kind == 'word' || kind == 'syllable';
  final lines = response['lyrics'];
  if (lines is! List || lines.isEmpty) {
    throw const LyricsFormatException('no lines');
  }
  final out = <String>[];
  for (final raw in lines.whereType<Map<String, dynamic>>()) {
    final time = (raw['time'] as num?)?.round() ?? 0;
    final stamp = lineTimestamp(time);
    final syllabus =
        (raw['syllabus'] as List?)
            ?.whereType<Map<String, dynamic>>()
            .toList() ??
        const <Map<String, dynamic>>[];
    if (words && wordTiming && syllabus.isNotEmpty) {
      var main = syllabus.where((s) => s['isbackground'] != true).toList();
      if (main.isEmpty) main = syllabus;
      final buffer = StringBuffer(stamp);
      for (final syllable in main) {
        final start = ((syllable['time'] as num?) ?? 0).round();
        buffer.write('<${inlineTimestamp(start)}>${syllable['text'] ?? ''}');
      }
      out.add(buffer.toString());
    } else {
      var text = raw['text'] as String? ?? '';
      if (text.trim().isEmpty && syllabus.isNotEmpty) {
        text = syllabus.map((s) => s['text'] as String? ?? '').join();
      }
      if (text.trim().isNotEmpty) out.add('$stamp${text.trim()}');
    }
  }
  final result = out.join('\n').trim();
  if (result.isEmpty) throw const LyricsFormatException('empty lyrics');
  return result;
}

double _parseTtmlTime(String raw) {
  final value = raw.trim();
  if (value.endsWith('ms')) {
    return double.parse(value.substring(0, value.length - 2)) / 1000;
  }
  if (value.endsWith('s') && !value.contains(':')) {
    return double.parse(value.substring(0, value.length - 1));
  }
  final parts = value.split(':');
  var seconds = 0.0;
  for (final part in parts) {
    seconds = seconds * 60 + double.parse(part);
  }
  return seconds;
}

int _ttmlMs(String? raw) {
  if (raw == null || raw.trim().isEmpty) return -1;
  try {
    return (_parseTtmlTime(raw) * 1000).round();
  } on FormatException {
    return -1;
  }
}

/// Apple-style TTML. Each `<p>` is a line; `<span begin end>` children are
/// words. Background vocals (`ttm:role="x-bg"`) are dropped.
String formatTtml(String document) {
  final XmlDocument xml;
  try {
    xml = XmlDocument.parse(document);
  } on XmlException {
    throw const LyricsFormatException('invalid TTML');
  }
  final out = <String>[];
  for (final p in xml.findAllElements('p')) {
    final begin = _ttmlMs(p.getAttribute('begin'));
    if (begin < 0) continue;
    final spans = p
        .findElements('span')
        .where(
          (span) =>
              span.getAttribute('ttm:role') != 'x-bg' &&
              _ttmlMs(span.getAttribute('begin')) >= 0,
        )
        .toList();
    if (spans.isEmpty) {
      final text = p.innerText.trim();
      if (text.isNotEmpty) out.add('${lineTimestamp(begin)}$text');
      continue;
    }
    final line = StringBuffer(lineTimestamp(begin));
    for (final span in spans) {
      final start = _ttmlMs(span.getAttribute('begin'));
      final word = span.innerText;
      if (word.trim().isEmpty) {
        line.write(' ');
        continue;
      }
      line.write('<${inlineTimestamp(start)}>${word.trim()}');
      // A trailing space after a word separates it from the next one.
      if (word.endsWith(' ')) line.write(' ');
    }
    final text = line.toString().trimRight();
    if (text.isNotEmpty) out.add(text);
  }
  final result = out.join('\n').trim();
  if (result.isEmpty) throw const LyricsFormatException('empty TTML');
  return result;
}

/// Genius lyric pages keep the lyrics in `data-lyrics-container` divs. Text
/// nodes are collected, `<br>` becomes a line break and any element marked
/// `data-exclude-from-selection` is skipped (annotations, buttons).
String extractGeniusLyrics(String html) {
  final sections = <String>[];
  final opener = RegExp(
    r'''<div[^>]*data-lyrics-container="true"[^>]*>''',
    caseSensitive: false,
  );
  for (final match in opener.allMatches(html)) {
    final body = _divBody(html, match.end);
    final text = _plainText(body).replaceAll(' ', ' ').trim();
    if (text.isNotEmpty) sections.add(text);
  }
  if (sections.isEmpty) {
    throw const LyricsFormatException('no lyrics container');
  }
  return sections.join('\n');
}

String _divBody(String html, int start) {
  final tag = RegExp(r'<(/?)div\b[^>]*>', caseSensitive: false);
  var depth = 1;
  for (final match in tag.allMatches(html, start)) {
    if (match.group(1) == '/') {
      depth--;
      if (depth == 0) return html.substring(start, match.start);
    } else {
      depth++;
    }
  }
  return html.substring(start);
}

const _voidTags = {'br', 'img', 'hr', 'input', 'meta', 'link', 'wbr'};

String _plainText(String fragment) {
  final out = StringBuffer();
  final token = RegExp(r'<[^>]+>|[^<]+');
  // Depth of the excluded element being skipped; zero means "keep text".
  var skipDepth = 0;
  for (final match in token.allMatches(fragment)) {
    final piece = match.group(0)!;
    if (!piece.startsWith('<')) {
      if (skipDepth == 0) out.write(_decodeEntities(piece));
      continue;
    }
    final name = RegExp(
      r'^<\/?\s*([a-zA-Z0-9]+)',
    ).firstMatch(piece)?.group(1)?.toLowerCase();
    final closing = piece.startsWith('</');
    final selfClosing = piece.endsWith('/>');
    final isVoid = name != null && _voidTags.contains(name);
    if (skipDepth > 0) {
      if (closing) {
        skipDepth--;
      } else if (!isVoid && !selfClosing) {
        skipDepth++;
      }
      continue;
    }
    if (closing) continue;
    if (piece.contains('data-exclude-from-selection="true"')) {
      if (!isVoid && !selfClosing) skipDepth = 1;
      continue;
    }
    if (name == 'br') out.write('\n');
  }
  return out.toString();
}

String _decodeEntities(String text) => text
    .replaceAllMapped(
      RegExp(r'&#x([0-9a-fA-F]+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!, radix: 16)),
    )
    .replaceAllMapped(
      RegExp(r'&#(\d+);'),
      (m) => String.fromCharCode(int.parse(m.group(1)!)),
    )
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&apos;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&amp;', '&');

/// Decodes a base64 lyric body from QQ Music or Kugou. Returns the text
/// itself when it is already LRC.
String decodeBase64Lyrics(String raw) {
  final trimmed = raw.trim();
  if (trimmed.startsWith('[')) return trimmed;
  try {
    return utf8.decode(base64.decode(trimmed)).trim();
  } on FormatException {
    throw const LyricsFormatException('invalid base64 lyrics');
  }
}
