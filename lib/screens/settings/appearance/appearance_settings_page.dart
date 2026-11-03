import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/settings/appearance/artist_images_settings_page.dart';
import 'package:sistrum/screens/settings/appearance/video_artwork_settings_page.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/animation/animation_utils.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
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
          appGlassOutlines: s.appGlassOutlines,
          themeMode: s.themeMode,
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
                child: SettingsSectionHeader(
                  title: context.l10n.appearanceGlassQuality,
                ),
              ),
              SliverToBoxAdapter(
                child: SettingsGroup(
                  children: [
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
                    icon: Icons.slow_motion_video_outlined,
                    title: context.l10n.motionArtwork,
                    subtitle: context.l10n.motionArtworkSubtitle,
                    value: settings.animatedAlbumArtwork,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setAnimatedAlbumArtwork(value),
                  ),
                  SettingsItem(
                    icon: Icons.person_search_outlined,
                    title: context.l10n.artistImagesEntryTitle,
                    subtitle: context.l10n.artistImagesEntrySubtitle,
                    onTap: () => Navigator.of(context).push(
                      slidePageRoute<void>(
                        page: const ArtistImagesSettingsPage(),
                      ),
                    ),
                  ),
                  SettingsItem(
                    icon: Icons.movie_outlined,
                    title: context.l10n.videoArtworkEntryTitle,
                    subtitle: context.l10n.videoArtworkEntrySubtitle,
                    onTap: () => Navigator.of(context).push(
                      slidePageRoute<void>(
                        page: const VideoArtworkSettingsPage(),
                      ),
                    ),
                  ),
                  SettingsSwitchItem(
                    icon: Icons.lyrics_outlined,
                    title: context.l10n.lyricsAboveSeekBar,
                    subtitle: context.l10n.lyricsAboveSeekBarSubtitle,
                    value: settings.lyricsAboveSeekBar,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setLyricsAboveSeekBar(value),
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
