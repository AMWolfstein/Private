import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/services/library/metadata/track_metadata_persistence.dart';
import 'package:sistrum/services/lyrics/embedded_lyrics_writer.dart';
import 'package:sistrum/services/lyrics/lyrics_fetch_controller.dart';
import 'package:sistrum/services/lyrics/lyrics_timing_store.dart';
import 'package:sistrum/services/lyrics/online_lyrics_search.dart';

class _Source implements OnlineLyricsProvider {
  _Source(this.id, this.bestTiming, {this.result, this.fails = false});

  @override
  final String id;
  @override
  final LyricsTiming bestTiming;
  final OnlineLyricsCandidate? result;
  final bool fails;

  @override
  Future<OnlineLyricsCandidate?> find(OnlineLyricsQuery query) async {
    if (fails) throw Exception('down');
    return result;
  }
}

class _Store implements EmbeddedLyricsStore {
  _Store({this.existing = '', this.writeOk = true});

  final String existing;
  final bool writeOk;
  String? written;
  int writes = 0;

  @override
  Future<String> existingLyrics(LocalLibraryItem item) async => existing;

  @override
  Future<EmbeddedLyricsWriteResult> write(
    LocalLibraryItem item,
    String lyrics,
  ) async {
    writes++;
    if (!writeOk) {
      return const EmbeddedLyricsWriteResult.failed(
        MetadataSaveFailure.storage,
      );
    }
    written = lyrics;
    return const EmbeddedLyricsWriteResult.saved();
  }
}

class _Prompts implements LyricsFetchPrompts {
  _Prompts({this.replace = true, this.plain = true});

  final bool replace;
  final bool plain;
  int replaceAsked = 0;
  int plainAsked = 0;

  @override
  Future<bool> confirmReplaceExisting() async {
    replaceAsked++;
    return replace;
  }

  @override
  Future<bool> confirmPlainLyrics() async {
    plainAsked++;
    return plain;
  }
}

LocalLibraryItem _song() => LocalLibraryItem(
  id: 'song-1',
  sourceId: 'legacy',
  trackName: 'Song',
  artistName: 'Artist',
  albumName: 'Album',
  filePath: '/music/song.flac',
  scannedAt: DateTime(2026),
  fileModTime: 42,
  duration: 200,
);

const _word = OnlineLyricsCandidate(
  provider: 'musixmatch',
  timing: LyricsTiming.wordSynced,
  text: '[00:01.00]<00:01.00>Hi',
);
const _line = OnlineLyricsCandidate(
  provider: 'lrclib',
  timing: LyricsTiming.lineSynced,
  text: '[00:01.00]Hi',
);
const _plain = OnlineLyricsCandidate(
  provider: 'genius',
  timing: LyricsTiming.plain,
  text: 'Hi there',
);

LyricsFetchController _controller({
  required List<OnlineLyricsProvider> sources,
  required _Store store,
  required _Prompts prompts,
  required MemoryLyricsTimingState timings,
  void Function()? onSearch,
}) => LyricsFetchController(
  search: () {
    onSearch?.call();
    return OnlineLyricsSearch(sources);
  },
  store: store,
  prompts: prompts,
  timings: timings,
);

void main() {
  test(
    'keeps existing lyrics when the user declines to replace them',
    () async {
      var searched = false;
      final store = _Store(existing: '[00:01.00]Old');
      final prompts = _Prompts(replace: false);
      final result = await _controller(
        sources: [_Source('a', LyricsTiming.wordSynced, result: _word)],
        store: store,
        prompts: prompts,
        timings: MemoryLyricsTimingState(),
        onSearch: () => searched = true,
      ).run(_song());

      expect(result.outcome, LyricsFetchOutcome.keptExisting);
      expect(searched, isFalse, reason: 'no request is sent when declined');
      expect(store.writes, 0);
    },
  );

  test('asks to replace only when the file already has lyrics', () async {
    final prompts = _Prompts();
    await _controller(
      sources: [_Source('a', LyricsTiming.wordSynced, result: _word)],
      store: _Store(),
      prompts: prompts,
      timings: MemoryLyricsTimingState(),
    ).run(_song());
    expect(prompts.replaceAsked, 0);
  });

  test('a word-synced result is written and recorded as word-synced', () async {
    final store = _Store();
    final timings = MemoryLyricsTimingState();
    final result = await _controller(
      sources: [
        _Source('lrclib', LyricsTiming.lineSynced, result: _line),
        _Source('musixmatch', LyricsTiming.wordSynced, result: _word),
      ],
      store: store,
      prompts: _Prompts(),
      timings: timings,
    ).run(_song());

    expect(result.outcome, LyricsFetchOutcome.saved);
    expect(result.provider, 'musixmatch');
    expect(store.written, _word.text);
    final record = (await timings.readAll())['song-1']!;
    expect(record.timing, LyricsTiming.wordSynced);
    expect(record.fingerprint, lyricsFingerprint('/music/song.flac', 42));
  });

  test('a line result is used when no word source has words', () async {
    final result = await _controller(
      sources: [_Source('lrclib', LyricsTiming.lineSynced, result: _line)],
      store: _Store(),
      prompts: _Prompts(),
      timings: MemoryLyricsTimingState(),
    ).run(_song());

    expect(result.outcome, LyricsFetchOutcome.saved);
    expect(result.timing, LyricsTiming.lineSynced);
  });

  test('declining plain text ends the run without writing', () async {
    final store = _Store();
    final prompts = _Prompts(plain: false);
    final result = await _controller(
      sources: [_Source('genius', LyricsTiming.plain, result: _plain)],
      store: store,
      prompts: prompts,
      timings: MemoryLyricsTimingState(),
    ).run(_song());

    expect(result.outcome, LyricsFetchOutcome.declinedPlain);
    expect(prompts.plainAsked, 1);
    expect(store.writes, 0);
  });

  test('accepting plain text writes it and records it as plain', () async {
    final store = _Store();
    final timings = MemoryLyricsTimingState();
    final result = await _controller(
      sources: [_Source('genius', LyricsTiming.plain, result: _plain)],
      store: store,
      prompts: _Prompts(),
      timings: timings,
    ).run(_song());

    expect(result.outcome, LyricsFetchOutcome.saved);
    expect(result.timing, LyricsTiming.plain);
    expect(store.written, 'Hi there');
    expect((await timings.readAll())['song-1']!.isSynced, isFalse);
  });

  test('reports not found when even plain text is missing', () async {
    final result = await _controller(
      sources: [_Source('genius', LyricsTiming.plain)],
      store: _Store(),
      prompts: _Prompts(),
      timings: MemoryLyricsTimingState(),
    ).run(_song());

    expect(result.outcome, LyricsFetchOutcome.notFound);
  });

  test('an unreachable source is listed, not hidden as a miss', () async {
    final result = await _controller(
      sources: [
        _Source('spotify', LyricsTiming.wordSynced, fails: true),
        _Source('lrclib', LyricsTiming.lineSynced, result: _line),
      ],
      store: _Store(),
      prompts: _Prompts(),
      timings: MemoryLyricsTimingState(),
    ).run(_song());

    expect(result.outcome, LyricsFetchOutcome.saved);
    expect(result.failedProviders, ['spotify']);
  });

  test('a failed write reports the failure and records nothing', () async {
    final timings = MemoryLyricsTimingState();
    final result = await _controller(
      sources: [_Source('lrclib', LyricsTiming.lineSynced, result: _line)],
      store: _Store(writeOk: false),
      prompts: _Prompts(),
      timings: timings,
    ).run(_song());

    expect(result.outcome, LyricsFetchOutcome.writeFailed);
    expect(result.writeFailure, MetadataSaveFailure.storage);
    expect(await timings.readAll(), isEmpty);
  });

  test('a cancelled search writes nothing', () async {
    final store = _Store();
    final result = await _controller(
      sources: [_Source('lrclib', LyricsTiming.lineSynced, result: _line)],
      store: store,
      prompts: _Prompts(),
      timings: MemoryLyricsTimingState(),
    ).run(_song(), isCancelled: () => true);

    expect(result.outcome, LyricsFetchOutcome.cancelled);
    expect(store.writes, 0);
  });
}
