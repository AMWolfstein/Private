import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/audio/replaygain_auto_writer.dart';
import 'package:sistrum/services/playback/audio/replaygain_state.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis_store.dart';

AppSettings _settings({bool onlyWhileCharging = false}) =>
    const AppSettings().copyWith(
      replayGainAutoWrite: true,
      replayGainOnlyWhileCharging: onlyWhileCharging,
    );

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 400 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

ReplayGainLibrarySong _song(String path, {String? album = 'Album'}) => (
  path: path,
  album: album,
  albumArtist: 'Artist',
  artist: 'Artist',
  local: true,
);

/// A fake device: files with stamps, tags and peaks, and recorded writes.
class _Fake {
  _Fake(this.songs);

  final List<ReplayGainLibrarySong> songs;
  final stamps = <String, SongFileStamp>{};
  final trackTagged = <String>{};
  final peaks = <String, double>{};
  final trackWrites = <String>[];
  final albumWrites = <String>[];
  final albumScans = <List<String>>[];
  String? playing;

  late final writer = ReplayGainAutoWriter(
    librarySongs: () async => songs,
    stamp: (path) async => stamps[path],
    hasTrackTags: (path) async => trackTagged.contains(path),
    writeTrack: (path) async {
      trackWrites.add(path);
      trackTagged.add(path);
      stamps[path] = (
        size: (stamps[path]?.size ?? 0) + 1,
        modified: (stamps[path]?.modified ?? 0) + 1,
      );
      return const ReplayGainWriteResult.written();
    },
    scanAlbumGain: (paths) async {
      albumScans.add(paths);
      return '-7.00 dB';
    },
    trackPeak: (path) async => peaks[path],
    writeAlbum: (path, gain, peak) async {
      albumWrites.add('$path $gain $peak');
      stamps[path] = (
        size: stamps[path]!.size + 1,
        modified: stamps[path]!.modified + 1,
      );
      return const ReplayGainWriteResult.written();
    },
    state: MemoryReplayGainState(),
    isCharging: () async => true,
    nowPlayingPath: () async => playing,
    // Waiting is when the playing song stops, so a later pass writes it.
    wait: (_) async => playing = null,
    isAndroid: false,
  );
}

void main() {
  group('ReplayGainLibrary', () {
    test('groups songs by album and album artist, ignoring case', () {
      expect(
        ReplayGainLibrary.albumKeyOf(_song('/a.flac')),
        ReplayGainLibrary.albumKeyOf(
          (
            path: '/b.flac',
            album: 'ALBUM',
            albumArtist: 'artist',
            artist: 'Other',
            local: true,
          ),
        ),
      );
      expect(ReplayGainLibrary.albumKeyOf(_song('/c.flac', album: null)), null);
    });

    test('a fingerprint changes when a file or the membership changes', () {
      final stamps = {
        '/a.flac': (size: 10, modified: 1),
        '/b.flac': (size: 20, modified: 2),
      };
      final both = ReplayGainLibrary.fingerprintOf(['/a.flac', '/b.flac'], stamps);
      expect(both, isNotNull);
      expect(ReplayGainLibrary.fingerprintOf(['/a.flac'], stamps), isNot(both));
      stamps['/b.flac'] = (size: 20, modified: 3);
      expect(
        ReplayGainLibrary.fingerprintOf(['/a.flac', '/b.flac'], stamps),
        isNot(both),
      );
      expect(ReplayGainLibrary.fingerprintOf(['/missing.flac'], stamps), null);
    });
  });

  group('ReplayGainIntegrity', () {
    test('keeps a write whose audio hash and size agree', () {
      expect(
        ReplayGainIntegrity.check(
          beforeHash: 'aa',
          afterHash: 'aa',
          sizeBefore: 1000,
          sizeAfter: 1200,
        ),
        isNull,
      );
    });

    test('restores when the audio hash differs or is unknown', () {
      expect(
        ReplayGainIntegrity.check(
          beforeHash: 'aa',
          afterHash: 'bb',
          sizeBefore: 1000,
          sizeAfter: 1000,
        ),
        ReplayGainWriteFailure.audioChanged,
      );
      expect(
        ReplayGainIntegrity.check(
          beforeHash: null,
          afterHash: 'aa',
          sizeBefore: 1000,
          sizeAfter: 1000,
        ),
        ReplayGainWriteFailure.verificationFailed,
      );
    });

    test('restores when the size moves by more than tags explain', () {
      expect(
        ReplayGainIntegrity.check(
          beforeHash: 'aa',
          afterHash: 'aa',
          sizeBefore: 100 * 1024 * 1024,
          sizeAfter: 90 * 1024 * 1024,
        ),
        ReplayGainWriteFailure.audioChanged,
      );
    });
  });

  group('ReplayGainAutoWriter', () {
    test('writes track gain for untagged songs and album gain for the album',
        () async {
      final fake = _Fake([_song('/music/a.flac'), _song('/music/b.flac')])
        ..stamps['/music/a.flac'] = (size: 1, modified: 1)
        ..stamps['/music/b.flac'] = (size: 1, modified: 1)
        ..peaks['/music/a.flac'] = 0.5
        ..peaks['/music/b.flac'] = 0.8;
      fake.writer.configure(_settings());
      await _until(() => fake.albumWrites.length == 2);

      expect(fake.trackWrites, ['/music/a.flac', '/music/b.flac']);
      expect(fake.albumScans, [
        ['/music/a.flac', '/music/b.flac'],
      ]);
      expect(fake.albumWrites, [
        '/music/a.flac -7.00 dB 0.800000',
        '/music/b.flac -7.00 dB 0.800000',
      ]);
      await fake.writer.dispose();
    });

    test('an unchanged album is not measured again', () async {
      final fake = _Fake([_song('/music/a.flac'), _song('/music/b.flac')])
        ..stamps['/music/a.flac'] = (size: 1, modified: 1)
        ..stamps['/music/b.flac'] = (size: 1, modified: 1)
        ..peaks['/music/a.flac'] = 0.5
        ..peaks['/music/b.flac'] = 0.5;
      fake.writer.configure(_settings());
      await _until(() => fake.albumWrites.length == 2);
      fake.writer.refresh();
      for (var i = 0; i < 100; i++) {
        await Future<void>.delayed(Duration.zero);
      }

      expect(fake.albumScans.length, 1);
      await fake.writer.dispose();
    });

    test('adding a song measures the album again over all its files', () async {
      final songs = [_song('/music/a.flac'), _song('/music/b.flac')];
      final fake = _Fake(songs)
        ..stamps['/music/a.flac'] = (size: 1, modified: 1)
        ..stamps['/music/b.flac'] = (size: 1, modified: 1)
        ..stamps['/music/c.flac'] = (size: 1, modified: 1)
        ..peaks['/music/a.flac'] = 0.5
        ..peaks['/music/b.flac'] = 0.5
        ..peaks['/music/c.flac'] = 0.5;
      fake.writer.configure(_settings());
      await _until(() => fake.albumWrites.length == 2);

      songs.add(_song('/music/c.flac'));
      fake.writer.refresh();
      await _until(() => fake.albumScans.length == 2);

      expect(fake.albumScans.last, [
        '/music/a.flac',
        '/music/b.flac',
        '/music/c.flac',
      ]);
      await fake.writer.dispose();
    });

    test('a changed file gets its track gain again', () async {
      final fake = _Fake([_song('/music/a.flac')])
        ..stamps['/music/a.flac'] = (size: 1, modified: 1)
        ..peaks['/music/a.flac'] = 0.5;
      fake.writer.configure(_settings());
      await _until(() => fake.albumWrites.length == 1);
      fake.trackWrites.clear();

      fake.stamps['/music/a.flac'] = (size: 5, modified: 9);
      fake.writer.refresh();
      await _until(() => fake.trackWrites.isNotEmpty);

      expect(fake.trackWrites, ['/music/a.flac']);
      await fake.writer.dispose();
    });

    test('a playing song is skipped and written on a later pass', () async {
      final fake = _Fake([_song('/music/a.flac'), _song('/music/b.flac')])
        ..stamps['/music/a.flac'] = (size: 1, modified: 1)
        ..stamps['/music/b.flac'] = (size: 1, modified: 1)
        ..peaks['/music/a.flac'] = 0.5
        ..peaks['/music/b.flac'] = 0.5
        ..playing = '/music/a.flac';
      fake.writer.configure(_settings());
      await _until(() => fake.albumWrites.length == 2);
      expect(fake.trackWrites, ['/music/b.flac', '/music/a.flac']);
      await fake.writer.dispose();
    });

    test('a failed track write is not retried in the same session', () async {
      var attempts = 0;
      final writer = ReplayGainAutoWriter(
        librarySongs: () async => [_song('/music/a.flac')],
        stamp: (_) async => (size: 1, modified: 1),
        hasTrackTags: (_) async => false,
        writeTrack: (_) async {
          attempts++;
          return const ReplayGainWriteResult.failed(
            ReplayGainWriteFailure.writeFailed,
          );
        },
        state: MemoryReplayGainState(),
        isCharging: () async => true,
        wait: (_) async {},
        isAndroid: false,
      );
      writer.configure(_settings());
      await _until(() => writer.progress.value?.analyzed == 1);
      writer.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(attempts, 1);
      await writer.dispose();
    });

    test('turning the option off clears progress', () async {
      final fake = _Fake([_song('/music/a.flac')])
        ..stamps['/music/a.flac'] = (size: 1, modified: 1);
      fake.writer.configure(_settings());
      fake.writer.configure(const AppSettings());
      expect(fake.writer.progress.value, isNull);
      await fake.writer.dispose();
    });
  });
}
