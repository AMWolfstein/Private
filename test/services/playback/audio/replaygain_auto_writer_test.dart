import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/audio/replaygain_auto_writer.dart';
import 'package:sistrum/services/playback/audio/replaygain_write_result.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis.dart';

AppSettings _settings({required bool onlyWhileCharging}) =>
    const AppSettings().copyWith(
      replayGainAutoWrite: true,
      replayGainOnlyWhileCharging: onlyWhileCharging,
    );

Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  const songs = <SongAnalysisLibrarySong>[
    (path: '/music/tagged.flac', duration: null, local: true),
    (path: '/music/plain.flac', duration: null, local: true),
    (path: 'content://remote/song', duration: null, local: false),
  ];

  test('writes only local songs that have no ReplayGain tags', () async {
    final written = <String>[];
    final writer = ReplayGainAutoWriter(
      librarySongs: () async => songs,
      hasTags: (path) async => path == '/music/tagged.flac',
      write: (path) async {
        written.add(path);
        return const ReplayGainWriteResult.written();
      },
      isCharging: () async => true,
      isAndroid: false,
    );

    writer.configure(_settings(onlyWhileCharging: false));
    await _until(() => writer.progress.value?.analyzed == 2);

    expect(written, ['/music/plain.flac']);
    expect(writer.progress.value?.total, 2);
    expect(writer.progress.value?.analyzed, 2);
    await writer.dispose();
  });

  test('waits for charging before writing when that option is on', () async {
    var charging = false;
    final written = <String>[];
    final writer = ReplayGainAutoWriter(
      librarySongs: () async => songs.sublist(1, 2),
      hasTags: (_) async => false,
      write: (path) async {
        written.add(path);
        return const ReplayGainWriteResult.written();
      },
      isCharging: () async => charging,
      wait: (_) async => charging = true,
      isAndroid: true,
    );

    writer.configure(_settings(onlyWhileCharging: true));
    await _until(() => written.isNotEmpty);

    expect(written, ['/music/plain.flac']);
    await writer.dispose();
  });

  test('a failed write is not retried on the next refresh', () async {
    var attempts = 0;
    final writer = ReplayGainAutoWriter(
      librarySongs: () async => songs.sublist(1, 2),
      hasTags: (_) async => false,
      write: (_) async {
        attempts++;
        return const ReplayGainWriteResult.failed(
          ReplayGainWriteFailure.writeFailed,
        );
      },
      isCharging: () async => true,
      isAndroid: false,
    );

    writer.configure(_settings(onlyWhileCharging: false));
    await _until(() => writer.progress.value?.analyzed == 1);
    writer.refresh();
    await _until(() => writer.progress.value?.analyzed == 1);

    expect(attempts, 1);
    await writer.dispose();
  });

  test('turning the option off stops the sweep and clears progress', () async {
    final writer = ReplayGainAutoWriter(
      librarySongs: () async => songs.sublist(1, 2),
      hasTags: (_) async => false,
      write: (_) async => const ReplayGainWriteResult.written(),
      isCharging: () async => true,
      isAndroid: false,
    );

    writer.configure(_settings(onlyWhileCharging: false));
    writer.configure(const AppSettings());
    expect(writer.progress.value, isNull);
    await writer.dispose();
  });
}
