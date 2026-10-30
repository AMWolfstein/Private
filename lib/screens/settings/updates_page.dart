import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/constants/app_info.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/platform/update_checker.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/sheets/update_dialog.dart';

class UpdatesPage extends ConsumerStatefulWidget {
  const UpdatesPage({super.key, this.checker});

  /// Test seam: production builds use the default [UpdateChecker].
  final UpdateChecker? checker;

  @override
  ConsumerState<UpdatesPage> createState() => _UpdatesPageState();
}

class _UpdatesPageState extends ConsumerState<UpdatesPage> {
  bool _checking = false;

  Future<void> _checkNow() async {
    if (_checking) return;
    setState(() => _checking = true);
    final channel = ref.read(settingsProvider).updateChannel;
    UpdateInfo? info;
    UpdateCheckException? failure;
    try {
      info = await (widget.checker ?? UpdateChecker()).checkForUpdate(
        channel: channel,
      );
    } on UpdateCheckException catch (error) {
      failure = error;
    } finally {
      if (mounted) setState(() => _checking = false);
    }
    if (!mounted) return;
    if (failure != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.updateCheckFailed),
          action: SnackBarAction(
            label: context.l10n.retry,
            onPressed: _checkNow,
          ),
        ),
      );
      return;
    }
    if (info == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.updateUpToDate)));
      return;
    }
    await showUpdateDialog(
      context,
      updateInfo: info,
      forced: info.releasesBehind >= UpdateChecker.forceUpdateThreshold,
      onDisableUpdates: () =>
          ref.read(settingsProvider.notifier).setCheckForUpdates(false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updates = ref.watch(
      settingsProvider.select(
        (s) => (check: s.checkForUpdates, channel: s.updateChannel),
      ),
    );
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.settingsUpdates),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(
              title: context.l10n.optionsCheckUpdates,
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsItem(
                  key: const ValueKey('check-update-now'),
                  icon: Icons.system_update,
                  title: context.l10n.updateCheckNow,
                  subtitle: _checking
                      ? context.l10n.updateChecking
                      : 'v${AppInfo.displayVersion}',
                  trailing: _checking
                      ? const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                  onTap: _checking ? null : _checkNow,
                ),
                SettingsSwitchItem(
                  key: const ValueKey('check-for-updates'),
                  icon: Icons.notifications_active_outlined,
                  title: context.l10n.optionsCheckUpdates,
                  subtitle: context.l10n.optionsCheckUpdatesSubtitle,
                  value: updates.check,
                  showDivider: updates.check,
                  onChanged: ref
                      .read(settingsProvider.notifier)
                      .setCheckForUpdates,
                ),
                if (updates.check)
                  SettingsSwitchItem(
                    key: const ValueKey('update-channel-preview'),
                    icon: Icons.new_releases_outlined,
                    title: context.l10n.optionsUpdateChannelPreview,
                    subtitle: context.l10n.optionsUpdateChannelWarning,
                    value: updates.channel == 'preview',
                    showDivider: false,
                    onChanged: (on) => ref
                        .read(settingsProvider.notifier)
                        .setUpdateChannel(on ? 'preview' : 'stable'),
                  ),
              ],
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}
