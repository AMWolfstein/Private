import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/theme_provider.dart';
import 'package:sistrum/providers/custom_font_provider.dart';
import 'package:sistrum/theme/sistrum_theme.dart';

class SistrumThemeWrapper extends ConsumerWidget {
  final Widget Function(ThemeData light, ThemeData dark, ThemeMode mode)
  builder;

  const SistrumThemeWrapper({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Select only what ThemeData needs; glass preferences have their own
    // providers so the clarity slider does not rebuild MaterialApp.
    final accent = ref.watch(themeProvider.select((s) => s.sistrumAccent));
    final useSystemFont = ref.watch(
      themeProvider.select((s) => s.useSystemFont),
    );
    final themeMode = ref.watch(themeProvider.select((s) => s.themeMode));
    final fontFamily = ref.watch(customFontFamilyProvider).asData?.value;

    return builder(
      SistrumTheme.build(
        Brightness.light,
        accent: accent,
        useSystemFont: useSystemFont,
        fontFamily: fontFamily,
      ),
      SistrumTheme.build(
        Brightness.dark,
        accent: accent,
        useSystemFont: useSystemFont,
        fontFamily: fontFamily,
      ),
      themeMode,
    );
  }
}
