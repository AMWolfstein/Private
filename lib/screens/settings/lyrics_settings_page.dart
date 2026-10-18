import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'package:spotiflac_android/widgets/app_bottom_sheet.dart';
import 'package:spotiflac_android/widgets/lyrics_size_setting.dart';

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
                  const LyricsSizeSetting(),
                  SettingsSwitchItem(
                    icon: Icons.light_mode_outlined,
                    title: context.l10n.lyricsKeepScreenOn,
                    subtitle: context.l10n.lyricsKeepScreenOnSubtitle,
                    value: settings.keepScreenOnLyrics,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setKeepScreenOnLyrics(value),
                  ),
                  SettingsSwitchItem(
                    icon: Icons.subtitles_outlined,
                    title: context.l10n.optionsEmbedLyrics,
                    subtitle: context.l10n.optionsEmbedLyricsSubtitle,
                    value: settings.embedLyrics,

                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setEmbedLyrics(value),
                    showDivider: settings.embedLyrics,
                  ),
                  if (settings.embedLyrics) ...[
                    SettingsItem(
                      icon: Icons.lyrics_outlined,
                      title: context.l10n.lyricsMode,
                      subtitle: _getLyricsModeLabel(
                        context,
                        settings.lyricsMode,
                      ),
                      onTap: () => _showLyricsModePicker(
                        context,
                        ref,
                        settings.lyricsMode,
                      ),
                      showDivider: false,
                    ),
                  ],
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }

  String _getLyricsModeLabel(BuildContext context, String mode) {
    switch (mode) {
      case 'external':
        return context.l10n.lyricsModeExternal;
      case 'both':
        return context.l10n.lyricsModeBoth;
      default:
        return context.l10n.lyricsModeEmbed;
    }
  }

  void _showLyricsModePicker(
    BuildContext context,
    WidgetRef ref,
    String current,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Text(
                context.l10n.lyricsMode,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
              child: Text(
                context.l10n.lyricsModeDescription,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            AppSheetOption(
              leading: const Icon(Icons.audiotrack),
              title: Text(context.l10n.lyricsModeEmbed),
              subtitle: Text(context.l10n.lyricsModeEmbedSubtitle),
              trailing: current == 'embed' ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setLyricsMode('embed');
                Navigator.pop(context);
              },
            ),
            AppSheetOption(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(context.l10n.lyricsModeExternal),
              subtitle: Text(context.l10n.lyricsModeExternalSubtitle),
              trailing: current == 'external' ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setLyricsMode('external');
                Navigator.pop(context);
              },
            ),
            AppSheetOption(
              leading: const Icon(Icons.library_music_outlined),
              title: Text(context.l10n.lyricsModeBoth),
              subtitle: Text(context.l10n.lyricsModeBothSubtitle),
              trailing: current == 'both' ? const Icon(Icons.check) : null,
              onTap: () {
                ref.read(settingsProvider.notifier).setLyricsMode('both');
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}
