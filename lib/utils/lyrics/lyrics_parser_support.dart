part of 'lyrics_parser.dart';

class _LyricsParserSupport {
  static (String, LyricVoice?) _vocalText(String content) {
    final match = LyricsParser._voicePrefix.firstMatch(content);
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

  static bool _hasUsableTiming(List<LyricLine> lines) {
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.text.trim().isEmpty ||
          (i == lines.length - 1 &&
              LyricsParser._writerCredit.hasMatch(line.text.trim()))) {
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
      final trailer = LyricsParser._writerCredit.firstMatch(
        lines.last.text.trim(),
      );
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
            (plain) => LyricsParser._writerCredit.hasMatch(plain.trim()),
          );
        }
        if (index >= 0) plainLines.removeAt(index);
        plainText = plainLines.join('\n');
      }
    } else {
      // Untimed provider results also keep the optional writer footer.
      final plainLines = plainText.split('\n');
      final trailer = LyricsParser._writerCredit.firstMatch(
        plainLines.last.trim(),
      );
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

      final background = LyricsParser._backgroundLine.firstMatch(line.trim());
      if (background != null) line = background.group(1)!.trim();

      final supplement = LyricsParser._supplementTag.firstMatch(line.trim());
      if (supplement != null) {
        final time = int.tryParse(supplement.group(2)!);
        try {
          final value = utf8.decode(base64.decode(supplement.group(3)!)).trim();
          if (time != null && value.isNotEmpty) {
            final kind = supplement.group(1)!.toLowerCase();
            if (kind == 'romaji-words') {
              final words = _LyricsParserWords._parseRomanizationWords(value);
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
      final idMatch = LyricsParser._idTag.firstMatch(line.trim());
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

      final timeMatches = LyricsParser._lineTimeTag.allMatches(line).toList();
      if (timeMatches.isEmpty) {
        final (content, voice) = _vocalText(line.trim());
        final clean = content.replaceAll(LyricsParser._wordTimeTag, '').trim();
        plainBuffer.add(clean);
        if (background != null && parsed.isNotEmpty && clean.isNotEmpty) {
          final words = _LyricsParserWords._parseWords(content);
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
      final parsedWords = _LyricsParserWords._parseWords(content);
      if (parsedWords.length > LyricsParser._maxWordsPerLine) {
        words = parsedWords.sublist(0, LyricsParser._maxWordsPerLine);
      } else {
        words = parsedWords;
      }
      sawWordTiming |= words.isNotEmpty;
      final cleanContent = content
          .replaceAll(LyricsParser._wordTimeTag, '')
          .trim();
      plainBuffer.add(cleanContent);

      // A line can have multiple timestamps (repeated chorus). The word
      // timing belongs to the occurrence nearest the first word; repeated
      // occurrences replay the same relative timing (BUG-103).
      times = timeMatches.length > LyricsParser._maxLineTimestamps
          ? timeMatches.sublist(0, LyricsParser._maxLineTimestamps)
          : timeMatches;
      final anchorMs = words.isEmpty
          ? null
          : _LyricsParserWords._nearestOccurrence(
              times,
              words.first.time.inMilliseconds,
            );
      // Every occurrence of the line duplicates the same content, so the
      // expansion cost is computed once and charged per pushed occurrence.
      final cost = _LyricsParserWords._expandedCost(cleanContent, words);
      var occurrences = 0;
      for (final RegExpMatch tm in times) {
        final d = _toDuration(tm.group(1), tm.group(2), tm.group(3));
        if (d == null) continue;
        final deltaMs = anchorMs == null ? 0 : d.inMilliseconds - anchorMs;
        final occurrenceWords = deltaMs == 0 || words.isEmpty
            ? words
            : _LyricsParserWords._shiftWordTimes(words, deltaMs);
        occurrences++;
        if (occurrences > 1 &&
            expandedUnits + cost > LyricsParser._maxExpandedUnits) {
          break;
        }
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
              time: _LyricsParserWords._shift(l.time, offsetMs),
              end: l.end == null
                  ? null
                  : _LyricsParserWords._shift(l.end!, offsetMs),
              text: l.text,
              voice: l.voice,
              isBackground: l.isBackground,
              vocalGroup: l.vocalGroup,
              romanization: romanization,
              romanizationWords: _LyricsParserWords._shiftWords(
                validWords,
                offsetMs,
              ),
              translation: alignedTranslation[l.time.inMilliseconds],
              words: _LyricsParserWords._shiftWords(l.words, offsetMs),
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

  static void _sortLines(List<LyricLine> lines) {
    // Simultaneous singers retain their document order.
    final order = {for (var i = 0; i < lines.length; i++) lines[i]: i};
    lines.sort((a, b) {
      final timing = a.time.compareTo(b.time);
      return timing != 0 ? timing : order[a]!.compareTo(order[b]!);
    });
  }
}
