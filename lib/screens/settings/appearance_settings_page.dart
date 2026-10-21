import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/constants/language_choices.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/custom_font_setting.dart';

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Glass clarity changes on every slider tick; keep it out of this page.
    final themeSettings = ref.watch(
      themeProvider.select(
        (s) => (
          mornyeAccent: s.mornyeAccent,
          mornyeGlassOutlines: s.mornyeGlassOutlines,
          themeMode: s.themeMode,
          useSystemFont: s.useSystemFont,
          playerView: s.playerView,
        ),
      ),
    );
    final settings = ref.watch(settingsProvider);

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: context.l10n.appearanceTitle),

            ...[
              SliverToBoxAdapter(
                child: SettingsSectionHeader(title: context.l10n.sectionColor),
              ),
              SliverToBoxAdapter(
                child: SettingsGroup(
                  children: [
                    _MornyeAccentPicker(
                      selected: themeSettings.mornyeAccent,
                      onChanged: ref
                          .read(themeProvider.notifier)
                          .setMornyeAccent,
                    ),
                    const _MornyeGlassClaritySlider(),
                    SettingsSwitchItem(
                      key: const ValueKey('mornye-glass-outlines'),
                      icon: Icons.rounded_corner,
                      title: context.l10n.appearanceGlassOutlines,
                      subtitle: context.l10n.appearanceGlassOutlinesSubtitle,
                      value: themeSettings.mornyeGlassOutlines,
                      onChanged: ref
                          .read(themeProvider.notifier)
                          .setMornyeGlassOutlines,
                      showDivider: false,
                    ),
                  ],
                ),
              ),
            ],

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionTheme),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  _ThemeModeSelector(
                    currentMode: themeSettings.themeMode,
                    onChanged: (mode) =>
                        ref.read(themeProvider.notifier).setThemeMode(mode),
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsSwitchItem(
                    icon: Icons.font_download_outlined,
                    title: context.l10n.appearanceUseSystemFont,
                    subtitle: context.l10n.appearanceUseSystemFontSubtitle,
                    value: themeSettings.useSystemFont,
                    onChanged: ref
                        .read(themeProvider.notifier)
                        .setUseSystemFont,
                  ),
                  SettingsSwitchItem(
                    icon: Icons.animation,
                    title: context.l10n.appearanceHeroAnimations,
                    subtitle: context.l10n.appearanceHeroAnimationsSubtitle,
                    value: settings.heroAnimationsEnabled,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setHeroAnimationsEnabled(value),
                  ),
                  const CustomFontSetting(),
                  SettingsSwitchItem(
                    icon: Icons.blur_on,
                    title: context.l10n.appearanceForceBlur,
                    subtitle: context.l10n.appearanceForceBlurSubtitle,
                    value: settings.forceBackdropBlur,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setForceBackdropBlur(value),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionLanguage),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  _LanguageSelector(
                    currentLocale: settings.locale,
                    onChanged: (locale) =>
                        ref.read(settingsProvider.notifier).setLocale(locale),
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.appearancePlayerView,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  _PlayerViewSelector(
                    currentView: themeSettings.playerView,
                    onChanged: ref.read(themeProvider.notifier).setPlayerView,
                  ),
                ],
              ),
            ),

            const SliverFillRemaining(
              hasScrollBody: false,
              child: SizedBox(height: 32),
            ),
          ],
        ),
      ),
    );
  }
}

class _MornyeGlassClaritySlider extends ConsumerWidget {
  const _MornyeGlassClaritySlider();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final clarity = ref.watch(
      themeProvider.select((settings) => settings.mornyeGlassClarity),
    );
    final notifier = ref.read(themeProvider.notifier);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // Match the renderer's policy without changing the stored clarity value.
    final contrastBlocked = ref.watch(
      mornyeGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );
    final adjustable = !contrastBlocked && ref.watch(mornyeBlurEnabledProvider);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.appearanceGlassClarity, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            l10n.appearanceGlassClaritySubtitle,
            style: theme.textTheme.bodySmall,
          ),
          if (!adjustable) ...[
            const SizedBox(height: 8),
            Text(
              contrastBlocked
                  ? l10n.appearanceGlassClarityHighContrast(
                      l10n.appearanceForceBlur,
                    )
                  : l10n.appearanceGlassClarityBlurOff(
                      l10n.appearanceForceBlur,
                    ),
              key: const ValueKey('mornye-glass-clarity-unavailable'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Separate layers: the thumb animation must not repaint the glass
          // preview, and preview blur must not repaint the slider.
          RepaintBoundary(
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        for (final color in [
                          theme.colorScheme.primary,
                          const Color(0xff277f94),
                          const Color(0xffc69756),
                        ])
                          // Preview light glass over a light backdrop, as in the
                          // app. Dense sample colors make white glass look gray.
                          theme.brightness == Brightness.light
                              ? Color.lerp(Colors.white, color, 0.4)!
                              : color,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: MornyeGlassPanel(
                      radius: 22,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.music_note_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Mornye',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const Icon(Icons.play_arrow_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          RepaintBoundary(
            child: Semantics(
              label: l10n.appearanceGlassClarity,
              child: Slider(
                key: const ValueKey('mornye-glass-clarity'),
                value: clarity,
                divisions: 20,
                label: '${(clarity * 100).round()}%',
                onChanged: adjustable
                    ? (value) =>
                          notifier.setMornyeGlassClarity(value, persist: false)
                    : null,
                onChangeEnd: adjustable ? notifier.setMornyeGlassClarity : null,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.appearanceGlassTinted,
                style: theme.textTheme.bodySmall,
              ),
              Text(l10n.appearanceGlassClear, style: theme.textTheme.bodySmall),
            ],
          ),
          if (adjustable && clarity >= 0.9) ...[
            const SizedBox(height: 8),
            Text(
              l10n.appearanceGlassClearPerformance,
              key: const ValueKey('mornye-glass-clear-performance'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MornyeAccentPicker extends StatelessWidget {
  const _MornyeAccentPicker({required this.selected, required this.onChanged});

  final MornyeAccent selected;
  final ValueChanged<MornyeAccent> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      MornyeAccent.red: l10n.appearanceAccentRed,
      MornyeAccent.orange: l10n.appearanceAccentOrange,
      MornyeAccent.green: l10n.appearanceAccentGreen,
      MornyeAccent.teal: l10n.appearanceAccentTeal,
      MornyeAccent.blue: l10n.appearanceAccentBlue,
      MornyeAccent.purple: l10n.appearanceAccentPurple,
      MornyeAccent.pink: l10n.appearanceAccentPink,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final accent in MornyeAccent.values)
            Builder(
              builder: (context) {
                final color = MornyeTheme.accentColor(
                  accent,
                  Theme.of(context).brightness,
                );
                final foreground =
                    ThemeData.estimateBrightnessForColor(color) ==
                        Brightness.dark
                    ? Colors.white
                    : Colors.black;
                return Semantics(
                  selected: selected == accent,
                  child: IconButton(
                    tooltip: labels[accent],
                    onPressed: () => onChanged(accent),
                    style: IconButton.styleFrom(
                      backgroundColor: color,
                      foregroundColor: foreground,
                      minimumSize: const Size.square(48),
                    ),
                    icon: selected == accent
                        ? const Icon(Icons.check)
                        : const SizedBox.square(dimension: 24),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ThemeModeSelector extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onChanged;
  const _ThemeModeSelector({
    required this.currentMode,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    {
      final labels = {
        ThemeMode.system: context.l10n.appearanceThemeSystem,
        ThemeMode.light: context.l10n.appearanceThemeLight,
        ThemeMode.dark: context.l10n.appearanceThemeDark,
      };
      return Padding(
        padding: const EdgeInsets.all(12),
        child: MornyeSegmentedControl(
          labels: labels.values.toList(),
          selectedIndex: labels.keys.toList().indexOf(currentMode),
          onChanged: (index) => onChanged(labels.keys.elementAt(index)),
        ),
      );
    }
  }
}

class _PlayerViewSelector extends StatelessWidget {
  final PlayerView currentView;
  final ValueChanged<PlayerView> onChanged;
  const _PlayerViewSelector({
    required this.currentView,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) => SettingsSearchTarget(
    label: context.l10n.appearancePlayerView,
    child: Padding(
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          for (final view in PlayerView.values) ...[
            if (view != PlayerView.normal) const SizedBox(width: 8),
            SettingsChoiceChip(
              expand: true,
              layout: SettingsChipLayout.column,
              icon: view == PlayerView.normal
                  ? Icons.crop_square
                  : Icons.fullscreen,
              label: view == PlayerView.normal
                  ? context.l10n.appearancePlayerViewNormal
                  : context.l10n.appearancePlayerViewImmersive,
              isSelected: currentView == view,
              onTap: () => onChanged(view),
            ),
          ],
        ],
      ),
    ),
  );
}

class _LanguageSelector extends StatelessWidget {
  final String currentLocale;
  final ValueChanged<String> onChanged;
  const _LanguageSelector({
    required this.currentLocale,
    required this.onChanged,
  });

  String _getLanguageName(String code) {
    for (final lang in appLanguageChoices) {
      if (lang.$1 == code) return lang.$2;
    }
    return code;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final content = ListTile(
      leading: null,
      title: Text(context.l10n.appearanceLanguage),
      subtitle: Text(_getLanguageName(currentLocale)),
      trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
      onTap: () => _showLanguagePicker(context),
    );
    return SettingsSearchTarget(
      label: context.l10n.appearanceLanguage,
      child: content,
    );
  }

  void _showLanguagePicker(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surface,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                context.l10n.appearanceLanguage,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: supportedLanguageChoices.length,
                itemBuilder: (context, index) {
                  final lang = supportedLanguageChoices[index];
                  final isSelected = currentLocale == lang.$1;
                  return AppSheetOption(
                    leading: Icon(
                      lang.$3,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurfaceVariant,
                    ),
                    title: Text(
                      lang.$2,
                      style: TextStyle(
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                        fontWeight: isSelected
                            ? FontWeight.w600
                            : FontWeight.normal,
                      ),
                    ),
                    trailing: isSelected
                        ? Icon(Icons.check, color: colorScheme.primary)
                        : null,
                    onTap: () {
                      onChanged(lang.$1);
                      Navigator.pop(context);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
