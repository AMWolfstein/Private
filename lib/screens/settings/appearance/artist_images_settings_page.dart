import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

/// Settings for background artist photo downloads: on or off, and which
/// networks they may use. Manual searches are never limited by these.
class ArtistImagesSettingsPage extends ConsumerWidget {
  const ArtistImagesSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final selected = ArtistImageNetwork.fromStored(
      settings.artistImagesNetwork,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: l10n.artistImagesSettingsTitle),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsSwitchItem(
                  icon: Icons.person_search_outlined,
                  title: l10n.artistImagesAutoTitle,
                  subtitle: l10n.artistImagesAutoSubtitle,
                  value: settings.artistImagesAutoDownload,
                  onChanged: notifier.setArtistImagesAutoDownload,
                  showDivider: false,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                for (final option in ArtistImageNetwork.values)
                  SettingsItem(
                    title: switch (option) {
                      ArtistImageNetwork.wifi => l10n.artistImagesNetworkWifi,
                      ArtistImageNetwork.mobile =>
                        l10n.artistImagesNetworkMobile,
                      ArtistImageNetwork.both => l10n.artistImagesNetworkBoth,
                    },
                    trailing: option == selected
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () => notifier.setArtistImagesNetwork(option.name),
                    showDivider: option != ArtistImageNetwork.both,
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
