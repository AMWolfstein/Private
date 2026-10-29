import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/constants/language_choices.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/models/app_glass.dart';
import 'package:sistrum/widgets/glass/app_glass_auto_probe.dart';
import 'package:sistrum/models/theme_settings.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/app_chrome_controls.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/widgets/settings/settings_chips_and_cards.dart';

/// Auto / Lite / Full / Off, in the same control as System / Light / Dark.
class GlassQualitySelector extends ConsumerWidget {
  const GlassQualitySelector({
    super.key,
    required this.current,
    required this.onChanged,
  });

  final AppGlassQuality current;
  final ValueChanged<AppGlassQuality> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final measured =
        ref.watch(
          appGlassAutoStatusProvider(MediaQuery.highContrastOf(context)),
        ) ==
        AppGlassAutoStatus.measured;
    final measuredQuality = switch (ref.watch(appGlassAutoStepProvider)) {
      AppGlassAutoStep.full =>
        ref.watch(appGlassLevelProvider) == AppGlassLevel.liquid
            ? l10n.appearanceGlassQualityFull
            : l10n.appearanceGlassQualityLite,
      AppGlassAutoStep.lite => l10n.appearanceGlassQualityLite,
      AppGlassAutoStep.liteFrosted =>
        '${l10n.appearanceGlassQualityLite} · '
            '${l10n.appearanceGlassLevelFrosted}',
    };
    final labels = {
      AppGlassQuality.auto: l10n.appearanceGlassQualityAuto,
      AppGlassQuality.lite: l10n.appearanceGlassQualityLite,
      AppGlassQuality.full: l10n.appearanceGlassQualityFull,
      AppGlassQuality.off: l10n.appearanceGlassQualityOff,
    };
    return SettingsSearchTarget(
      label: l10n.appearanceGlassQuality,
      child: Padding(
        key: const ValueKey('sistrum-glass-quality'),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.appearanceGlassQuality,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(
              l10n.appearanceGlassQualitySubtitle,
              style: theme.textTheme.bodySmall,
            ),
            AppSegmentedControl(
              labels: labels.values.toList(),
              selectedIndex: labels.keys.toList().indexOf(current),
              onChanged: (index) => onChanged(labels.keys.elementAt(index)),
            ),
            if (measured)
              Text(
                l10n.appearanceGlassAutoMeasured(measuredQuality),
                key: const ValueKey('sistrum-glass-auto-measured'),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AppAccentPicker extends StatelessWidget {
  const AppAccentPicker({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final AppAccent selected;
  final ValueChanged<AppAccent> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final labels = {
      AppAccent.red: l10n.appearanceAccentRed,
      AppAccent.orange: l10n.appearanceAccentOrange,
      AppAccent.green: l10n.appearanceAccentGreen,
      AppAccent.teal: l10n.appearanceAccentTeal,
      AppAccent.blue: l10n.appearanceAccentBlue,
      AppAccent.purple: l10n.appearanceAccentPurple,
      AppAccent.pink: l10n.appearanceAccentPink,
    };
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final accent in AppAccent.values)
            Builder(
              builder: (context) {
                final color = AppTheme.accentColor(
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

class ThemeModeSelector extends StatelessWidget {
  final ThemeMode currentMode;
  final ValueChanged<ThemeMode> onChanged;
  const ThemeModeSelector({
    super.key,
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
        child: AppSegmentedControl(
          labels: labels.values.toList(),
          selectedIndex: labels.keys.toList().indexOf(currentMode),
          onChanged: (index) => onChanged(labels.keys.elementAt(index)),
        ),
      );
    }
  }
}

class PlayerViewSelector extends StatelessWidget {
  final PlayerView currentView;
  final ValueChanged<PlayerView> onChanged;
  const PlayerViewSelector({
    super.key,
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

class LanguageSelector extends StatelessWidget {
  final String currentLocale;
  final ValueChanged<String> onChanged;
  const LanguageSelector({
    super.key,
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
    showAppScrollableBottomSheet<void>(
      context: context,
      title: context.l10n.appearanceLanguage,
      builder: (context, controller) => ListView.builder(
        controller: controller,
        shrinkWrap: true,
        itemCount: supportedLanguageChoices.length,
        itemBuilder: (context, index) {
          final lang = supportedLanguageChoices[index];
          final isSelected = currentLocale == lang.$1;
          return AppSheetOption.choice(
            leading: Icon(
              lang.$3,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurfaceVariant,
            ),
            title: Text(
              lang.$2,
              style: TextStyle(
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            selected: isSelected,
            onTap: () {
              onChanged(lang.$1);
              Navigator.pop(context);
            },
          );
        },
      ),
    );
  }
}
