import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_color_utilities/quantize/quantizer_celebi.dart';
import 'package:sqflite/sqflite.dart';
import 'package:sistrum/services/native/library_scan_bridge.dart';
import 'package:sistrum/services/playback/automix/automix_analysis.dart';
import 'package:sistrum/services/library/database/library_row_mapper.dart';
import 'package:sistrum/services/library/database/library_schema.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/utils/lyrics/lyrics_parser.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/widgets/audio_analysis/audio_analysis_widget.dart';

part 'native_data_jobs_1.dart';

// Run on a real Android/iOS host. These tests intentionally use the actual
// channel and native workers; missing bindings must fail, never use a fallback.
Future<Map<String, dynamic>> _job(
  String operation,
  Map<String, dynamic> request, {
  Uint8List? bytes,
  String? requestId,
}) => NativeDataJobs.run(
  {'operation': operation, ...request},
  bytes: bytes,
  requestId: requestId,
);

Map<String, dynamic> _word(LyricWord word) => {
  'timeMs': word.time.inMilliseconds,
  'endMs': word.end?.inMilliseconds,
  'text': word.text,
};

Map<String, dynamic> _lyricsDto(ParsedLyrics lyrics) => {
  'synced': lyrics.synced,
  'wordSynced': lyrics.wordSynced,
  'plainText': lyrics.plainText,
  'writers': lyrics.writers,
  'provider': lyrics.provider,
  'lines': [
    for (final line in lyrics.lines)
      {
        'timeMs': line.time.inMilliseconds,
        'endMs': line.end?.inMilliseconds,
        'text': line.text,
        'words': line.words.map(_word).toList(),
        'romanization': line.romanization,
        'romanizationWords': line.romanizationWords.map(_word).toList(),
        'translation': line.translation,
        'voice': line.voice == null
            ? null
            : {
                'id': line.voice!.id,
                'index': line.voice!.index,
                'isGroup': line.voice!.isGroup,
              },
        'isBackground': line.isBackground,
        'vocalGroup': line.vocalGroup,
      },
  ],
};

Uint8List _drums(double bpm) {
  const rate = 11025;
  final data = ByteData(rate * 24 * 2);
  final random = math.Random(7);
  for (var i = 0; i < rate * 24; i++) {
    final time = i / rate;
    final transient = time < 0.17
        ? 0.0
        : math.exp(-((time - 0.17) % (60 / bpm)) * 50);
    final value =
        0.75 * transient * math.sin(time * 2 * math.pi * 100) +
        (random.nextDouble() - 0.5) * 0.003;
    data.setInt16(i * 2, (value * 32767).round(), Endian.little);
  }
  return data.buffer.asUint8List();
}

Uint8List _flac({String title = 'Native song', Uint8List? picture}) {
  final comments = BytesBuilder();
  void little(int number) => comments.add(
    (ByteData(4)..setUint32(0, number, Endian.little)).buffer.asUint8List(),
  );
  little(0);
  final tags = ['TITLE=$title', 'ARTIST=Native artist', 'ALBUM=Native album'];
  little(tags.length);
  for (final tag in tags) {
    final bytes = utf8.encode(tag);
    little(bytes.length);
    comments.add(bytes);
  }
  final output = BytesBuilder()..add(ascii.encode('fLaC'));
  void block(int type, List<int> bytes, {bool last = false}) => output.add([
    type | (last ? 128 : 0),
    (bytes.length >> 16) & 255,
    (bytes.length >> 8) & 255,
    bytes.length & 255,
    ...bytes,
  ]);
  // A valid STREAMINFO descriptor; identifiable audio bytes stay unchanged.
  final streamInfo = ByteData(34)
    ..setUint16(0, 4096)
    ..setUint16(2, 4096);
  final descriptor = (44100 << 44) | (1 << 41) | (15 << 36) | 44100;
  streamInfo.setUint64(10, descriptor);
  block(0, streamInfo.buffer.asUint8List());
  block(4, comments.takeBytes(), last: picture == null);
  if (picture != null) block(6, picture, last: true);
  output.add([0xff, 0xf8, ...utf8.encode('unchanged native audio payload')]);
  return output.takeBytes();
}

void main() {
  _registerNativeDataJobs1();
}

// Embedded from test/fixtures/native_lyrics_parsers.json so device tests do not
// depend on repository files or add fixtures to the production asset bundle.
const _lyricCases = <(String, String)>[
  ("empty", ""),
  (
    "plain IDs and Unicode",
    "﻿[ar:Performer]\r[by:Uploader]\r\nV2: 日本語\n\nPlain text",
  ),
  (
    "voices words supplements offset",
    "[offset:100]\n[x-romaji:2000:U2Vjb25kIHJlYWRpbmc=]\n[x-translation:2000:U2Vjb25kIHRyYW5zbGF0aW9u]\n[00:01.00]v1:<00:01.00>First<00:03.00>\n[00:02.00]<00:02.00> V2: Second<00:04.00>\n[00:04.00]v3:Third\n[00:06.00]v12:Twelfth\n[00:08.00]The v2: label stays inside a sentence",
  ),
  (
    "background groups sorting",
    "[offset:100]\n[00:01.00]v2:<00:01.00>Lead<00:06.00>\n[bg:<00:04.00>Echo<00:05.00>]\n[bg:[00:05.00]<00:05.00>Again<00:06.00>]\n[00:03.00]v1:<00:03.00>Other lead<00:06.00>",
  ),
  (
    "repeated line and empty end tags",
    "[00:08.10][00:01.9]<00:01.00>First <00:00.90><00:01.30><00:01.40><00:02.00>second<00:02.00>",
  ),
  (
    "stable simultaneous voice order",
    "[00:02]v2:Guest\n[00:01]Lead\n[00:02]v1:Lead again\n[bg:echo]",
  ),
  (
    "boundary collision supplements",
    "[x-romaji:1009:TmVhcg==]\n[x-romaji:1010:RXhhY3Q=]\n[x-romaji:1001:RnVydGhlcg==]\n[x-translation:2005:VGll]\n[x-translation:2990:Qm91bmRhcnk=]\n[x-translation:4011:VG9vIGZhcg==]\n[00:01.010]A\n[00:02.000]B\n[00:02.010]C\n[00:03.000]D\n[00:04]E",
  ),
  (
    "romanized timed words offset",
    "[offset:109]\n[x-romaji-words:1009:W3sidGV4dCI6IlJvIiwic3RhcnRUaW1lTXMiOjEwMDksImVuZFRpbWVNcyI6MTEwN30seyJ0ZXh0IjoibWEgIiwic3RhcnRUaW1lTXMiOjExMDcsImVuZFRpbWVNcyI6MTMwN30seyJ0ZXh0Ijoibml6ZWQiLCJzdGFydFRpbWVNcyI6MjAwMywiZW5kVGltZU1zIjoyNDk3fV0=]\n[x-romaji:1009:Um9tYSBuaXplZA==]\n[00:01.01]Original",
  ),
  (
    "romanization mismatched words",
    "[x-romaji:1000:Um9tYW5pemVk]\n[x-romaji-words:1000:W3sidGV4dCI6Ik90aGVyIiwic3RhcnRUaW1lTXMiOjEwMDAsImVuZFRpbWVNcyI6MTMwMH1d]\n[00:01]Original",
  ),
  (
    "only romanization timings remain hidden",
    "[x-romaji-words:1000:W3sidGV4dCI6IlJvIiwic3RhcnRUaW1lTXMiOjEwMDAsImVuZFRpbWVNcyI6MTMwMH1d]\n[00:01]Original",
  ),
  (
    "corrupt optional metadata",
    "[x-romaji:1000:%%%]\n[x-romaji:1000:/w==]\n[x-translation:bad:YQ==]\n[x-translation:1000:]\n[x-romaji-words:1000:W251bGxd]\n[00:01]Original",
  ),
  (
    "supplement base64 normalization",
    "[x-romaji:1000:Um8]\n[x-translation:1000:44GT44KT44Gr44Gh44Gv]\n[00:01]Original",
  ),
  (
    "unicode newline supplement first wins",
    "[x-translation:1000:5pel5pys6KqeIF0KU2Vjb25kIGxpbmU=]\n[x-translation:1000:SWdub3JlZA==]\n[00:01]Original",
  ),
  (
    "negative offset and clamped timing",
    "[offset:2500]\n[00:01]<00:01>Word<00:02>\n[00:03]Next",
  ),
  (
    "credits explicit trailer",
    "[au:Existing Writer]\n[x-provider:extension:stored]\n[00:04]Written By: Ignored Writer\n[00:01]Last lyric",
  ),
  (
    "credits via API",
    "[by:\u0053\u0070\u006f\u0074\u0069\u0046\u004c\u0041\u0043-Mobile via Example Lyrics API (source: upstream)]\n[00:01]First line\n[00:04]Written By: Example Writer",
  ),
  (
    "credits source fallback",
    "[by:\u0053\u0070\u006f\u0074\u0069\u0046\u004c\u0041\u0043-Mobile (source: extension:example.lyrics)]\n[00:01]Lyric",
  ),
  (
    "TTML namespaced agent inheritance",
    "<t:tt xmlns:t=\"http://www.w3.org/ns/ttml\" xmlns:m=\"http://www.w3.org/ns/ttml#metadata\"><t:head><t:metadata><m:agent xml:id=\"lead\" type=\"person\"/><m:agent xml:id=\"guest\" type=\"person\"/><m:agent xml:id=\"v3\" type=\"group\"/><m:agent xml:id=\"third\" type=\"person\"/></t:metadata></t:head><t:body><t:div m:agent=\"lead\"><t:p begin=\"1s\" end=\"3s\">Lead</t:p><t:p begin=\"3s\" end=\"5s\" m:agent=\"guest\">Guest</t:p><t:p begin=\"5s\" end=\"7s\" m:agent=\"v3\">Together</t:p><t:p begin=\"7s\" end=\"9s\" m:agent=\"third\">Third</t:p></t:div></t:body></t:tt>",
  ),
  (
    "TTML runs voices syllable grouping",
    "<tt xmlns=\"http://www.w3.org/ns/ttml\" xmlns:m=\"http://www.w3.org/ns/ttml#metadata\"><head><metadata><m:agent xml:id=\"v1\" type=\"person\"/><m:agent xml:id=\"v2\" type=\"person\"/></metadata></head><body><div><p begin=\"1s\" end=\"5s\"><span m:agent=\"v1\"><span begin=\"1s\" end=\"2s\">日本</span><span begin=\"2s\" end=\"3s\">語</span></span><span m:agent=\"v2\" begin=\"2s\" end=\"4s\">Reply</span><span m:agent=\"v1\" m:role=\"x-bg\" begin=\"2s\" end=\"3s\">Echo</span></p></div></body></tt>",
  ),
  (
    "TTML partial timing retains text",
    "<tt><body><p begin=\"1s\" end=\"5s\">Untimed <span begin=\"2s\" end=\"3s\">timed</span> ending</p></body></tt>",
  ),
  (
    "TTML paragraph end and word end separate",
    "<tt xmlns=\"http://www.w3.org/ns/ttml\"><body><div><p begin=\"00:01.009\" end=\"00:05.000\">\n<span begin=\"00:01.009\" end=\"00:01.307\">First</span>\n<span begin=\"00:02.003\" end=\"00:02.497\">second</span>\n</p></div></body></tt>",
  ),
  (
    "TTML duplicate songwriters nested entity text",
    "<tt xmlns:meta=\"urn:example\"><head><meta:songwriter>Example &amp; Writer</meta:songwriter><meta:songwriter>Second <span>Writer</span></meta:songwriter><meta:songwriter>Example &amp; Writer</meta:songwriter></head><body><p begin=\"00:01.00\">Lyric</p></body></tt>",
  ),
  (
    "TTML invalid missing paragraph timing falls to plain",
    "<tt><body><p>No time</p></body></tt>",
  ),
  (
    "TTML CDATA vocals skipped but songwriter retained",
    "<tt><head><songwriter><![CDATA[Writer & guest]]></songwriter></head><body><p begin=\"1s\"><![CDATA[Skipped]]>Visible<![CDATA[Skipped]]> again</p></body></tt>",
  ),
  ("TTML malformed syntax falls to plain", "<tt invalid"),
  (
    "TTML clocks negative and hours",
    "<tt><body><p begin=\"-1.25s\" end=\"0.5s\">Negative</p><p begin=\"01:02:03.456\" end=\"01:02:04.123\"><span begin=\"01:02:03.456\" end=\"01:02:03.455\">Word</span></p><p begin=\"00:07.0005\" end=\"8s\">Rounded</p></body></tt>",
  ),
  (
    "TTML same-voice fragments merge across interruption",
    "<tt xmlns:m=\"http://www.w3.org/ns/ttml#metadata\"><body><p begin=\"1s\" end=\"5s\"><span m:agent=\"v1\" begin=\"1s\">A </span><span m:agent=\"v2\" begin=\"2s\">B</span><span m:agent=\"v1\" begin=\"3s\"> C</span><span m:role=\"x-bg\" m:agent=\"v1\" begin=\"2s\">Echo</span></p></body></tt>",
  ),
];
