import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';

void main() {
  test(
    'old Material settings migrate to Mornye, retaining light/dark mode',
    () {
      final theme = ThemeSettings.fromJson({
        kThemeStyleKey: 'material',
        kThemeModeKey: 'dark',
      });
      expect(theme.style, AppThemeStyle.mornye);
      expect(theme.themeMode, ThemeMode.dark);
      expect(const ThemeSettings().style, AppThemeStyle.mornye);
    },
  );

  testWidgets('stale online artwork renders a placeholder', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: CachedCoverImage(
          imageUrl: 'https://example.invalid/artwork.jpg',
          width: 48,
          placeholder: (_, _) => const Text('Local artwork unavailable'),
        ),
      ),
    );
    expect(find.byType(Image), findsNothing);
    expect(find.text('Local artwork unavailable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('cover export copies local files and rejects remote URLs', () async {
    final directory = await Directory.systemTemp.createTemp('offline-artwork-');
    addTearDown(() => directory.delete(recursive: true));
    final source = File('${directory.path}/source.jpg');
    final output = File('${directory.path}/output.jpg');
    await source.writeAsBytes([1, 2, 3]);
    final result = await PlatformBridge.copyLocalCoverToFile(
      source.uri.toString(),
      output.path,
    );
    expect(result['success'], isTrue);
    expect(await output.readAsBytes(), [1, 2, 3]);
    final remote = await PlatformBridge.copyLocalCoverToFile(
      'https://example.invalid/artwork.jpg',
      output.path,
    );
    expect(remote['error'], isNotNull);
    expect(await output.readAsBytes(), [1, 2, 3]);
  });
}
