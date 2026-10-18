import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/widgets/settings_group.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';

class AppSettingsPage extends ConsumerWidget {
  const AppSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: context.l10n.settingsApp),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.sectionDebug),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsSwitchItem(
                    icon: Icons.bug_report,
                    title: context.l10n.optionsDetailedLogging,
                    subtitle: settings.enableLogging
                        ? context.l10n.optionsDetailedLoggingOn
                        : context.l10n.optionsDetailedLoggingOff,
                    value: settings.enableLogging,
                    onChanged: (v) =>
                        ref.read(settingsProvider.notifier).setEnableLogging(v),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}
