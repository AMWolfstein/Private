import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/theme_provider.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/custom_font_setting.dart';
import 'package:sistrum/screens/settings/appearance/appearance_glass_clarity_slider.dart';
import 'package:sistrum/screens/settings/appearance/appearance_settings_selectors.dart';

class AppearanceSettingsPage extends ConsumerWidget {
  const AppearanceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Glass clarity changes on every slider tick; keep it out of this page.
    final themeSettings = ref.watch(
      themeProvider.select(
        (s) => (
          appAccent: s.appAccent,
          appGlassOutlines: s.appGlassOutlines,
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
                    AppAccentPicker(
                      selected: themeSettings.appAccent,
                      onChanged: ref.read(themeProvider.notifier).setAppAccent,
                    ),
                    GlassQualitySelector(
                      current: appGlassQualityFromString(settings.glassQuality),
                      onChanged: ref
                          .read(settingsProvider.notifier)
                          .setGlassQuality,
                    ),
                    SettingsSearchTarget(
                      label: context.l10n.appearanceGlassClarity,
                      child: const AppGlassClaritySlider(),
                    ),
                    SettingsSwitchItem(
                      key: const ValueKey('sistrum-glass-outlines'),
                      icon: Icons.rounded_corner,
                      title: context.l10n.appearanceGlassOutlines,
                      subtitle: context.l10n.appearanceGlassOutlinesSubtitle,
                      value: themeSettings.appGlassOutlines,
                      onChanged: ref
                          .read(themeProvider.notifier)
                          .setAppGlassOutlines,
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
                  ThemeModeSelector(
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
                  SettingsSwitchItem(
                    icon: Icons.slow_motion_video_outlined,
                    title: context.l10n.motionArtwork,
                    subtitle: context.l10n.motionArtworkSubtitle,
                    value: settings.animatedAlbumArtwork,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setAnimatedAlbumArtwork(value),
                  ),
                  SettingsSearchTarget(
                    label: context.l10n.appearanceCustomFont,
                    child: const CustomFontSetting(),
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
                  LanguageSelector(
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
                  PlayerViewSelector(
                    currentView: themeSettings.playerView,
                    onChanged: ref.read(themeProvider.notifier).setPlayerView,
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
            const NavBarSliverSpacer(),
          ],
        ),
      ),
    );
  }
}
