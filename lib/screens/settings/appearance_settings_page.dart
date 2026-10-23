import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/theme_provider.dart';
import 'package:spotiflac_android/models/mornye_glass.dart';
import 'package:spotiflac_android/services/mornye_glass_auto_probe.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/custom_font_setting.dart';
import 'package:spotiflac_android/widgets/mornye_slider.dart';

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
                    _GlassQualitySelector(
                      current: mornyeGlassQualityFromString(
                        settings.glassQuality,
                      ),
                      onChanged: ref
                          .read(settingsProvider.notifier)
                          .setGlassQuality,
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

class _MornyeGlassClaritySlider extends ConsumerStatefulWidget {
  const _MornyeGlassClaritySlider();

  @override
  ConsumerState<_MornyeGlassClaritySlider> createState() =>
      _MornyeGlassClaritySliderState();
}

class _MornyeGlassClaritySliderState
    extends ConsumerState<_MornyeGlassClaritySlider> {
  /// Only the preview follows a drag; the rest of the app updates on release.
  int? _dragLevel;

  @override
  Widget build(BuildContext context) {
    // The saved level; glass may render lower where Auto measured it.
    final int level =
        _dragLevel ??
        ref.watch(settingsProvider.select((s) => s.glassClarityLevel));
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // Match the renderer's policy without changing the stored clarity value.
    final contrastBlocked = ref.watch(
      mornyeGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );
    final quality = ref.watch(mornyeGlassQualityProvider);
    // Auto measured that this device needs Level 1.
    final autoFrosted =
        quality == MornyeGlassQuality.auto &&
        ref.watch(mornyeGlassClarityLevelProvider) == 1 &&
        ref.watch(mornyeGlassAutoStepProvider) ==
            MornyeGlassAutoStep.liteFrosted;
    final adjustable =
        !contrastBlocked &&
        ref.watch(mornyeBlurEnabledProvider) &&
        !autoFrosted;
    final levelNames = [
      l10n.appearanceGlassLevelFrosted,
      l10n.appearanceGlassLevelSoft,
      l10n.appearanceGlassLevelBalanced,
      l10n.appearanceGlassLevelClear,
      l10n.appearanceGlassLevelCrystal,
    ];
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
                  ? l10n.appearanceGlassClarityContrast
                  : autoFrosted
                  ? l10n.appearanceGlassClarityAutoFrosted
                  : quality == MornyeGlassQuality.off
                  ? l10n.appearanceGlassClarityOff
                  : l10n.appearanceGlassClarityDeviceOpaque,
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
                      clarityLevel: level,
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
              child: MornyeSlider(
                key: const ValueKey('mornye-glass-clarity'),
                value: level.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: levelNames[level - 1],
                semanticFormatterCallback: (value) =>
                    levelNames[value.round().clamp(1, 5) - 1],
                onChanged: adjustable
                    ? (value) => setState(() => _dragLevel = value.round())
                    : null,
                onChangeEnd: adjustable
                    ? (value) {
                        // Commit, persist and update the app in a single step.
                        notifier.setGlassClarityLevel(value.round());
                        setState(() => _dragLevel = null);
                      }
                    : null,
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
          // Only full Crystal glass costs noticeably more to render.
          if (adjustable &&
              level == 5 &&
              ref.watch(mornyeGlassLevelProvider) ==
                  MornyeGlassLevel.liquid) ...[
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

/// Auto / Lite / Full / Off, in the same control as System / Light / Dark.
class _GlassQualitySelector extends ConsumerWidget {
  const _GlassQualitySelector({required this.current, required this.onChanged});

  final MornyeGlassQuality current;
  final ValueChanged<MornyeGlassQuality> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final measured =
        ref.watch(
          mornyeGlassAutoStatusProvider(MediaQuery.highContrastOf(context)),
        ) ==
        MornyeGlassAutoStatus.measured;
    final measuredQuality = switch (ref.watch(mornyeGlassAutoStepProvider)) {
      MornyeGlassAutoStep.full =>
        ref.watch(mornyeGlassLevelProvider) == MornyeGlassLevel.liquid
            ? l10n.appearanceGlassQualityFull
            : l10n.appearanceGlassQualityLite,
      MornyeGlassAutoStep.lite => l10n.appearanceGlassQualityLite,
      MornyeGlassAutoStep.liteFrosted =>
        '${l10n.appearanceGlassQualityLite} · '
            '${l10n.appearanceGlassLevelFrosted}',
    };
    final labels = {
      MornyeGlassQuality.auto: l10n.appearanceGlassQualityAuto,
      MornyeGlassQuality.lite: l10n.appearanceGlassQualityLite,
      MornyeGlassQuality.full: l10n.appearanceGlassQualityFull,
      MornyeGlassQuality.off: l10n.appearanceGlassQualityOff,
    };
    return SettingsSearchTarget(
      label: l10n.appearanceGlassQuality,
      child: Padding(
        key: const ValueKey('mornye-glass-quality'),
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
            MornyeSegmentedControl(
              labels: labels.values.toList(),
              selectedIndex: labels.keys.toList().indexOf(current),
              onChanged: (index) => onChanged(labels.keys.elementAt(index)),
            ),
            if (measured)
              Text(
                l10n.appearanceGlassAutoMeasured(measuredQuality),
                key: const ValueKey('mornye-glass-auto-measured'),
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
