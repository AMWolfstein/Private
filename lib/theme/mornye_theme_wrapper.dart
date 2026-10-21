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
    // Select only what ThemeData needs; glass preferences have their own
    // providers so the clarity slider does not rebuild MaterialApp.
    final accent = ref.watch(themeProvider.select((s) => s.mornyeAccent));
    final useSystemFont = ref.watch(
      themeProvider.select((s) => s.useSystemFont),
    );
    final themeMode = ref.watch(themeProvider.select((s) => s.themeMode));
    final fontFamily = ref.watch(customFontFamilyProvider).asData?.value;

    return builder(
      MornyeTheme.build(
        Brightness.light,
        accent: accent,
        useSystemFont: useSystemFont,
        fontFamily: fontFamily,
      ),
      MornyeTheme.build(
        Brightness.dark,
        accent: accent,
        useSystemFont: useSystemFont,
        fontFamily: fontFamily,
      ),
      themeMode,
    );
  }
}
