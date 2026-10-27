import 'dart:io';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/utils/file_access.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.amwolfstein.sistrum/backend');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  tearDown(() => messenger.setMockMethodCallHandler(channel, null));
  group('local stat OS boundary', () {
    late Directory temporary;
    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('file_stat_boundary_');
    });
    tearDown(() async {
      await temporary.delete(recursive: true);
    });
    test('found and CUE backing files retain actual stat metadata', () async {
      final file = await File(
        '${temporary.path}/album.cue',
      ).writeAsString('CUE fixture');
      final expected = await file.stat();
      final result = await fileStat('${file.path}#track01');
      expect(result?.size, expected.size);
      expect(result?.modified, expected.modified);
    });
    test('ENOENT and ENOTDIR are confirmed missing', () async {
      final file = await File(
        '${temporary.path}/track.flac',
      ).writeAsString('audio');
      expect(await fileStat('${temporary.path}/removed.flac'), isNull);
      expect(await fileStat('${file.path}/child.flac'), isNull);
    });
    test('symlink loop propagates rather than reporting absence', () async {
      final path = '${temporary.path}/loop.flac';
      await Link(path).create(path);
      await expectLater(fileStat(path), throwsA(isA<FileSystemException>()));
    }, skip: Platform.isWindows);
    test(
      'permission denial is not reported as confirmed absence',
      () async {
        final file = await File(
          '${temporary.path}/locked.flac',
        ).writeAsString('fixture');
        expect(
          (await Process.run('chmod', ['000', temporary.path])).exitCode,
          0,
        );
        try {
          await expectLater(
            fileStat(file.path),
            throwsA(isA<FileSystemException>()),
          );
        } finally {
          await Process.run('chmod', ['700', temporary.path]);
        }
      },
      skip:
          Platform.isWindows ||
          Process.runSync('id', ['-u']).stdout.toString().trim() == '0',
    );
  });
  test('empty paths avoid provider calls', () async {
    messenger.setMockMethodCallHandler(channel, (_) async {
      fail('No provider call expected');
    });
    expect(await fileStat(null), isNull);
    expect(await fileStat(''), isNull);
  });
  test('SAF CUE stat queries once and preserves nullable metadata', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return '{"exists":true,"size":null,"modified":null}';
    });
    const uri = 'content://example.documents/tree/root/document/album%2Fcue';
    final result = await fileStat('$uri#track02');
    expect(result, isNotNull);
    expect(result!.size, isNull);
    expect(result.modified, isNull);
    expect(calls.map((c) => c.method), ['safStat']);
    expect(calls.single.arguments, {'uri': uri});
  });
  test('SAF confirmed absence is missing', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (_) async => '{"exists":false}',
    );
    expect(
      await fileStat('content://example.documents/document/removed'),
      isNull,
    );
  });
  for (final code in ['permission_denied', 'provider_unavailable']) {
    test('SAF $code propagates', () async {
      messenger.setMockMethodCallHandler(channel, (_) async {
        throw PlatformException(code: code);
      });
      await expectLater(
        fileStat('content://example.documents/document/song'),
        throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
      );
    });
  }
}
