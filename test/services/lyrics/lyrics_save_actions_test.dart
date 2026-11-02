import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/metadata/track_metadata_persistence.dart';
import 'package:sistrum/services/lyrics/embedded_lyrics_writer.dart';
import 'package:sistrum/services/lyrics/lrc_sidecar_store.dart';
import 'package:sistrum/services/lyrics/lyrics_save_actions.dart';
import 'package:sistrum/services/lyrics/lyrics_timing_store.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

class _Embedded implements EmbeddedLyricsStore {
  _Embedded({this.existing = '', this.writeOk = true});

  final String existing;
  final bool writeOk;
  String? written;

  @override
  Future<String> existingLyrics(LocalLibraryItem item) async => existing;

  @override
  Future<EmbeddedLyricsWriteResult> write(
    LocalLibraryItem item,
    String lyrics,
  ) async {
    if (!writeOk) {
      return const EmbeddedLyricsWriteResult.failed(
        MetadataSaveFailure.storage,
      );
    }
    written = lyrics;
    return const EmbeddedLyricsWriteResult.saved();
  }
}

LocalLibraryItem _song({String path = '/music/song.flac'}) => LocalLibraryItem(
  id: 'song-1',
  sourceId: 'legacy',
  trackName: 'Song',
  artistName: 'Artist',
  albumName: 'Album',
  filePath: path,
  scannedAt: DateTime(2026),
  fileModTime: 42,
  duration: 200,
);

const _line = OnlineLyricsCandidate(
  provider: 'lrclib',
  timing: LyricsTiming.lineSynced,
  text: '[00:01.00]Hi',
);

LyricsSaveActions _actions({
  required EmbeddedLyricsStore embedded,
  LrcSidecarStore sidecar = const LrcSidecarStore(),
  MemoryLyricsTimingState? timings,
}) => LyricsSaveActions(
  embedded: embedded,
  sidecar: sidecar,
  timings: timings ?? MemoryLyricsTimingState(),
);

Future<bool> _yes() async => true;
Future<bool> _no() async => false;

void main() {
  test('embedding writes the lyrics and records their timing', () async {
    final embedded = _Embedded();
    final timings = MemoryLyricsTimingState();
    final outcome = await _actions(
      embedded: embedded,
      timings: timings,
    ).embed(_song(), _line, confirmReplace: _no);

    expect(outcome, LyricsSaveOutcome.saved);
    expect(embedded.written, '[00:01.00]Hi');
    final record = (await timings.readAll())['song-1']!;
    expect(record.timing, LyricsTiming.lineSynced);
    expect(record.fingerprint, lyricsFingerprint('/music/song.flac', 42));
  });

  test(
    'existing lyrics are kept when the user declines to replace them',
    () async {
      final embedded = _Embedded(existing: '[00:01.00]Old');
      final outcome = await _actions(
        embedded: embedded,
      ).embed(_song(), _line, confirmReplace: _no);

      expect(outcome, LyricsSaveOutcome.keptExisting);
      expect(embedded.written, isNull);
    },
  );

  test('existing lyrics are replaced after the user confirms', () async {
    final embedded = _Embedded(existing: '[00:01.00]Old');
    final outcome = await _actions(
      embedded: embedded,
    ).embed(_song(), _line, confirmReplace: _yes);

    expect(outcome, LyricsSaveOutcome.saved);
    expect(embedded.written, '[00:01.00]Hi');
  });

  test(
    'the replace question is asked only when lyrics already exist',
    () async {
      var asked = 0;
      await _actions(embedded: _Embedded()).embed(
        _song(),
        _line,
        confirmReplace: () async {
          asked++;
          return true;
        },
      );
      expect(asked, 0);
    },
  );

  test('a failed embed records nothing', () async {
    final timings = MemoryLyricsTimingState();
    final outcome = await _actions(
      embedded: _Embedded(writeOk: false),
      timings: timings,
    ).embed(_song(), _line, confirmReplace: _no);

    expect(outcome, LyricsSaveOutcome.failed);
    expect(await timings.readAll(), isEmpty);
  });

  test('a .lrc file is written beside the audio file', () async {
    final dir = Directory.systemTemp.createTempSync('lrc_save_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final audio = '${dir.path}/song.flac';

    final outcome = await _actions(
      embedded: _Embedded(),
    ).downloadLrc(_song(path: audio), _line, confirmReplace: _no);

    expect(outcome, LyricsSaveOutcome.saved);
    expect(File('${dir.path}/song.lrc').readAsStringSync(), '[00:01.00]Hi');
  });

  test('an existing .lrc file is kept when the user declines', () async {
    final dir = Directory.systemTemp.createTempSync('lrc_save_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final lrc = File('${dir.path}/song.lrc')..writeAsStringSync('old');

    final outcome = await _actions(embedded: _Embedded()).downloadLrc(
      _song(path: '${dir.path}/song.flac'),
      _line,
      confirmReplace: _no,
    );

    expect(outcome, LyricsSaveOutcome.keptExisting);
    expect(lrc.readAsStringSync(), 'old');
  });

  test('an existing .lrc file is replaced after the user confirms', () async {
    final dir = Directory.systemTemp.createTempSync('lrc_save_test');
    addTearDown(() => dir.deleteSync(recursive: true));
    final lrc = File('${dir.path}/song.lrc')..writeAsStringSync('old');

    final outcome = await _actions(embedded: _Embedded()).downloadLrc(
      _song(path: '${dir.path}/song.flac'),
      _line,
      confirmReplace: _yes,
    );

    expect(outcome, LyricsSaveOutcome.saved);
    expect(lrc.readAsStringSync(), '[00:01.00]Hi');
  });

  test(
    'a folder-picker song reports that no .lrc can be saved beside it',
    () async {
      final outcome = await _actions(embedded: _Embedded()).downloadLrc(
        _song(path: 'content://tree/document/song.flac'),
        _line,
        confirmReplace: _no,
      );
      expect(outcome, LyricsSaveOutcome.unsupported);
    },
  );
}
