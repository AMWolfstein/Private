import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';

class ReplayGainSettingsPage extends ConsumerWidget {
  const ReplayGainSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final writer = ref.watch(musicPlayerRuntimeProvider).replayGainWriter;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.replayGain),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsSwitchItem(
                  title: context.l10n.replayGainAutoWrite,
                  subtitle: context.l10n.replayGainAutoWriteDescription,
                  value: settings.replayGainAutoWrite,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setReplayGainAutoWrite(v),
                ),
                SettingsSwitchItem(
                  title: context.l10n.replayGainOnlyWhileCharging,
                  subtitle: context.l10n.replayGainOnlyWhileChargingDescription,
                  enabled: settings.replayGainAutoWrite,
                  value: settings.replayGainOnlyWhileCharging,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setReplayGainOnlyWhileCharging(v),
                ),
                ValueListenableBuilder<SongAnalysisProgress?>(
                  valueListenable: writer.progress,
                  builder: (context, progress, _) {
                    final label = progress == null
                        ? null
                        : context.l10n.replayGainProgress(
                            progress.analyzed,
                            progress.total,
                          );
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: LinearProgressIndicator(
                        value: progress == null
                            ? null
                            : progress.total == 0
                            ? 0
                            : progress.analyzed / progress.total,
                        semanticsLabel: label ?? context.l10n.replayGain,
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}
