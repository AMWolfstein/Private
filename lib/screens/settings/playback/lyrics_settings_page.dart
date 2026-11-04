import 'package:flutter/material.dart';
import 'package:sistrum/widgets/lyrics/app_lyrics_timing_setting.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/screens/settings/playback/missing_lyrics_page.dart';
import 'package:sistrum/widgets/animation/animation_utils.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/lyrics/lyrics_size_setting.dart';

class LyricsSettingsPage extends ConsumerWidget {
  const LyricsSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: context.l10n.settingsLyrics),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionLyrics),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsSearchTarget(
                    label: context.l10n.lyricsTextSize,
                    child: const LyricsSizeSetting(),
                  ),
                  const AppLyricsTimingSetting(),
                  SettingsSwitchItem(
                    icon: Icons.light_mode_outlined,
                    title: context.l10n.lyricsKeepScreenOn,
                    subtitle: context.l10n.lyricsKeepScreenOnSubtitle,
                    value: settings.keepScreenOnLyrics,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setKeepScreenOnLyrics(value),
                  ),
                  SettingsItem(
                    icon: Icons.subtitles_outlined,
                    title: context.l10n.lyricsMissingRowTitle,
                    subtitle: context.l10n.lyricsMissingRowSubtitle,
                    onTap: () => Navigator.of(context).push(
                      slidePageRoute<void>(page: const MissingLyricsPage()),
                    ),
                    showDivider: false,
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
