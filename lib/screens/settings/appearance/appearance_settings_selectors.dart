import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/constants/language_choices.dart';
import 'package:sistrum/core/models/theme_settings.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/widgets/settings/settings_chips_and_cards.dart';
import 'package:sistrum/widgets/primitives/app_selection_controls.dart';

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

/// System plus the rates Android reports at the current resolution. A saved
/// rate the display lacks stays listed, so the choice is never silently lost.
List<int> displayRefreshChoices(int preferenceHz, List<int> supportedRates) => [
  0,
  ...{...supportedRates, if (preferenceHz > 0) preferenceHz}.toList()..sort(),
];

class DisplayRefreshRateSelector extends StatelessWidget {
  const DisplayRefreshRateSelector({
    super.key,
    required this.preferenceHz,
    required this.state,
    required this.onChanged,
  });

  /// Saved choice in whole Hz; 0 is System Default.
  final int preferenceHz;
  final DisplayRefreshState state;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final choices = displayRefreshChoices(preferenceHz, state.supportedRates);
    String label(int hz) =>
        hz == 0 ? l10n.displayRefreshRateSystem : l10n.displayRefreshRateHz(hz);
    final status = displayRefreshStatus(preferenceHz, state);
    final active = state.attached && state.activeModeHz > 0
        ? l10n.displayRefreshRateHz(state.activeModeHz.round())
        : '—';
    final statusText = switch (status) {
      DisplayRefreshStatus.systemDefault => null,
      DisplayRefreshStatus.requested => l10n.displayRefreshRateStatusRequested,
      DisplayRefreshStatus.active => l10n.displayRefreshRateStatusActive,
      DisplayRefreshStatus.notApplied =>
        l10n.displayRefreshRateStatusNotApplied,
      DisplayRefreshStatus.unsupported =>
        l10n.displayRefreshRateStatusUnsupported,
      DisplayRefreshStatus.unavailable =>
        l10n.displayRefreshRateStatusUnavailable,
    };
    final style = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    return SettingsSearchTarget(
      label: l10n.displayRefreshRate,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.displayRefreshRateSubtitle, style: style),
            AppSegmentedControl(
              labels: [for (final hz in choices) label(hz)],
              selectedIndex: choices.indexOf(preferenceHz),
              onChanged: (index) => onChanged(choices[index]),
            ),
            Text(
              l10n.displayRefreshRateSelected(label(preferenceHz)),
              style: style,
            ),
            Text(l10n.displayRefreshRateActive(active), style: style),
            if (statusText != null) Text(statusText, style: style),
            if (state.powerSaveMode && preferenceHz > 0)
              Text(l10n.displayRefreshRateBatterySaver, style: style),
          ],
        ),
      ),
    );
  }
}
