import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/providers/custom_font_provider.dart';
import 'package:mornye/providers/theme_provider.dart';
import 'package:mornye/theme/app_theme.dart';

/// Builds the light and dark [AppTheme] for the app. Preferences that change
/// the look (mode, font, accent and glass outlines) rebuild the themes; a
/// stable parent keeps the Navigator and player state across those changes.
class AppThemeWrapper extends ConsumerWidget {
  final Widget Function(ThemeData light, ThemeData dark, ThemeMode mode)
  builder;

  const AppThemeWrapper({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(
      themeProvider.select(
        (s) => (
          themeMode: s.themeMode,
          accent: s.accent,
          useSystemFont: s.useSystemFont,
          glassOutlines: s.glassOutlines,
        ),
      ),
    );
    // Only the family: a rebuild while it loads would animate an equal theme.
    final fontFamily = ref.watch(
      customFontFamilyProvider.select((font) => font.asData?.value),
    );

    return builder(
      AppTheme.build(
        Brightness.light,
        accent: themeSettings.accent,
        useSystemFont: themeSettings.useSystemFont,
        fontFamily: fontFamily,
        glassOutlines: themeSettings.glassOutlines,
      ),
      AppTheme.build(
        Brightness.dark,
        accent: themeSettings.accent,
        useSystemFont: themeSettings.useSystemFont,
        fontFamily: fontFamily,
        glassOutlines: themeSettings.glassOutlines,
      ),
      themeSettings.themeMode,
    );
  }
}
