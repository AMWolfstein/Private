import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/lyrics/lrc_sidecar_store.dart';

void main() {
  test('the .lrc path keeps the folder and replaces only the extension', () {
    expect(
      lrcSidecarPath('/music/Album/01 Song.flac'),
      '/music/Album/01 Song.lrc',
    );
    expect(lrcSidecarPath('/music/song.name.mp3'), '/music/song.name.lrc');
  });

  test('the file is written as UTF-8 next to the audio', () async {
    final dir = Directory.systemTemp.createTempSync('lrc_sidecar_test');
    addTearDown(() => dir.deleteSync(recursive: true));

    final result = await const LrcSidecarStore().write(
      '${dir.path}/song.flac',
      '[00:01.00]مرحبا',
      replace: false,
    );

    expect(result.outcome, LrcSidecarOutcome.saved);
    expect(result.path, '${dir.path}/song.lrc');
    expect(File('${dir.path}/song.lrc').readAsStringSync(), '[00:01.00]مرحبا');
  });

  test(
    'an existing file is reported, not overwritten, without replace',
    () async {
      final dir = Directory.systemTemp.createTempSync('lrc_sidecar_test');
      addTearDown(() => dir.deleteSync(recursive: true));
      File('${dir.path}/song.lrc').writeAsStringSync('old');

      final result = await const LrcSidecarStore().write(
        '${dir.path}/song.flac',
        'new',
        replace: false,
      );

      expect(result.outcome, LrcSidecarOutcome.exists);
      expect(File('${dir.path}/song.lrc').readAsStringSync(), 'old');
    },
  );

  test('a write into a missing folder fails with a typed outcome', () async {
    final result = await const LrcSidecarStore().write(
      '/nonexistent-folder-for-test/song.flac',
      'text',
      replace: false,
    );
    expect(result.outcome, LrcSidecarOutcome.failed);
  });
  test(
    'failed replacement preserves the old sidecar and cleans staging',
    () async {
      final dir = await Directory.systemTemp.createTemp('lrc-publish-failed-');
      addTearDown(() => dir.delete(recursive: true));
      final old = await File(
        '${dir.path}/song.lrc',
      ).writeAsString('old lyrics');
      final store = LrcSidecarStore(
        publish: (staged, target) async {
          expect(await staged.readAsString(), 'new lyrics');
          throw const FileSystemException('publication refused');
        },
      );
      final result = await store.write(
        '${dir.path}/song.flac',
        'new lyrics',
        replace: true,
      );
      expect(result.outcome, LrcSidecarOutcome.failed);
      expect(await old.readAsString(), 'old lyrics');
      expect(await dir.list().length, 1);
    },
  );
  test(
    'simultaneous no-replace writers cannot silently replace each other',
    () async {
      final dir = await Directory.systemTemp.createTemp('lrc-claim-');
      addTearDown(() => dir.delete(recursive: true));
      final results = await Future.wait([
        const LrcSidecarStore().write(
          '${dir.path}/song.flac',
          'one',
          replace: false,
        ),
        const LrcSidecarStore().write(
          '${dir.path}/song.flac',
          'two',
          replace: false,
        ),
      ]);
      expect(
        results.where((r) => r.outcome == LrcSidecarOutcome.saved),
        hasLength(1),
      );
      expect(
        results.where((r) => r.outcome == LrcSidecarOutcome.exists),
        hasLength(1),
      );
      expect(
        await File('${dir.path}/song.lrc').readAsString(),
        isIn(['one', 'two']),
      );
      expect(await dir.list().length, 1);
    },
  );
}
