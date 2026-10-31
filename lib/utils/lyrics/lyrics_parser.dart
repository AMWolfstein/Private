import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:xml/xml.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';

part 'lyrics_parser_support.dart';
part 'lyrics_parser_words.dart';

part 'lyrics_parser_ttml.dart';
part 'lyrics_parser_isolate.dart';

/// Lyrics up to this many characters are UTF-8 encoded on the calling isolate.
const _inlineEncodeChars = 64 * 1024;

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

  static ParsedLyrics parse(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return ParsedLyrics.empty;

    if (_LyricsParserSupport._looksLikeTtml(text)) {
      final ttml = _parseTtml(text);
      // Untimed TTML keeps its plain lyric text instead of being re-parsed as
      // LRC, which would show the raw XML markup (BUG-101, RUST-401).
      if (ttml != null &&
          (ttml.lines.isNotEmpty || ttml.plainText.trim().isNotEmpty)) {
        return _LyricsParserSupport._withCredits(text, ttml);
      }
    }

    return _LyricsParserSupport._withCredits(
      text,
      _LyricsParserSupport._parseLrcOrPlain(text),
    );
  }

  /// Production parsing runs away from rendering. The synchronous parser
  /// remains the compatibility contract for old native builds and test hosts.
  static Future<ParsedLyrics> parseAsyncNative(String? raw) async {
    if (raw == null || raw.isEmpty) return ParsedLyrics.empty;
    Map<String, dynamic> result;
    try {
      // Small lyrics encode inline: the isolate spawn costs more than the work.
      final bytes = raw.length <= _inlineEncodeChars
          ? Uint8List.fromList(utf8.encode(raw))
          : await compute(_encodeLyricsInBackground, raw);
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

  // The word timing belongs to the occurrence nearest the first word;
  // repeated occurrences replay the same relative timing (BUG-103).

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
}
