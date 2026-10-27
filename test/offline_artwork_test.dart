import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/theme_settings.dart';
import 'package:sistrum/widgets/cached_cover_image.dart';

void main() {
  test(
    'old Material settings migrate to Sistrum, retaining light/dark mode',
    () {
      final theme = ThemeSettings.fromJson({
        'theme_style': 'material',
        kThemeModeKey: 'dark',
      });
      expect(theme.toJson(), isNot(contains('theme_style')));
      expect(theme.themeMode, ThemeMode.dark);
      expect(ThemeSettings.fromJson(theme.toJson()), theme);
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
}
