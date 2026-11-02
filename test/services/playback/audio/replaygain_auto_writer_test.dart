import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/ffmpeg/ffmpeg_models.dart';
import 'package:sistrum/services/playback/audio/replaygain_auto_writer.dart';
import 'package:sistrum/services/playback/audio/replaygain_progress.dart';
import 'package:sistrum/services/playback/audio/replaygain_state.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis_store.dart';

AppSettings _settings({bool charging = false}) => const AppSettings().copyWith(
  replayGainAutoWrite: true,
  replayGainOnlyWhileCharging: charging,
);
ReplayGainLibrarySong _song(
  String path, {
  String? album = 'Album',
  bool local = true,
}) => (
  path: path,
  album: album,
  albumArtist: 'Artist',
  artist: 'Artist',
  local: local,
);
const _measurement = ReplayGainResult(
  trackGain: '-7.00 dB',
  trackPeak: '0.800000',
  integratedLufs: -11,
  truePeakLinear: 0.8,
);
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 1000 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(done(), isTrue, reason: 'ReplayGain operation did not settle');
}

class _FailingState extends MemoryReplayGainState {
  @override
  Future<void> saveTrackStamp(String path, SongFileStamp stamp) async =>
      throw StateError('state write failed');
}

class _Fake {
  _Fake(this.songs) {
    for (final song in songs) {
      stamps[song.path] = (size: 10, modified: 10);
    }
  }
  final List<ReplayGainLibrarySong> songs;
  final stamps = <String, SongFileStamp>{};
  final metadata = <String, Map<String, dynamic>>{};
  final trackScans = <String>[];
  final albumScans = <List<String>>[];
  final writes = <String, List<Map<String, String>>>{};
  final phases = <ReplayGainProgress>[];
  MemoryReplayGainState state = MemoryReplayGainState();
  final failedReads = <String>{}, failedWrites = <String>{};
  String? playing;
  bool charging = true;
  int libraryReads = 0;
  Future<void> Function()? duringAlbum, beforeWrite;
  Future<void> Function(Duration)? wait;
  late final ReplayGainAutoWriter writer =
      ReplayGainAutoWriter(
          librarySongs: () async {
            libraryReads++;
            return List.of(songs);
          },
          stamp: (path) async => stamps[path],
          readTags: (path) async {
            if (failedReads.contains(path)) {
              throw StateError('permission denied');
            }
            return metadata[path] ?? {};
          },
          scanTrack: (path) async {
            trackScans.add(path);
            return _measurement;
          },
          scanAlbum: (paths) async {
            albumScans.add(List.of(paths));
            await duringAlbum?.call();
            return _measurement;
          },
          writeTags: (path, fields, guard) async {
            await beforeWrite?.call();
            if (!await guard()) {
              return const ReplayGainWriteResult.failed(
                ReplayGainWriteFailure.deferred,
              );
            }
            if (failedWrites.contains(path)) {
              return const ReplayGainWriteResult.failed(
                ReplayGainWriteFailure.storageFailed,
              );
            }
            writes.putIfAbsent(path, () => []).add(Map.of(fields));
            metadata.putIfAbsent(path, () => {}).addAll(fields);
            final stamp = stamps[path]!;
            stamps[path] = (size: stamp.size + 1, modified: stamp.modified + 1);
            return const ReplayGainWriteResult.written();
          },
          state: state,
          isCharging: () async => charging,
          nowPlayingPath: () async => playing,
          wait: (delay) async {
            if (wait != null) {
              await wait!(delay);
            } else {
              await Completer<void>().future;
            }
          },
          isAndroid: true,
        )
        ..progress.addListener(() {
          final next = writer.progress.value;
          if (next != null) phases.add(next);
        });
  Future<void> finish() =>
      _until(() => writer.progress.value?.phase == ReplayGainPhase.completed);
}

void main() {
  test('library grouping and fingerprints retain whole-album identity', () {
    expect(
      ReplayGainLibrary.albumKeyOf(_song('/a')),
      ReplayGainLibrary.albumKeyOf((
        path: '/b',
        album: 'ALBUM',
        albumArtist: 'ARTIST',
        artist: 'x',
        local: true,
      )),
    );
    expect(ReplayGainLibrary.albumKeyOf(_song('/a', album: null)), isNull);
    final stamps = {'/a': (size: 1, modified: 1), '/b': (size: 2, modified: 2)};
    final both = ReplayGainLibrary.fingerprintOf(['/a', '/b'], stamps);
    expect(ReplayGainLibrary.fingerprintOf(['/a'], stamps), isNot(both));
    expect(ReplayGainLibrary.fingerprintOf(['/missing'], stamps), isNull);
  });

  test(
    'track and album tags publish together once; progress finishes after publication',
    () async {
      final fake = _Fake([_song('/a.flac'), _song('/b.flac')]);
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.trackScans, ['/a.flac', '/b.flac']);
      expect(fake.albumScans.single, ['/a.flac', '/b.flac']);
      for (final writes in fake.writes.values) {
        expect(writes, hasLength(1));
        expect(
          writes.single.keys,
          containsAll([
            'replaygain_track_gain',
            'replaygain_track_peak',
            'replaygain_album_gain',
            'replaygain_album_peak',
          ]),
        );
      }
      expect(
        fake.phases
            .where((p) => p.phase != ReplayGainPhase.completed)
            .every((p) => (p.fraction ?? 0) < 1),
        isTrue,
      );
      final done = fake.writer.progress.value!;
      expect(done.written, 2);
      expect(done.failed, 0);
      expect(done.fraction, 1);
    },
  );

  test(
    'first observation preserves complete existing tags without measurements or writes',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      fake.metadata['/a.flac'] = {
        'replaygain_track_gain': '-3 dB',
        'replaygain_track_peak': '0.5',
        'replaygain_album_gain': '-4 dB',
        'replaygain_album_peak': '0.6',
      };
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.trackScans, isEmpty);
      expect(fake.albumScans, isEmpty);
      expect(fake.writes, isEmpty);
      expect(fake.writer.progress.value!.unchanged, 1);
      expect(await fake.state.trackStamp('/a.flac'), fake.stamps['/a.flac']);
    },
  );

  test(
    'existing track tags are retained while missing album tags are added once',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      fake.metadata['/a.flac'] = {'replaygain_track_gain': '-3 dB'};
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.trackScans, isEmpty);
      expect(
        fake.writes['/a.flac']!.single.keys,
        everyElement(startsWith('replaygain_album_')),
      );
    },
  );

  test(
    'unchanged files skip subsequent scans and adding a member remeasures the album',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      final reads = fake.libraryReads;
      fake.writer.refresh();
      await _until(() => fake.libraryReads > reads);
      await fake.finish();
      expect(fake.trackScans, hasLength(1));
      expect(fake.albumScans, hasLength(1));
      fake.songs.add(_song('/b.flac'));
      fake.stamps['/b.flac'] = (size: 10, modified: 10);
      fake.writer.refresh();
      await _until(() => fake.albumScans.length == 2);
      await fake.finish();
      expect(fake.albumScans.last, ['/a.flac', '/b.flac']);
      expect(fake.trackScans, ['/a.flac', '/b.flac']);
    },
  );

  test(
    'a known changed file gets new track and album values in one write',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      fake.stamps['/a.flac'] = (size: 30, modified: 30);
      fake.writer.refresh();
      await _until(() => fake.trackScans.length == 2);
      await fake.finish();
      expect(fake.writes['/a.flac'], hasLength(2));
    },
  );

  test(
    'mixed filesystem and SAF members are measured as one complete album',
    () async {
      final fake = _Fake([_song('/a.flac'), _song('content://music/b')]);
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.albumScans.single, ['/a.flac', 'content://music/b']);
      expect(fake.writes.keys, containsAll(['/a.flac', 'content://music/b']));
    },
  );

  test(
    'permission errors do not produce partial album gain and other tracks continue',
    () async {
      final fake = _Fake([_song('/a.flac'), _song('content://music/b')]);
      fake.failedReads.add('content://music/b');
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.albumScans, isEmpty);
      expect(
        fake.writes['/a.flac']!.single,
        isNot(contains('replaygain_album_gain')),
      );
      expect(fake.writer.progress.value!.failed, 1);
      expect(fake.writer.progress.value!.written, 1);
    },
  );

  test('unsupported members prevent partial album measurement', () async {
    final fake = _Fake([
      _song('/a.flac'),
      _song('https://unsupported/song', local: false),
    ]);
    addTearDown(fake.writer.dispose);
    fake.writer.configure(_settings());
    await fake.finish();
    expect(fake.albumScans, isEmpty);
  });

  test(
    'a song starting playback during album measurement is deferred before write',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      fake.duringAlbum = () async {
        fake.playing = '/a.flac';
      };
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await _until(
        () =>
            fake.writer.progress.value?.phase ==
            ReplayGainPhase.waitingForPlayback,
      );
      expect(fake.writes, isEmpty);
      expect(fake.writer.progress.value!.deferred, 1);
      expect(
        await fake.state.albumFingerprint(
          ReplayGainLibrary.albumKeyOf(fake.songs.single)!,
        ),
        isNull,
      );
    },
  );

  test(
    'service guard catches playback starting after the outer write check',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      fake.beforeWrite = () async {
        fake.playing = '/a.flac';
      };
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await _until(
        () =>
            fake.writer.progress.value?.phase ==
            ReplayGainPhase.waitingForPlayback,
      );
      expect(fake.writes, isEmpty);
    },
  );

  test(
    'a file changed during measurement is deferred instead of receiving stale values',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      fake.duringAlbum = () async {
        fake.stamps['/a.flac'] = (size: 40, modified: 40);
      };
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await _until(
        () =>
            fake.writer.progress.value?.phase ==
            ReplayGainPhase.waitingForPlayback,
      );
      expect(fake.writes, isEmpty);
    },
  );

  test(
    'failure counts are distinct and a failed album publication is not stamped complete',
    () async {
      final fake = _Fake([_song('/a.flac'), _song('/b.flac')]);
      fake.failedWrites.add('/b.flac');
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.writer.progress.value!.written, 1);
      expect(fake.writer.progress.value!.failed, 1);
      expect(
        await fake.state.albumFingerprint(
          ReplayGainLibrary.albumKeyOf(fake.songs.first)!,
        ),
        isNull,
      );
    },
  );

  test(
    'rapid off/on while a scan is pending queues a fresh generation',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      final entered = Completer<void>(), release = Completer<void>();
      fake.duringAlbum = () async {
        if (!entered.isCompleted) {
          entered.complete();
          await release.future;
        }
      };
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await entered.future;
      fake.writer.configure(const AppSettings());
      expect(fake.writer.progress.value, isNull);
      fake.writer.configure(_settings());
      release.complete();
      await fake.finish();
      expect(fake.libraryReads, 2);
      expect(fake.writes['/a.flac'], hasLength(1));
    },
  );

  test(
    'charging wait wakes immediately when disabled and re-enabled without the restriction',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      fake.charging = false;
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings(charging: true));
      await _until(
        () =>
            fake.writer.progress.value?.phase ==
            ReplayGainPhase.waitingForCharging,
      );
      expect(fake.trackScans, isEmpty);
      fake.writer.configure(const AppSettings());
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.writes['/a.flac'], hasLength(1));
    },
  );

  test('index refresh during a scan is not lost', () async {
    final fake = _Fake([_song('/a.flac')]);
    var queued = false;
    fake.duringAlbum = () async {
      if (!queued) {
        queued = true;
        fake.writer.refresh();
      }
    };
    addTearDown(fake.writer.dispose);
    fake.writer.configure(_settings());
    await _until(() => fake.libraryReads == 2);
    await fake.finish();
    expect(fake.writes['/a.flac'], hasLength(1));
  });

  test(
    'disposal during a pending scan prevents writes and stale notifications',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      final entered = Completer<void>(), release = Completer<void>();
      fake.duringAlbum = () async {
        entered.complete();
        await release.future;
      };
      fake.writer.configure(_settings());
      await entered.future;
      await fake.writer.dispose();
      release.complete();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(fake.writes, isEmpty);
    },
  );
  test(
    'missing file identity is reported without publishing unverified measurements',
    () async {
      final fake = _Fake([_song('content://music/unknown')]);
      fake.stamps.clear();
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.trackScans, isEmpty);
      expect(fake.writes, isEmpty);
      expect(fake.writer.progress.value!.failed, 1);
    },
  );

  test('a playing file is retried only after playback releases it', () async {
    final fake = _Fake([_song('/a.flac')]);
    fake.playing = '/a.flac';
    fake.wait = (_) async {
      fake.playing = null;
    };
    addTearDown(fake.writer.dispose);
    fake.writer.configure(_settings());
    await fake.finish();
    expect(fake.writes['/a.flac'], hasLength(1));
    expect(
      fake.phases.any((p) => p.phase == ReplayGainPhase.waitingForPlayback),
      isTrue,
    );
  });

  test(
    'an empty library finishes without an endless preparation indicator',
    () async {
      final fake = _Fake([]);
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.writer.progress.value!.total, 0);
      expect(fake.writer.progress.value!.fraction, 1);
    },
  );

  test(
    'explicit off/on retries failed files without losing the failure counts',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      fake.failedWrites.add('/a.flac');
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.writer.progress.value!.failed, 1);
      fake.failedWrites.clear();
      fake.writer.configure(const AppSettings());
      fake.writer.configure(_settings());
      await fake.finish();
      expect(fake.writer.progress.value!.failed, 0);
      expect(fake.writer.progress.value!.written, 1);
    },
  );
  test(
    'state persistence failure does not double count a file as written and failed',
    () async {
      final fake = _Fake([_song('/a.flac')]);
      fake.state = _FailingState();
      addTearDown(fake.writer.dispose);
      fake.writer.configure(_settings());
      await fake.finish();
      final result = fake.writer.progress.value!;
      expect(result.failed, 1);
      expect(result.written, 0);
      expect(result.unchanged, 0);
      expect(
        result.failed + result.written + result.unchanged + result.deferred,
        result.total,
      );
    },
  );
}
