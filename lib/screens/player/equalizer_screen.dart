// SPDX-License-Identifier: LGPL-3.0-only
// Copyright 2026 zarzet and contributors; adapted from Mornye v5.3.0.
import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/equalizer_settings.dart';
import 'package:sistrum/providers/settings/equalizer_provider.dart';
import 'package:sistrum/services/playback/audio/playback_equalizer.dart';
import 'package:sistrum/core/theme/app_tokens.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_level_slider.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_controls.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/settings/settings_chips_and_cards.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/widgets/status/beta_badge.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';

part 'equalizer_widgets.dart';
part 'equalizer_curve.dart';

class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  bool _busy = false;

  void _message(String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(message)));

  Future<void> _savePreset() async {
    final name = await showAppDialog<String>(
      context: context,
      builder: (context) => const _PresetNameDialog(),
    );
    if (!mounted || name == null) return;
    try {
      ref.read(equalizerProvider.notifier).savePreset(name);
      _message(context.l10n.equalizerSaved);
    } on FormatException catch (error) {
      _message(error.message);
    }
  }

  Future<void> _import() async {
    setState(() => _busy = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null) return;
      final source = await readEqualizerPreset(
        file.readAsByteStream(),
        declaredSize: file.lengthSync(),
      );
      if (!mounted) return;
      ref.read(equalizerProvider.notifier).importPreset(source);
      _message(context.l10n.equalizerSaved);
    } catch (_) {
      if (mounted) _message(context.l10n.equalizerImportInvalid);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    final source = ref
        .read(equalizerProvider.notifier)
        .exportPreset('Custom EQ');
    final box = context.findRenderObject() as RenderBox?;
    try {
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(source)),
              mimeType: 'application/json',
            ),
          ],
          fileNameOverrides: ['sistrum-equalizer.json'],
          sharePositionOrigin: box == null
              ? null
              : box.localToGlobal(Offset.zero) & box.size,
        ),
      );
    } catch (error) {
      if (mounted) _message(context.l10n.snackbarError(error.toString()));
    }
  }

  Future<void> _presets() => showAppBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    title: context.l10n.equalizerPresets,
    maxHeightFactor: 0.85,
    builder: (sheetContext) => Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(equalizerProvider);
        final selected = _matchingPreset(state);
        final mornye = context.isAppTheme;
        return SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final preset in [
                ...EqualizerPreset.builtIn,
                ...state.presets,
              ])
                AppSheetOption(
                  title: Text(preset.name),
                  selected: preset == selected,
                  // iOS lists mark the choice with a trailing checkmark.
                  leading: mornye
                      ? null
                      : preset == selected
                      ? const _AppEqualizerIcon(Icons.check)
                      : const _AppEqualizerIcon(Icons.graphic_eq),
                  trailing:
                      (mornye && preset == selected) ||
                          state.presets.contains(preset)
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (mornye && preset == selected)
                              _AppEqualizerIcon(
                                Icons.check,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                            if (state.presets.contains(preset))
                              IconButton(
                                tooltip: context.l10n.equalizerDeletePreset,
                                icon: const _AppEqualizerIcon(
                                  Icons.delete_outline,
                                ),
                                onPressed: () => ref
                                    .read(equalizerProvider.notifier)
                                    .deletePreset(preset.name),
                              ),
                          ],
                        )
                      : null,
                  onTap: () {
                    ref.read(equalizerProvider.notifier).applyPreset(preset);
                    Navigator.pop(sheetContext);
                  },
                ),
            ],
          ),
        );
      },
    ),
  );

  Future<void> _reset() async {
    final accepted = await showAppDialog<bool>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.equalizerResetTitle),
        content: Text(context.l10n.equalizerResetDescription),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.dialogCancel),
          ),
          AppDialogAction(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.l10n.libraryFilterReset),
          ),
        ],
      ),
    );
    if (mounted && accepted == true) {
      final enabled = ref.read(equalizerProvider).settings.enabled;
      ref
          .read(equalizerProvider.notifier)
          .update(EqualizerSettings(enabled: enabled));
    }
  }

  @override
  Widget build(BuildContext context) => AppSettingsTheme(
    // Reached from Playback and Now Playing alike, so the page brings its own
    // inset grouped surfaces in Mornye.
    child: Builder(builder: _buildPage),
  );

  Widget _buildPage(BuildContext context) {
    final state = ref.watch(equalizerProvider);
    final settings = state.settings;
    final notifier = ref.read(equalizerProvider.notifier);
    final l10n = context.l10n;
    final selectedPreset = _matchingPreset(state);
    final presetName = selectedPreset?.name ?? l10n.equalizerCustom;
    void update(EqualizerSettings next) => notifier.update(next);
    void setEnabled(bool v) => update(settings.copyWith(enabled: v));
    Widget section(Widget child) => SliverToBoxAdapter(child: child);
    final error = section(
      ValueListenableBuilder<String?>(
        valueListenable: playbackEqualizerError,
        builder: (context, error, _) {
          final message = error ?? state.error;
          return message == null
              ? const SizedBox.shrink()
              : SettingsInfoCard(
                  message: message,
                  icon: Icons.error_outline,
                  glass: true,
                );
        },
      ),
    );
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          AppSliverHeader.page(title: l10n.equalizerTitle),
          // iOS order: the master switch, its footnote, then the response.
          section(
            SettingsGroup(
              children: [
                SettingsSwitchItem(
                  icon: Icons.graphic_eq,
                  title: l10n.equalizerEnable,
                  titleTrailing: const BetaBadge(),
                  value: settings.enabled,
                  onChanged: setEnabled,
                  showDivider: false,
                ),
              ],
            ),
          ),
          section(_Footnote(l10n.equalizerBypass)),
          error,
          section(
            SettingsGroup(
              children: [
                _EqualizerOverview(settings: settings, presetName: presetName),
              ],
            ),
          ),
          // The value cell names the group, so it needs no header.
          const SliverToBoxAdapter(child: SizedBox(height: 28)),
          section(
            SettingsGroup(
              children: [
                SettingsItem(
                  title: l10n.equalizerPresets,
                  trailing: _DetailValue(presetName),
                  onTap: _presets,
                ),
                _ActionRow(label: l10n.equalizerSavePreset, onTap: _savePreset),
                _ActionRow(
                  label: l10n.equalizerImport,
                  onTap: _busy ? null : _import,
                ),
                _ActionRow(
                  label: l10n.equalizerExport,
                  onTap: _export,
                  last: true,
                ),
              ],
            ),
          ),
          section(SettingsSectionHeader(title: l10n.equalizerBands)),
          section(
            SettingsGroup(
              children: [_BandEditor(settings: settings, onChanged: update)],
            ),
          ),
          section(SettingsSectionHeader(title: l10n.equalizerTone)),
          section(
            SettingsGroup(
              children: [
                _SliderTile(
                  title: l10n.equalizerPreamp,
                  subtitle:
                      '${l10n.equalizerEffectivePreamp}: ${_signed(settings.inputGain)} dB',
                  value: settings.preamp,
                  min: -24,
                  max: 12,
                  step: 0.5,
                  unit: 'dB',
                  onChanged: (v) => update(settings.copyWith(preamp: v)),
                ),
                _SliderTile(
                  title: l10n.equalizerBass,
                  value: settings.bass,
                  min: -12,
                  max: 12,
                  step: 0.5,
                  unit: 'dB',
                  centered: true,
                  onChanged: (v) => update(settings.copyWith(bass: v)),
                ),
                _SliderTile(
                  title: l10n.equalizerTreble,
                  value: settings.treble,
                  min: -12,
                  max: 12,
                  step: 0.5,
                  unit: 'dB',
                  centered: true,
                  onChanged: (v) => update(settings.copyWith(treble: v)),
                ),
                _SliderTile(
                  title: l10n.equalizerBalance,
                  value: settings.balance * 100,
                  min: -100,
                  max: 100,
                  step: 1,
                  unit: '%',
                  centered: true,
                  last: true,
                  onChanged: (v) => update(settings.copyWith(balance: v / 100)),
                ),
              ],
            ),
          ),
          section(SettingsSectionHeader(title: l10n.equalizerDynamics)),
          section(
            SettingsGroup(
              children: [
                SettingsSwitchItem(
                  icon: Icons.vertical_align_bottom,
                  title: l10n.equalizerHeadroom,
                  subtitle: l10n.equalizerHeadroomDescription,
                  value: settings.autoHeadroom,
                  onChanged: (v) => update(settings.copyWith(autoHeadroom: v)),
                ),
                SettingsSwitchItem(
                  icon: Icons.health_and_safety_outlined,
                  title: l10n.equalizerLimiter,
                  subtitle: l10n.equalizerLimiterDescription,
                  value: settings.limiter,
                  onChanged: (v) => update(settings.copyWith(limiter: v)),
                ),
                SettingsSwitchItem(
                  icon: Icons.compress,
                  title: l10n.equalizerCompressor,
                  subtitle: l10n.equalizerCompressorDescription,
                  value: settings.compressor,
                  onChanged: (v) => update(settings.copyWith(compressor: v)),
                  showDivider: settings.compressor,
                ),
                if (settings.compressor) ...[
                  _SliderTile(
                    title: l10n.equalizerThreshold,
                    value: settings.threshold,
                    min: -60,
                    max: 0,
                    step: 0.5,
                    unit: 'dB',
                    onChanged: (v) => update(settings.copyWith(threshold: v)),
                  ),
                  _SliderTile(
                    title: l10n.equalizerRatio,
                    value: settings.ratio,
                    min: 1,
                    max: 20,
                    step: 0.5,
                    unit: ':1',
                    signed: false,
                    onChanged: (v) => update(settings.copyWith(ratio: v)),
                  ),
                  _SliderTile(
                    title: l10n.equalizerAttack,
                    value: settings.attack,
                    min: 1,
                    max: 100,
                    step: 1,
                    unit: 'ms',
                    signed: false,
                    onChanged: (v) => update(settings.copyWith(attack: v)),
                  ),
                  _SliderTile(
                    title: l10n.equalizerRelease,
                    value: settings.release,
                    min: 20,
                    max: 1000,
                    step: 10,
                    unit: 'ms',
                    signed: false,
                    last: true,
                    onChanged: (v) => update(settings.copyWith(release: v)),
                  ),
                ],
              ],
            ),
          ),
          ...[
            // iOS keeps a destructive command in its own group at the end.
            const SliverToBoxAdapter(child: SizedBox(height: 28)),
            section(
              SettingsGroup(
                children: [
                  _ActionRow(
                    label: l10n.libraryFilterReset,
                    onTap: _reset,
                    destructive: true,
                    last: true,
                  ),
                ],
              ),
            ),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 40)),
          const NavBarSliverSpacer(),
        ],
      ),
    );
  }
}

/// The preset whose curve, tone and dynamics match the current settings.
EqualizerPreset? _matchingPreset(EqualizerState state) {
  // Matches when applying the preset would change nothing.
  String key(EqualizerSettings settings) => jsonEncode(settings.toJson());
  final current = key(state.settings);
  for (final preset in [...EqualizerPreset.builtIn, ...state.presets]) {
    if (key(state.settings.withToneOf(preset.settings)) == current) {
      return preset;
    }
  }
  return null;
}

/// Bound preset input before accumulation, including providers with no size.
Future<String> readEqualizerPreset(
  Stream<List<int>> chunks, {
  int? declaredSize,
}) async {
  const limit = 65536;
  if (declaredSize != null && declaredSize > limit) {
    throw const FormatException('Equalizer preset exceeds 64 KB');
  }
  final bytes = BytesBuilder(copy: false);
  await for (final chunk in chunks) {
    if (bytes.length + chunk.length > limit) {
      throw const FormatException('Equalizer preset exceeds 64 KB');
    }
    bytes.add(chunk);
  }
  return utf8.decode(bytes.takeBytes());
}
