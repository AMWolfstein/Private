import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/performance/perf_hud_settings_provider.dart';
import 'package:sistrum/services/performance/perf_frame_monitor.dart';
import 'package:sistrum/services/performance/perf_frame_window.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/widgets/primitives/app_slider.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

/// Developer tools, reachable from About after the hidden unlock. Only the
/// performance HUD lives here; the HUD itself is gated by the build flag.
class DeveloperOptionsPage extends ConsumerWidget {
  const DeveloperOptionsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(perfHudSettingsProvider);
    final notifier = ref.read(perfHudSettingsProvider.notifier);
    final monitor = ref.read(perfFrameMonitorProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: l10n.devOptionsTitle),
          SliverToBoxAdapter(
            child: SettingsGroup(
              margin: EdgeInsets.fromLTRB(
                16 + wideListInset(context),
                8,
                16 + wideListInset(context),
                8,
              ),
              children: [
                SettingsSwitchItem(
                  icon: Icons.speed,
                  title: l10n.devOptionsPerfHud,
                  subtitle: l10n.devOptionsPerfHudSubtitle,
                  value: settings.enabled,
                  onChanged: notifier.setEnabled,
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Row(
                    children: [
                      Expanded(child: Text(l10n.devOptionsHudOpacity)),
                      SizedBox(
                        width: 180,
                        child: AppSlider(
                          value: settings.opacity,
                          min: 0.4,
                          max: 1,
                          onChanged: notifier.setOpacity,
                        ),
                      ),
                    ],
                  ),
                ),
                SettingsItem(
                  icon: Icons.restart_alt,
                  title: l10n.devOptionsResetMetrics,
                  onTap: monitor.reset,
                ),
                SettingsItem(
                  icon: Icons.copy_outlined,
                  title: l10n.devOptionsCopyReport,
                  showDivider: false,
                  onTap: () async {
                    final report = formatPerfReport(
                      screen: 'developer-options',
                      snapshot: monitor.currentSnapshot(),
                    );
                    await Clipboard.setData(ClipboardData(text: report));
                    if (!context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(l10n.devOptionsCopied)),
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
