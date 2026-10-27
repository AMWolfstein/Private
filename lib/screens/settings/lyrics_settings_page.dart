import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/widgets/settings_group.dart';
import 'package:sistrum/widgets/app_sliver_header.dart';
import 'package:sistrum/widgets/lyrics_size_setting.dart';

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
                  SettingsSwitchItem(
                    icon: Icons.light_mode_outlined,
                    title: context.l10n.lyricsKeepScreenOn,
                    subtitle: context.l10n.lyricsKeepScreenOnSubtitle,
                    value: settings.keepScreenOnLyrics,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setKeepScreenOnLyrics(value),
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
