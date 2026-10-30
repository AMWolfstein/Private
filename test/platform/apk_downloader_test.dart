import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/widgets/sheets/update_dialog.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('APK updater resumes a matching partial and verifies SHA-256', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sistrum-updater-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final payload = <int>[
      0x50,
      0x4b,
      0x03,
      0x04,
      ...List.generate(64, (i) => i),
    ];
    const version = '5.0.0';
    const url = 'https://updates.example.test/Sistrum.apk';
    final finalPath = p.join(directory.path, 'Sistrum-$version.apk');
    final part = File('$finalPath.part');
    await part.writeAsBytes(payload.sublist(0, 12));
    await File(
      '$finalPath.part.json',
    ).writeAsString(jsonEncode({'url': url, 'etag': '"release-1"'}));

    final client = MockClient((request) async {
      expect(request.headers['range'], 'bytes=12-');
      expect(request.headers['if-range'], '"release-1"');
      return http.Response.bytes(
        payload.sublist(12),
        206,
        headers: {
          'content-range': 'bytes 12-${payload.length - 1}/${payload.length}',
          'content-length': '${payload.length - 12}',
          'etag': '"release-1"',
        },
        request: request,
      );
    });
    var lastReceived = 0;
    var lastTotal = 0;

    final downloaded = await ApkDownloader.downloadApk(
      url: url,
      version: version,
      expectedSha256: sha256.convert(payload).toString(),
      client: client,
      downloadDirectory: directory,
      onProgress: (received, total) {
        lastReceived = received;
        lastTotal = total;
      },
    );

    expect(downloaded, isA<ApkDownloaded>());
    expect((downloaded as ApkDownloaded).path, finalPath);
    expect(await File(finalPath).readAsBytes(), payload);
    expect(lastReceived, payload.length);
    expect(lastTotal, payload.length);
    expect(await part.exists(), isFalse);
    expect(await File('$finalPath.part.json').exists(), isFalse);
  });

  test('a digest mismatch discards the download', () async {
    final directory = await Directory.systemTemp.createTemp(
      'sistrum-updater-mismatch-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final payload = <int>[0x50, 0x4b, 0x03, 0x04, 1, 2, 3];
    final client = MockClient(
      (request) async => http.Response.bytes(payload, 200, request: request),
    );
    final rejected = await ApkDownloader.downloadApk(
      url: 'https://updates.example.test/update.apk',
      version: 'mismatch',
      expectedSha256: '0' * 64,
      client: client,
      downloadDirectory: directory,
    );
    expect(
      rejected,
      isA<ApkDownloadFailed>().having(
        (failed) => failed.reason,
        'reason',
        ApkDownloadFailure.digestMismatch,
      ),
    );
    expect(
      await File('${directory.path}/Sistrum-mismatch.apk').exists(),
      false,
    );
    expect(
      await File('${directory.path}/Sistrum-mismatch.apk.part').exists(),
      false,
    );
  });

  test('plain HTTP URLs are refused', () async {
    expect(
      await ApkDownloader.downloadApk(
        url: 'http://updates.example.test/update.apk',
        version: '1',
      ),
      isA<ApkDownloadFailed>().having(
        (failed) => failed.reason,
        'reason',
        ApkDownloadFailure.invalidUrl,
      ),
    );
  });
}
