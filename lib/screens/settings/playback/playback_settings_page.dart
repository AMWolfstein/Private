import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/automix_options.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/screens/equalizer_screen.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart'
    show resetAutoplayLearning;
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/player/app_volume_control.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_slider.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/music_haptics_settings.dart';
import 'package:sistrum/widgets/settings/playback_normalization_settings.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/status/beta_badge.dart';

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
                                AppVolumeControl(
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
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}

class AutoMixSettings extends ConsumerStatefulWidget {
  const AutoMixSettings({super.key});

  @override
  ConsumerState<AutoMixSettings> createState() => _AutoMixSettingsState();
}

class _AutoMixSettingsState extends ConsumerState<AutoMixSettings> {
  double? _duration;
  double? _pitch;
  double? _speed;

  void _showEffectPicker(
    BuildContext context,
    AutoMixEffect current,
    Map<AutoMixEffect, String> names,
  ) {
    final notifier = ref.read(settingsProvider.notifier);
    showAppBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      title: context.l10n.autoMixEffect,
      maxHeightFactor: 0.85,
      builder: (sheetContext) => SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final effect in AutoMixEffect.values)
              Semantics(
                selected: effect == current,
                child: AppSheetOption(
                  leading: Icon(switch (effect) {
                    AutoMixEffect.auto => Icons.auto_awesome,
                    AutoMixEffect.crossfade => Icons.compare_arrows,
                    AutoMixEffect.muffled => Icons.graphic_eq,
                    AutoMixEffect.echo => Icons.surround_sound,
                    AutoMixEffect.pitch => Icons.music_note,
                    AutoMixEffect.custom => Icons.tune,
                  }),
                  title: Text(names[effect]!),
                  trailing: effect == current
                      ? Icon(
                          Icons.check,
                          color: Theme.of(sheetContext).colorScheme.primary,
                        )
                      : null,
                  onTap: () {
                    notifier.setAutoMixEffect(effect);
                    Navigator.pop(sheetContext);
                  },
                ),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final enabled = settings.autoMix && !settings.usbBitPerfect;
    final l10n = context.l10n;
    final names = {
      AutoMixEffect.auto: l10n.autoMixEffectAuto,
      AutoMixEffect.crossfade: l10n.autoMixEffectCrossfade,
      AutoMixEffect.muffled: l10n.autoMixEffectMuffled,
      AutoMixEffect.echo: l10n.autoMixEffectEcho,
      AutoMixEffect.pitch: l10n.autoMixEffectPitch,
      AutoMixEffect.custom: l10n.autoMixEffectCustom,
    };
    Widget slider(
      String label,
      String semanticLabel,
      String Function(double) spokenValue,
      double value,
      double min,
      double max,
      int divisions,
      ValueChanged<double> draft,
      ValueChanged<double> save,
    ) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label),
            Semantics(
              label: semanticLabel,
              child: AppSlider(
                value: value.clamp(min, max),
                min: min,
                max: max,
                divisions: divisions,
                label: value.toStringAsFixed(2),
                semanticFormatterCallback: spokenValue,
                onChanged: enabled ? draft : null,
                onChangeEnd: enabled ? save : null,
              ),
            ),
          ],
        ),
      );
    }

    return SettingsGroup(
      children: [
        SettingsSwitchItem(
          icon: Icons.timer_outlined,
          title: l10n.autoMixAutomaticDuration,
          value: settings.autoMixDuration == 0,
          enabled: enabled,
          onChanged: (automatic) =>
              notifier.setAutoMixDuration(automatic ? 0 : 5),
        ),
        if (settings.autoMixDuration != 0)
          slider(
            '${l10n.autoMixDuration}: ${(_duration ?? settings.autoMixDuration.toDouble()).round()} s',
            l10n.autoMixDuration,
            (value) => '${value.round()} s',
            _duration ?? settings.autoMixDuration.toDouble(),
            3,
            60,
            57,
            (value) => setState(() => _duration = value),
            (value) {
              notifier.setAutoMixDuration(value.round());
              setState(() => _duration = null);
            },
          ),
        SettingsItem(
          icon: Icons.tune,
          title: l10n.autoMixEffect,
          subtitle: names[settings.autoMixEffect],
          onTap: enabled
              ? () => _showEffectPicker(context, settings.autoMixEffect, names)
              : null,
        ),
        if (settings.autoMixEffect == AutoMixEffect.pitch ||
            settings.autoMixEffect == AutoMixEffect.custom)
          slider(
            '${l10n.autoMixPitch}: ${(_pitch ?? settings.autoMixPitch).toStringAsFixed(1)}',
            l10n.autoMixPitch,
            (value) => value.toStringAsFixed(1),
            _pitch ?? settings.autoMixPitch,
            -6,
            6,
            24,
            (value) => setState(() => _pitch = value),
            (value) {
              notifier.setAutoMixPitch(value);
              setState(() => _pitch = null);
            },
          ),
        if (settings.autoMixEffect == AutoMixEffect.custom) ...[
          slider(
            '${l10n.autoMixSpeed}: ${(_speed ?? settings.autoMixSpeed).toStringAsFixed(2)}×',
            l10n.autoMixSpeed,
            (value) => '${value.toStringAsFixed(2)}×',
            _speed ?? settings.autoMixSpeed,
            0.8,
            1.2,
            40,
            (value) => setState(() => _speed = value),
            (value) {
              notifier.setAutoMixSpeed(value);
              setState(() => _speed = null);
            },
          ),
          SettingsSwitchItem(
            icon: Icons.surround_sound,
            title: l10n.autoMixEcho,
            value: settings.autoMixEcho,
            enabled: enabled,
            onChanged: notifier.setAutoMixEcho,
          ),
          SettingsSwitchItem(
            icon: Icons.graphic_eq,
            title: l10n.autoMixLowPass,
            value: settings.autoMixLowPass,
            enabled: enabled,
            onChanged: notifier.setAutoMixLowPass,
          ),
        ],
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text(
            l10n.autoMixEffectsHelp,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}
