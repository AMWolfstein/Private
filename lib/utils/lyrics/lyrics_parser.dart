import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:xml/xml.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';

part 'lyrics_parser_ttml.dart';

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

class LyricsParser {
  LyricsParser._();

  // Hostile LRC lines repeat timestamps or word tags to amplify per-line
  // clones (RUST-403: one crafted line can request hundreds of GiB of
  // allocations). The caps bound the expanded output on both this parser and
  // the native one so their fixtures stay equal. A legit chorus repeats a few
  // times and word-timed lines stay under a few dozen words, far below these
  // caps.
  static const int _maxLineTimestamps = 64;
  static const int _maxWordsPerLine = 256;

  /// Weighted expanded-output budget per parse (word counts plus the UTF-16
  /// text length of every duplicated line) in code-unit units.
  static const int _maxExpandedUnits = 16 * 1024 * 1024;

  // [mm:ss.xx] or [mm:ss.xxx] or [mm:ss]
  static final RegExp _lineTimeTag = RegExp(
    r'\[(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?\]',
  );

  // <mm:ss.xx> inline word timestamp (enhanced LRC).
  static final RegExp _wordTimeTag = RegExp(
    r'<(\d{1,3}):(\d{1,2})(?:[.:](\d{1,3}))?>',
  );
  static final RegExp _voicePrefix = RegExp(
    r'^(\s*(?:<\d{1,3}:\d{1,2}(?:[.:]\d{1,3})?>\s*)*)(v[1-9]\d*):[ \t]*',
    caseSensitive: false,
  );
  static final RegExp _backgroundLine = RegExp(
    r'^\[bg:(.*)\]$',
    caseSensitive: false,
  );

  static (String, LyricVoice?) _vocalText(String content) {
    final match = _voicePrefix.firstMatch(content);
    if (match == null) return (content, null);
    final id = match.group(2)!.toLowerCase();
    final number = int.tryParse(id.substring(1));
    return (
      content.replaceRange(
        0,
        match.end,
        match.group(1)!.replaceAll(RegExp(r'\s+'), ''),
      ),
      LyricVoice(id: id, index: (number ?? 1) - 1, isGroup: id == 'v3'),
    );
  }

  // ID tags such as [ti:..], [ar:..], [offset:..].
  static final RegExp _idTag = RegExp(
    r'^\[(ti|ar|al|by|offset|length|re|ve|tool|au|la|encoder|instrumental|x-[a-z0-9_-]+):.*\]$',
    caseSensitive: false,
  );
  static final RegExp _supplementTag = RegExp(
    r'^\[x-(romaji-words|romaji|translation):(\d+):([^\]]*)\]$',
    caseSensitive: false,
  );
  static final RegExp _writerCredit = RegExp(
    r'^Written\s+by\s*:\s*(.+)$',
    caseSensitive: false,
  );

  static bool _hasUsableTiming(List<LyricLine> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.text.trim().isEmpty ||
          (i == lines.length - 1 && _writerCredit.hasMatch(line.text.trim()))) {
        continue;
      }
      if (line.time > Duration.zero ||
          (line.end ?? Duration.zero) > Duration.zero ||
          line.words.any(
            (word) =>
                word.text.trim().isNotEmpty &&
                (word.time > Duration.zero ||
                    (word.end ?? Duration.zero) > Duration.zero),
          )) {
        return true;
      }
    }
    return false;
  }

  static ParsedLyrics parse(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return ParsedLyrics.empty;

    if (_looksLikeTtml(text)) {
      final ttml = _parseTtml(text);
      // Untimed TTML keeps its plain lyric text instead of being re-parsed as
      // LRC, which would show the raw XML markup (BUG-101, RUST-401).
      if (ttml != null &&
          (ttml.lines.isNotEmpty || ttml.plainText.trim().isNotEmpty)) {
        return _withCredits(text, ttml);
      }
    }

    return _withCredits(text, _parseLrcOrPlain(text));
  }

  /// Production parsing runs away from rendering. The synchronous parser
  /// remains the compatibility contract for old native builds and test hosts.
  static Future<ParsedLyrics> parseAsyncNative(String? raw) async {
    if (raw == null || raw.isEmpty) return ParsedLyrics.empty;
    Map<String, dynamic> result;
    try {
      final bytes = await compute(_encodeLyricsInBackground, raw);
      result = await NativeDataJobs.run({
        'operation': 'parse_lyrics',
      }, bytes: bytes);
    } on MissingPluginException {
      return compute(_parseLyricsInBackground, raw);
    } on PlatformException catch (error) {
      // Rust bounds its recursive XML tokenizer. The isolated compatibility
      // parser retains support for valid documents beyond that native limit.
      if (error.message?.contains('XML nesting exceeds') != true) rethrow;
      return compute(_parseLyricsInBackground, raw);
    }
    return compute(_hydrateParsedLyricsInBackground, result);
  }

  static ParsedLyrics _withCredits(String raw, ParsedLyrics lyrics) {
    String? tag(String name) => RegExp(
      '^\\[$name:([^\\]\\r\\n]*)\\]\\s*\$',
      multiLine: true,
      caseSensitive: false,
    ).firstMatch(raw)?.group(1)?.trim();
    var writers = tag('au');
    var provider = tag('x-provider');
    final credit = tag('by') ?? '';
    provider ??= RegExp(r'\bvia\s+([^\(]+)', caseSensitive: false)
        .firstMatch(credit)
        ?.group(1)
        ?.trim()
        .replaceFirst(RegExp(r'\s+API$', caseSensitive: false), '');
    provider ??= RegExp(
      r'\(source:\s*([^\)]+)\)',
      caseSensitive: false,
    ).firstMatch(credit)?.group(1)?.trim();
    provider = provider?.replaceFirst(
      RegExp(r'^extension:', caseSensitive: false),
      '',
    );
    if (_looksLikeTtml(raw)) {
      try {
        final doc = XmlDocument.parse(raw);
        final names = doc.descendants
            .whereType<XmlElement>()
            .where((node) => node.name.local == 'songwriter')
            .map((node) => node.innerText.trim())
            .where((name) => name.isNotEmpty)
            .toSet();
        if (names.isNotEmpty) writers = names.join(', ');
      } on XmlParserException {
        // Malformed optional credits must not prevent lyric playback.
      }
    }
    var lines = lyrics.lines;
    var plainText = lyrics.plainText;
    if (lines.isNotEmpty) {
      final trailer = _writerCredit.firstMatch(lines.last.text.trim());
      if (trailer != null) {
        writers ??= trailer.group(1)?.trim();
        // Drop the popped credit from the retained plain text instead of
        // rebuilding it from lines, which duplicates chorus lines shared by
        // timestamps (BUG-102). Match the popped credit's text first so
        // multi-credit files keep the rows their lines retained.
        final creditText = lines.last.text.trim();
        lines = lines.sublist(0, lines.length - 1);
        final plainLines = plainText.split('\n');
        var index = plainLines.lastIndexWhere(
          (plain) => plain.trim() == creditText,
        );
        if (index < 0) {
          index = plainLines.lastIndexWhere(
            (plain) => _writerCredit.hasMatch(plain.trim()),
          );
        }
        if (index >= 0) plainLines.removeAt(index);
        plainText = plainLines.join('\n');
      }
    } else {
      // Untimed provider results also keep the optional writer footer.
      final plainLines = plainText.split('\n');
      final trailer = _writerCredit.firstMatch(plainLines.last.trim());
      if (trailer != null) {
        writers ??= trailer.group(1)?.trim();
        plainText = plainLines.take(plainLines.length - 1).join('\n');
      }
    }
    return ParsedLyrics(
      synced: lyrics.synced,
      wordSynced: lyrics.wordSynced,
      lines: lyrics.synced ? lines : const [],
      plainText: plainText,
      writers: writers?.isNotEmpty == true ? writers : null,
      provider: provider?.isNotEmpty == true ? provider : null,
    );
  }

  static bool _looksLikeTtml(String text) {
    final head = text.trimLeft();
    return head.startsWith('<?xml') ||
        head.startsWith('<tt') ||
        head.contains('<tt ') ||
        head.contains('http://www.w3.org/ns/ttml');
  }

  static Duration? _toDuration(String? min, String? sec, String? frac) {
    if (min == null || sec == null) return null;
    final m = int.tryParse(min) ?? 0;
    final s = int.tryParse(sec) ?? 0;
    var ms = 0;
    if (frac != null && frac.isNotEmpty) {
      // Normalize to milliseconds regardless of 2 or 3 digit fractions.
      final padded = frac.padRight(3, '0').substring(0, 3);
      ms = int.tryParse(padded) ?? 0;
    }
    return Duration(minutes: m, seconds: s, milliseconds: ms);
  }

  static ParsedLyrics _parseLrcOrPlain(String text) {
    final rawLines = text.split(RegExp(r'\r\n|\r|\n'));
    final parsed = <LyricLine>[];
    final plainBuffer = <String>[];
    final romanization = <int, String>{};
    final romanizationWords = <int, List<LyricWord>>{};
    final translation = <int, String>{};
    var sawTimestamp = false;
    var sawWordTiming = false;
    var offsetMs = 0;
    var expandedUnits = 0;
    List<RegExpMatch> times;
    List<LyricWord> words;

    for (final rawLine in rawLines) {
      var line = rawLine.trimRight();
      if (line.trim().isEmpty) continue;

      final background = _backgroundLine.firstMatch(line.trim());
      if (background != null) line = background.group(1)!.trim();

      final supplement = _supplementTag.firstMatch(line.trim());
      if (supplement != null) {
        final time = int.tryParse(supplement.group(2)!);
        try {
          final value = utf8.decode(base64.decode(supplement.group(3)!)).trim();
          if (time != null && value.isNotEmpty) {
            final kind = supplement.group(1)!.toLowerCase();
            if (kind == 'romaji-words') {
              final words = _parseRomanizationWords(value);
              if (words.isNotEmpty) {
                romanizationWords.putIfAbsent(time, () => words);
              }
            } else {
              final target = kind == 'romaji' ? romanization : translation;
              target.putIfAbsent(time, () => value);
            }
          }
        } on FormatException {
          // Optional corrupt metadata must not hide the original lyrics.
        }
        continue;
      }

      // Capture [offset:] for timing correction, drop other ID tags.
      final idMatch = _idTag.firstMatch(line.trim());
      if (idMatch != null) {
        final key = idMatch.group(1)!.toLowerCase();
        if (key == 'offset') {
          final value = line
              .substring(line.indexOf(':') + 1)
              .replaceAll(']', '')
              .trim();
          offsetMs = int.tryParse(value) ?? 0;
        }
        continue;
      }

      final timeMatches = _lineTimeTag.allMatches(line).toList();
      if (timeMatches.isEmpty) {
        final (content, voice) = _vocalText(line.trim());
        final clean = content.replaceAll(_wordTimeTag, '').trim();
        plainBuffer.add(clean);
        if (background != null && parsed.isNotEmpty && clean.isNotEmpty) {
          final words = _parseWords(content);
          final previous = parsed.last;
          parsed.add(
            LyricLine(
              time: words.firstOrNull?.time ?? previous.time,
              end: words.lastOrNull?.end ?? previous.end,
              text: clean,
              words: words,
              voice: voice ?? previous.voice,
              isBackground: true,
              vocalGroup: previous.vocalGroup,
            ),
          );
          sawWordTiming |= words.isNotEmpty;
        }
        continue;
      }

      sawTimestamp = true;

      // Strip leading line timestamps to obtain the lyric content.
      final lastTag = timeMatches.last;
      final (content, voice) = _vocalText(line.substring(lastTag.end).trim());

      // Enhanced LRC word timestamps inside the content.
      final parsedWords = _parseWords(content);
      if (parsedWords.length > _maxWordsPerLine) {
        words = parsedWords.sublist(0, _maxWordsPerLine);
      } else {
        words = parsedWords;
      }
      sawWordTiming |= words.isNotEmpty;
      final cleanContent = content.replaceAll(_wordTimeTag, '').trim();
      plainBuffer.add(cleanContent);

      // A line can have multiple timestamps (repeated chorus). The word
      // timing belongs to the occurrence nearest the first word; repeated
      // occurrences replay the same relative timing (BUG-103).
      times = timeMatches.length > _maxLineTimestamps
          ? timeMatches.sublist(0, _maxLineTimestamps)
          : timeMatches;
      final anchorMs = words.isEmpty
          ? null
          : _nearestOccurrence(times, words.first.time.inMilliseconds);
      // Every occurrence of the line duplicates the same content, so the
      // expansion cost is computed once and charged per pushed occurrence.
      final cost = _expandedCost(cleanContent, words);
      var occurrences = 0;
      for (final RegExpMatch tm in times) {
        final d = _toDuration(tm.group(1), tm.group(2), tm.group(3));
        if (d == null) continue;
        final deltaMs = anchorMs == null ? 0 : d.inMilliseconds - anchorMs;
        final occurrenceWords = deltaMs == 0 || words.isEmpty
            ? words
            : _shiftWordTimes(words, deltaMs);
        occurrences++;
        if (occurrences > 1 && expandedUnits + cost > _maxExpandedUnits) break;
        expandedUnits += cost;
        parsed.add(
          LyricLine(
            time: d,
            end: occurrenceWords.lastOrNull?.end,
            text: cleanContent,
            words: occurrenceWords,
            voice:
                voice ?? (background != null ? parsed.lastOrNull?.voice : null),
            isBackground: background != null,
            vocalGroup: background != null
                ? parsed.lastOrNull?.vocalGroup
                : parsed.length,
          ),
        );
      }
    }

    if (!sawTimestamp) {
      // Pure plain text.
      return ParsedLyrics(
        synced: false,
        wordSynced: false,
        lines: const [],
        plainText: plainBuffer.where((l) => l.isNotEmpty).join('\n'),
      );
    }

    // Providers can put [00:00.00] on every plain-text row. Check the source
    // before applying offsets, which must not manufacture usable timing.
    final synced = _hasUsableTiming(parsed);
    _sortLines(parsed);
    final alignedRomanization = _alignSupplements(parsed, romanization);
    final alignedRomanizationWords = _alignSupplements(
      parsed,
      romanizationWords,
    );
    final alignedTranslation = _alignSupplements(parsed, translation);

    final adjusted =
        offsetMs == 0 &&
            alignedRomanization.isEmpty &&
            alignedTranslation.isEmpty
        ? parsed
        : parsed.map((l) {
            final romanization = alignedRomanization[l.time.inMilliseconds];
            final words =
                alignedRomanizationWords[l.time.inMilliseconds] ??
                const <LyricWord>[];
            // Keep readable text when optional timings are incomplete or
            // belong to a different revision of the transliteration.
            final validWords =
                words.map((word) => word.text).join() == romanization
                ? words
                : const <LyricWord>[];
            return LyricLine(
              time: _shift(l.time, offsetMs),
              end: l.end == null ? null : _shift(l.end!, offsetMs),
              text: l.text,
              voice: l.voice,
              isBackground: l.isBackground,
              vocalGroup: l.vocalGroup,
              romanization: romanization,
              romanizationWords: _shiftWords(validWords, offsetMs),
              translation: alignedTranslation[l.time.inMilliseconds],
              words: _shiftWords(l.words, offsetMs),
            );
          }).toList();

    return ParsedLyrics(
      synced: synced,
      wordSynced: synced && sawWordTiming,
      lines: adjusted,
      plainText: plainBuffer.where((l) => l.isNotEmpty).join('\n'),
    );
  }

  /// Older files may have centisecond line times alongside millisecond
  /// supplement times. Resolve each supplement to one nearest line, keeping
  /// exact matches when multiple metadata entries compete for that line.
  static Map<int, T> _alignSupplements<T>(
    List<LyricLine> lines,
    Map<int, T> supplements,
  ) {
    final matched = <int, (int, T)>{};
    for (final entry in supplements.entries) {
      var lo = 0;
      var hi = lines.length;
      while (lo < hi) {
        final mid = (lo + hi) >> 1;
        if (lines[mid].time.inMilliseconds < entry.key) {
          lo = mid + 1;
        } else {
          hi = mid;
        }
      }
      int? nearest;
      var distance = 11;
      for (final index in [lo - 1, lo]) {
        if (index < 0 || index >= lines.length) continue;
        final time = lines[index].time.inMilliseconds;
        final delta = (time - entry.key).abs();
        if (delta < distance) {
          nearest = time;
          distance = delta;
        }
      }
      if (nearest == null) continue;
      final previous = matched[nearest];
      if (previous == null || distance < previous.$1) {
        matched[nearest] = (distance, entry.value);
      }
    }
    return matched.map((time, match) => MapEntry(time, match.$2));
  }

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
    final matches = _wordTimeTag.allMatches(content).toList();
    if (matches.isEmpty) return const [];

    final words = <LyricWord>[];
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final d = _toDuration(m.group(1), m.group(2), m.group(3));
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

  // The word timing belongs to the occurrence nearest the first word;
  // repeated occurrences replay the same relative timing (BUG-103).
  static int? _nearestOccurrence(List<RegExpMatch> matches, int target) {
    int? nearest;
    var distance = -1;
    for (final RegExpMatch match in matches.take(_maxLineTimestamps)) {
      final d = _toDuration(match.group(1), match.group(2), match.group(3));
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

  static int activeIndex(List<LyricLine> lines, Duration position) {
    if (lines.isEmpty) return -1;
    var lo = 0;
    var hi = lines.length - 1;
    var result = -1;
    while (lo <= hi) {
      final mid = (lo + hi) >> 1;
      if (lines[mid].time <= position) {
        result = mid;
        lo = mid + 1;
      } else {
        hi = mid - 1;
      }
    }
    return result;
  }

  static void _sortLines(List<LyricLine> lines) {
    // Simultaneous singers retain their document order.
    final order = {for (var i = 0; i < lines.length; i++) lines[i]: i};
    lines.sort((a, b) {
      final timing = a.time.compareTo(b.time);
      return timing != 0 ? timing : order[a]!.compareTo(order[b]!);
    });
  }
}
