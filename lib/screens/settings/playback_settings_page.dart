import 'package:sistrum/screens/equalizer_screen.dart';
import 'package:sistrum/widgets/music_haptics_settings.dart';
import 'package:sistrum/widgets/playback_normalization_settings.dart';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/services/music_playback_deck.dart';
import 'package:sistrum/services/music_player_service.dart'
    show resetAutoplayLearning;
import 'package:sistrum/screens/listening_statistics_screen.dart';
import 'package:sistrum/utils/nav_bar_inset.dart';
import 'package:sistrum/widgets/animation_utils.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'package:sistrum/widgets/app_sliver_header.dart';
import 'package:sistrum/widgets/beta_badge.dart';
import 'package:sistrum/widgets/sistrum_volume_control.dart';
import 'package:sistrum/widgets/settings_group.dart';
import 'package:sistrum/widgets/automix_settings.dart';

class PlaybackSettingsPage extends ConsumerStatefulWidget {
  const PlaybackSettingsPage({super.key});

  @override
  ConsumerState<PlaybackSettingsPage> createState() =>
      _PlaybackSettingsPageState();
}

class _PlaybackSettingsPageState extends ConsumerState<PlaybackSettingsPage> {
  Future<bool> _confirmAudioVolume(String message) async {
    return await showAppDialog<bool>(
          context: context,
          builder: (context) => AppAlertDialog(
            title: Text(context.l10n.usbVolumeWarningTitle),
            content: Text(message),
            actions: [
              AppDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.dialogCancel),
              ),
              AppDialogAction(
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.usbVolumeAccept),
              ),
            ],
          ),
        ) ??
        false;
  }

  /// Learning cannot be restored once cleared, so a stray tap must not wipe it.
  Future<void> _confirmResetLearning() async {
    final confirmed =
        await showAppDialog<bool>(
          context: context,
          builder: (context) => AppAlertDialog(
            title: Text(context.l10n.autoplayResetLearningConfirmTitle),
            content: Text(context.l10n.autoplayResetLearningConfirmMessage),
            actions: [
              AppDialogAction(
                onPressed: () => Navigator.pop(context, false),
                child: Text(context.l10n.dialogCancel),
              ),
              AppDialogAction(
                isDestructive: true,
                onPressed: () => Navigator.pop(context, true),
                child: Text(context.l10n.autoplayResetLearningConfirm),
              ),
            ],
          ),
        ) ??
        false;
    if (confirmed) await resetAutoplayLearning();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: context.l10n.libraryPlayback),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsItem(
                  title: context.l10n.equalizerTitle,
                  titleTrailing: const BetaBadge(),
                  subtitle: context.l10n.equalizerDescription,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const EqualizerScreen(),
                    ),
                  ),
                ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(
              title: context.l10n.sectionVolumeAndTransitions,
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsSwitchItem(
                  icon: Icons.graphic_eq,
                  title: context.l10n.libraryPlaybackNormalization,
                  subtitle: context.l10n.libraryPlaybackNormalizationSubtitle,
                  value: settings.playbackNormalization,
                  enabled: !settings.usbBitPerfect,
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setPlaybackNormalization(value),
                ),
                if (settings.playbackNormalization)
                  PlaybackNormalizationSettings(
                    enabled: !settings.usbBitPerfect,
                  ),
                SettingsSwitchItem(
                  icon: Icons.vibration,
                  title: context.l10n.musicHaptics,
                  subtitle: context.l10n.musicHapticsDescription,
                  value: settings.musicHaptics,
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setMusicHaptics(value),
                ),
                if (settings.musicHaptics)
                  const MusicHapticsSettings(enabled: true),
                SettingsSwitchItem(
                  icon: Icons.compare_arrows,
                  title: 'AutoMix',
                  subtitle: context.l10n.autoMixDescription,
                  value: settings.autoMix,
                  enabled: !settings.usbBitPerfect,
                  onChanged: (value) =>
                      ref.read(settingsProvider.notifier).setAutoMix(value),
                  showDivider: false,
                ),
              ],
            ),
          ),
          if (settings.autoMix) ...[
            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.autoMixSettingsTitle,
              ),
            ),
            const SliverToBoxAdapter(child: AutoMixSettings()),
          ],
          SliverToBoxAdapter(
            child: SettingsSectionHeader(
              title: context.l10n.autoplayFromLibrary,
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsSwitchItem(
                  icon: Icons.playlist_play_rounded,
                  title: context.l10n.autoplayFromLibrary,
                  subtitle: context.l10n.autoplayDescription,
                  value: settings.autoplay,
                  onChanged: (value) =>
                      ref.read(settingsProvider.notifier).setAutoplay(value),
                ),
                SettingsSwitchItem(
                  icon: Icons.auto_awesome_outlined,
                  title: context.l10n.autoplayPersonalization,
                  subtitle: context.l10n.autoplayPersonalizationDescription,
                  value: settings.autoplayPersonalization,
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setAutoplayPersonalization(value),
                  showDivider: settings.autoplayPersonalization,
                ),
                if (settings.autoplayPersonalization)
                  SettingsItem(
                    icon: Icons.restart_alt,
                    title: context.l10n.autoplayResetLearning,
                    onTap: _confirmResetLearning,
                    showDivider: false,
                  ),
              ],
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(
              title: context.l10n.playbackAutomation,
            ),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsSwitchItem(
                  icon: Icons.volume_off_outlined,
                  title: context.l10n.playbackPauseOnMute,
                  subtitle: context.l10n.playbackPauseOnMuteDescription,
                  value: settings.pauseOnMute,
                  enabled: !settings.usbBitPerfect,
                  onChanged: (value) =>
                      ref.read(settingsProvider.notifier).setPauseOnMute(value),
                ),
                SettingsSwitchItem(
                  icon: Icons.headphones_outlined,
                  title: context.l10n.playbackOnHeadphonesConnected,
                  subtitle:
                      context.l10n.playbackOnHeadphonesConnectedDescription,
                  value: settings.playOnHeadphonesConnected,
                  onChanged: (value) => ref
                      .read(settingsProvider.notifier)
                      .setPlayOnHeadphonesConnected(value),
                  showDivider: false,
                ),
              ],
            ),
          ),
          if (Platform.isAndroid)
            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.sectionAudioOutput,
              ),
            ),
          if (Platform.isAndroid)
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  ValueListenableBuilder<UsbAudioStatus>(
                    valueListenable: usbAudioStatus,
                    builder: (context, status, _) => SettingsSwitchItem(
                      icon: Icons.usb,
                      title: context.l10n.usbBitPerfect,
                      titleTrailing: const BetaBadge(),
                      subtitle: [
                        context.l10n.usbBitPerfectDescription,
                        if (settings.usbBitPerfect)
                          switch (status.reason) {
                            'active' =>
                              '${status.device} · ${status.transport == 'pcm'
                                  ? '${status.bitDepth}-bit PCM'
                                  : status.transport == 'dop'
                                  ? 'DSD (DoP)'
                                  : 'DSD (Native)'} · ${(status.sampleRate! / 1000).toStringAsFixed(1)} kHz',
                            'dsd_unsupported' => context.l10n.usbDsdUnsupported,
                            'volume_unavailable' =>
                              context.l10n.usbVolumeUnavailable,
                            'exclusive_unavailable' =>
                              context.l10n.dapExclusiveUnavailable,
                            'permission_denied' =>
                              context.l10n.usbPermissionDenied,
                            'no_usb' => context.l10n.usbBitPerfectNoDevice,
                            'route_changed' =>
                              context.l10n.usbBitPerfectRouteChanged,
                            'android_version' ||
                            'unsupported' ||
                            'format' => context.l10n.usbBitPerfectFallback,
                            _ => context.l10n.usbBitPerfectPending,
                          },
                      ].join('\n\n'),
                      value: settings.usbBitPerfect,
                      onChanged: (value) async {
                        if (value &&
                            !await _confirmAudioVolume(
                              context.l10n.usbVolumeWarning,
                            )) {
                          return;
                        }
                        if (mounted) {
                          ref
                              .read(settingsProvider.notifier)
                              .setUsbBitPerfect(value);
                        }
                      },
                      showDivider: settings.usbBitPerfect,
                    ),
                  ),
                  if (settings.usbBitPerfect) ...[
                    SettingsSwitchItem(
                      icon: Icons.usb,
                      title: context.l10n.usbDirect,
                      subtitle: context.l10n.usbDirectDescription,
                      value: settings.usbDirect,
                      onChanged: (value) async {
                        if (value &&
                            !await _confirmAudioVolume(
                              context.l10n.usbVolumeWarning,
                            )) {
                          return;
                        }
                        if (mounted) {
                          ref
                              .read(settingsProvider.notifier)
                              .setUsbDirect(value);
                        }
                      },
                    ),
                    if (settings.usbDirect) ...[
                      SettingsSwitchItem(
                        icon: Icons.graphic_eq,
                        title: context.l10n.usbDsdOverPcm,
                        subtitle: context.l10n.usbDsdOverPcmDescription,
                        value: settings.usbDsdOverPcm,
                        onChanged: (value) => ref
                            .read(settingsProvider.notifier)
                            .setUsbDsdOverPcm(value),
                      ),
                      SettingsSwitchItem(
                        icon: Icons.volume_up_outlined,
                        title: context.l10n.usbFixedVolume,
                        subtitle: context.l10n.usbFixedVolumeDescription,
                        value: settings.usbAllowFixedVolume,
                        onChanged: (value) async {
                          if (value &&
                              !await _confirmAudioVolume(
                                context.l10n.usbFixedVolumeWarning,
                              )) {
                            return;
                          }
                          if (mounted) {
                            ref
                                .read(settingsProvider.notifier)
                                .setUsbAllowFixedVolume(value);
                          }
                        },
                      ),
                      ValueListenableBuilder<UsbVolumeState?>(
                        valueListenable: usbHardwareVolume,
                        builder: (context, volume, _) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 12,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.usbHardwareVolume,
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                              Text(
                                volume == null
                                    ? context.l10n.usbBitPerfectPending
                                    : volume.available
                                    ? '${volume.currentDb.toStringAsFixed(1)} dB'
                                    : context.l10n.usbVolumeUnavailable,
                              ),
                              if (volume?.available == true)
                                SistrumVolumeControl(
                                  foreground: colorScheme.onSurface,
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                    SettingsSwitchItem(
                      icon: Icons.headphones,
                      title: context.l10n.dapExclusive,
                      titleTrailing: const BetaBadge(),
                      subtitle: context.l10n.dapExclusiveDescription,
                      value: settings.dapExclusive,
                      onChanged: (value) => ref
                          .read(settingsProvider.notifier)
                          .setDapExclusive(value),
                      showDivider: false,
                    ),
                  ],
                ],
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
          SliverToBoxAdapter(
            child: SettingsSectionHeader(title: context.l10n.listeningStats),
          ),
          SliverToBoxAdapter(
            child: SettingsGroup(
              children: [
                SettingsItem(
                  icon: Icons.insights_outlined,
                  title: context.l10n.listeningStats,
                  subtitle: context.l10n.listeningStatsDescription,
                  onTap: () => Navigator.of(context).push(
                    slidePageRoute<void>(
                      page: const ListeningStatisticsScreen(),
                    ),
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
    );
  }
}
