import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/animated_artwork/animated_artwork_providers.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/artist_images/artist_image_network.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';

/// Settings for background video artwork downloads: on or off, and which
/// networks they may use. Manual searches are never limited by these, and
/// turning this off never deletes a saved video.
class VideoArtworkSettingsPage extends ConsumerWidget {
  const VideoArtworkSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final progress = ref.watch(animatedArtworkProgressProvider);
    final selected = ArtistImageNetwork.fromStored(
      settings.videoArtworkNetwork,
    );

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: l10n.videoArtworkSettingsTitle),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsSwitchItem(
                  icon: Icons.movie_outlined,
                  title: l10n.videoArtworkAutoTitle,
                  subtitle: l10n.videoArtworkAutoSubtitle,
                  value: settings.videoArtworkAutoDownload,
                  onChanged: notifier.setVideoArtworkAutoDownload,
                  showDivider: false,
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsItem(
                  icon: Icons.sync,
                  title: progress == null
                      ? l10n.videoArtworkIdle
                      : l10n.videoArtworkProgress(
                          progress.completed,
                          progress.total,
                        ),
                  subtitle: progress == null
                      ? null
                      : l10n.videoArtworkCounts(
                          progress.saved,
                          progress.notFound,
                          progress.failed,
                        ),
                  showDivider: true,
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
                      ArtistImageNetwork.wifi => l10n.videoArtworkNetworkWifi,
                      ArtistImageNetwork.mobile =>
                        l10n.videoArtworkNetworkMobile,
                      ArtistImageNetwork.both => l10n.videoArtworkNetworkBoth,
                    },
                    trailing: option == selected
                        ? Icon(
                            Icons.check,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : null,
                    onTap: () => notifier.setVideoArtworkNetwork(option.name),
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
