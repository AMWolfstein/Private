import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/playback/song_analysis_provider.dart';
import 'package:sistrum/services/playback/autoplay/song_analysis.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';

class SongAnalysisSettingsPage extends ConsumerStatefulWidget {
  const SongAnalysisSettingsPage({super.key});
  @override
  ConsumerState<SongAnalysisSettingsPage> createState() =>
      _SongAnalysisSettingsPageState();
}

class _SongAnalysisSettingsPageState
    extends ConsumerState<SongAnalysisSettingsPage> {
  bool _clearing = false;
  Future<void> _clear() async {
    if (_clearing) return;
    final yes = await showAppDialog<bool>(
      context: context,
      builder: (dialog) => AppAlertDialog(
        title: Text(context.l10n.songAnalysisClearConfirmTitle),
        content: Text(context.l10n.songAnalysisClearConfirmMessage),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(dialog, false),
            child: Text(context.l10n.dialogCancel),
          ),
          AppDialogAction(
            isDestructive: true,
            onPressed: () => Navigator.pop(dialog, true),
            child: Text(context.l10n.songAnalysisClear),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => _clearing = true);
    try {
      await ref.read(songAnalysisProvider).clear();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.songAnalysisClearFailed)),
        );
      }
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final analysis = ref.watch(songAnalysisProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.songAnalysis),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsSwitchItem(
                  title: context.l10n.songAnalysis,
                  subtitle: context.l10n.songAnalysisDescription,
                  value: settings.autoplaySoundMatching,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setAutoplaySoundMatching(v),
                ),
                SettingsSwitchItem(
                  title: context.l10n.songAnalysisOnlyWhileCharging,
                  subtitle:
                      context.l10n.songAnalysisOnlyWhileChargingDescription,
                  enabled: settings.autoplaySoundMatching,
                  value: settings.songAnalysisOnlyWhileCharging,
                  onChanged: (v) => ref
                      .read(settingsProvider.notifier)
                      .setSongAnalysisOnlyWhileCharging(v),
                ),
                ValueListenableBuilder<SongAnalysisProgress?>(
                  valueListenable: analysis.progress,
                  builder: (context, progress, _) => Column(
                    children: [
                      SettingsSearchTarget(
                        label: context.l10n.songAnalysisClear,
                        child: SettingsItem(
                          title: context.l10n.songAnalysisClear,
                          subtitle: progress == null
                              ? null
                              : context.l10n.songAnalysisProgress(
                                  progress.analyzed,
                                  progress.total,
                                ),
                          onTap: _clearing ? null : _clear,
                          showDivider: false,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                        child: LinearProgressIndicator(
                          value: progress == null
                              ? null
                              : progress.total == 0
                              ? 0
                              : progress.analyzed / progress.total,
                          semanticsLabel: progress == null
                              ? context.l10n.songAnalysis
                              : context.l10n.songAnalysisProgress(
                                  progress.analyzed,
                                  progress.total,
                                ),
                        ),
                      ),
                    ],
                  ),
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
