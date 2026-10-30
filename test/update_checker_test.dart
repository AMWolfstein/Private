import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/services/update_checker.dart';
import 'package:sistrum/utils/logger.dart';

Map<String, Object?> release(String version) => {
  'tag_name': 'v$version',
  'prerelease': false,
  'draft': false,
  'body': '- Release notes',
  'published_at': '2026-09-26T06:32:33Z',
  'html_url': 'https://github.com/amwolfstein/private/releases/tag/v$version',
  'assets': [
    for (final abi in ['arm32', 'arm64'])
      {
        'name': 'Sistrum-v$version-$abi.apk',
        'browser_download_url':
            'https://example.test/Sistrum-v$version-$abi.apk',
        'digest': 'sha256:${List.filled(64, 'a').join()}',
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LogBuffer().clear();
  });

  for (final (abi, asset) in [
    ('arm64-v8a', 'arm64'),
    ('armeabi-v7a', 'arm32'),
  ]) {
    test('5.0.0 discovers 5.0.5 despite a recent cache ($abi)', () async {
      SharedPreferences.setMockInitialValues({
        'update_checker_releases_json': jsonEncode([release('5.0.0')]),
        'update_checker_releases_fetched_at':
            DateTime.now().millisecondsSinceEpoch,
        'update_checker_releases_etag': '"old-release-list"',
      });
      var requests = 0;
      final checker = UpdateChecker(
        installedVersion: '5.0.0',
        isAndroid: true,
        supportedAbis: [abi],
        client: MockClient((request) async {
          requests++;
          expect(request.headers['If-None-Match'], '"old-release-list"');
          return http.Response(
            jsonEncode([release('5.0.5'), release('5.0.0')]),
            200,
            headers: {'etag': '"new-release-list"'},
          );
        }),
      );

      final update = await checker.checkForUpdate();
      expect(requests, 1);
      expect(update?.version, '5.0.5');
      expect(update?.apkDownloadUrl, endsWith('v5.0.5-$asset.apk'));
      expect(update?.releasesBehind, 1);
      expect(update?.apkSha256, List.filled(64, 'a').join());
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('update_checker_releases_etag'),
        '"new-release-list"',
      );
      expect(
        prefs.getString('update_checker_releases_json'),
        contains('v5.0.5'),
      );
    });
  }

  test(
    'checks again immediately and reuses the body only after GitHub 304',
    () async {
      var requests = 0;
      final checker = UpdateChecker(
        installedVersion: '5.0.0',
        isAndroid: true,
        supportedAbis: ['arm64-v8a'],
        client: MockClient((request) async {
          requests++;
          if (requests == 1) {
            expect(request.headers['If-None-Match'], isNull);
            return http.Response(
              jsonEncode([release('5.0.5')]),
              200,
              headers: {'etag': '"fresh"'},
            );
          }
          expect(request.headers['If-None-Match'], '"fresh"');
          return http.Response('', 304);
        }),
      );
      expect((await checker.checkForUpdate())?.version, '5.0.5');
      expect((await checker.checkForUpdate())?.version, '5.0.5');
      expect(requests, 2);
    },
  );

  test(
    'replacing a body without an ETag removes the previous validator',
    () async {
      SharedPreferences.setMockInitialValues({
        'update_checker_releases_json': jsonEncode([release('5.0.0')]),
        'update_checker_releases_etag': '"old"',
      });
      final checker = UpdateChecker(
        installedVersion: '5.0.0',
        isAndroid: true,
        supportedAbis: ['arm64-v8a'],
        client: MockClient(
          (_) async => http.Response(jsonEncode([release('5.0.5')]), 200),
        ),
      );
      expect((await checker.checkForUpdate())?.version, '5.0.5');
      expect(
        (await SharedPreferences.getInstance()).getString(
          'update_checker_releases_etag',
        ),
        isNull,
      );
    },
  );

  for (final failure in ['offline', 'rate limit', 'invalid JSON']) {
    test('$failure does not claim cached 5.0.0 is the latest online', () async {
      final cachedBody = jsonEncode([release('5.0.0')]);
      SharedPreferences.setMockInitialValues({
        'update_checker_releases_json': cachedBody,
        'update_checker_releases_etag': '"cached"',
      });
      final checker = UpdateChecker(
        installedVersion: '5.0.0',
        isAndroid: true,
        supportedAbis: ['arm64-v8a'],
        client: MockClient((_) async {
          if (failure == 'offline') throw http.ClientException('Offline');
          if (failure == 'rate limit') return http.Response('Limited', 403);
          return http.Response('{"message":"Invalid response"}', 200);
        }),
      );
      await expectLater(
        checker.checkForUpdate(),
        throwsA(isA<UpdateCheckException>()),
      );
      final messages = LogBuffer().entries
          .map((entry) => entry.message)
          .join('\n');
      expect(messages, contains('could not be verified'));
      expect(messages, isNot(contains('No update available')));
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('update_checker_releases_json'), cachedBody);
      expect(prefs.getString('update_checker_releases_etag'), '"cached"');
    });
  }

  test(
    'an unreachable release list without a cache reports a failure',
    () async {
      final checker = UpdateChecker(
        installedVersion: '5.0.0',
        isAndroid: true,
        client: MockClient((_) async => throw http.ClientException('Offline')),
      );
      await expectLater(
        checker.checkForUpdate(),
        throwsA(isA<UpdateCheckException>()),
      );
    },
  );

  test(
    'an offline check can still offer a previously discovered update',
    () async {
      SharedPreferences.setMockInitialValues({
        'update_checker_releases_json': jsonEncode([release('5.0.5')]),
      });
      final checker = UpdateChecker(
        installedVersion: '5.0.0',
        isAndroid: true,
        supportedAbis: ['armeabi-v7a'],
        client: MockClient((_) async => throw http.ClientException('Offline')),
      );
      expect((await checker.checkForUpdate())?.version, '5.0.5');
    },
  );

  test(
    'invalid stored JSON does not send its ETag or block fresh releases',
    () async {
      SharedPreferences.setMockInitialValues({
        'update_checker_releases_json': '{broken',
        'update_checker_releases_etag': '"broken"',
      });
      final checker = UpdateChecker(
        installedVersion: '5.0.0',
        isAndroid: true,
        supportedAbis: ['arm64-v8a'],
        client: MockClient((request) async {
          expect(request.headers['If-None-Match'], isNull);
          return http.Response(jsonEncode([release('5.0.5')]), 200);
        }),
      );
      expect((await checker.checkForUpdate())?.version, '5.0.5');
    },
  );

  test('stable skips previews and counts only newer stable releases', () async {
    final checker = UpdateChecker(
      installedVersion: '4.9.5',
      isAndroid: true,
      supportedAbis: ['arm64-v8a'],
      client: MockClient(
        (_) async => http.Response(
          jsonEncode([
            {...release('5.0.6-preview'), 'prerelease': true},
            release('5.0.5'),
            release('5.0.0'),
            release('4.9.6'),
            release('4.9.5'),
          ]),
          200,
        ),
      ),
    );
    final stable = await checker.checkForUpdate();
    expect(stable?.version, '5.0.5');
    expect(stable?.releasesBehind, UpdateChecker.forceUpdateThreshold);
    expect(
      (await checker.checkForUpdate(channel: 'preview'))?.version,
      '5.0.6-preview',
    );
  });

  test(
    'an installed 5.0.5 does not prompt to reinstall the same version',
    () async {
      final checker = UpdateChecker(
        installedVersion: '5.0.5',
        isAndroid: true,
        client: MockClient(
          (_) async => http.Response(jsonEncode([release('5.0.5')]), 200),
        ),
      );
      expect(await checker.checkForUpdate(), isNull);
    },
  );

  test('non-Android platforms do not request or offer an APK', () async {
    final checker = UpdateChecker(
      installedVersion: '5.0.0',
      isAndroid: false,
      client: MockClient(
        (_) async => throw StateError('Unexpected network request'),
      ),
    );
    expect(await checker.checkForUpdate(), isNull);
  });
}
