import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/providers/custom_font_provider.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';

class MornyeThemeWrapper extends ConsumerWidget {
  final Widget Function(ThemeData light, ThemeData dark, ThemeMode mode)
  builder;

  const MornyeThemeWrapper({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeProvider);
    final fontFamily = ref.watch(customFontFamilyProvider).asData?.value;

    return builder(
      MornyeTheme.build(
        Brightness.light,
        accent: themeSettings.mornyeAccent,
        useSystemFont: themeSettings.useSystemFont,
        fontFamily: fontFamily,
        glassClarity: themeSettings.mornyeGlassClarity,
        glassOutlines: themeSettings.mornyeGlassOutlines,
      ),
      MornyeTheme.build(
        Brightness.dark,
        accent: themeSettings.mornyeAccent,
        useSystemFont: themeSettings.useSystemFont,
        fontFamily: fontFamily,
        glassClarity: themeSettings.mornyeGlassClarity,
        glassOutlines: themeSettings.mornyeGlassOutlines,
      ),
      themeSettings.themeMode,
    );
  }
}
