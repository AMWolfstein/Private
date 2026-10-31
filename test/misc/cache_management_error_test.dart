import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/screens/settings/cache/cache_management_page.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/utils/text/string_utils.dart';
import 'package:sistrum/widgets/status/error_card.dart';

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();
}

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  // Real directory enumeration needs event-loop turns outside fake async.
  // Poll for the completed UI instead of assuming a fixed I/O completion time.
  for (var attempt = 0; attempt < 200 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
  }
  expect(finder, findsOneWidget);
}

void main() {
  testWidgets(
    'first cache overview failure shows an error and Retry recovers',
    (tester) async {
      SharedPreferences.setMockInitialValues({});
      final root = (await tester.runAsync(
        () => Directory.systemTemp.createTemp('cache-overview-test-'),
      ))!;
      addTearDown(() async {
        // This is the unique directory created by this test, never an app path.
        await root.delete(recursive: true);
      });
      final cache = Directory('${root.path}/cache');
      final temporary = Directory('${root.path}/temporary');
      final support = Directory('${root.path}/support');
      await tester.runAsync(() async {
        await cache.create();
        await temporary.create();
        await support.create();
        await File('${cache.path}/entry').writeAsBytes([1, 2, 3]);
        // The audio-analysis row can be cleared, so its bytes are part of the
        // displayed total.
        await Directory('${support.path}/audio_analysis_cache').create();
        await File(
          '${support.path}/audio_analysis_cache/aa.json',
        ).writeAsBytes([1, 2, 3, 4, 5]);
      });

      final firstCachePath = Completer<String?>();
      final retryCachePath = Completer<String?>();
      var cacheReads = 0;
      var supportReads = 0;
      var temporaryReads = 0;
      const paths = MethodChannel('plugins.flutter.io/path_provider');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(paths, (
        call,
      ) async {
        switch (call.method) {
          case 'getApplicationCacheDirectory':
            cacheReads++;
            return cacheReads == 1
                ? firstCachePath.future
                : retryCachePath.future;
          case 'getTemporaryDirectory':
            temporaryReads++;
            return temporary.path;
          case 'getApplicationSupportDirectory':
            supportReads++;
            return support.path;
          case 'getApplicationDocumentsDirectory':
            return root.path;
          default:
            throw StateError('Unexpected path-provider call: ${call.method}');
        }
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          paths,
          null,
        ),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(_Settings.new),
            lowEndDeviceProvider.overrideWithValue(true),
            appLiquidGlassProvider.overrideWithValue(false),
          ],
          child: MaterialApp(
            theme: AppTheme.build(Brightness.light),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: const CacheManagementPage(),
          ),
        ),
      );
      await tester.pump();
      expect(cacheReads, 1);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // Fail only the cache path. The concurrently started support/temporary
      // lookups receive valid directories.
      firstCachePath.completeError(
        PlatformException(
          code: 'cache-unavailable',
          message: 'Cache path failed',
        ),
      );
      await _pumpUntilFound(tester, find.byType(ErrorCard));
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final error = tester.widget<ErrorCard>(find.byType(ErrorCard));
      expect(error.error, contains('Cache path failed'));
      expect(error.onRetry, isNotNull);
      expect(supportReads, greaterThanOrEqualTo(1));
      expect(temporaryReads, 1);
      expect(tester.takeException(), isNull);

      await tester.tap(find.widgetWithText(FilledButton, 'Retry'));
      await tester.pump();
      expect(cacheReads, 2);
      expect(find.byType(ErrorCard), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      retryCachePath.complete(cache.path);

      final strings = AppLocalizations.of(
        tester.element(find.byType(CacheManagementPage)),
      );
      await _pumpUntilFound(tester, find.text(strings.cacheSummaryTitle));
      expect(find.byType(ErrorCard), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // 3 bytes in the app cache + 5 in the audio-analysis cache.
      expect(
        find.text(strings.cacheEstimatedTotal(formatBytes(8))),
        findsOneWidget,
      );
      expect(cacheReads, 2);
      expect(temporaryReads, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
