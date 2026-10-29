import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/equalizer_settings.dart';
import 'package:sistrum/providers/equalizer_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/playback/playback_equalizer.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/app_glass_thumb.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_choice_chip.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/status/beta_badge.dart';

/// The retained Sistrum Settings surfaces around the upstream per-player DSP.
class EqualizerScreen extends ConsumerWidget {
  const EqualizerScreen({super.key});

  Future<void> _presetName(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    try {
      final name = await showAppDialog<String>(
        context: context,
        builder: (context) => AppAlertDialog(
          title: Text(context.l10n.equalizerSavePreset),
          content: TextField(
            controller: controller,
            maxLength: 80,
            autofocus: true,
            decoration: InputDecoration(
              labelText: context.l10n.equalizerPresetName,
            ),
          ),
          actions: [
            AppDialogAction(
              onPressed: () => Navigator.pop(context),
              child: Text(context.l10n.dialogCancel),
            ),
            AppDialogAction(
              onPressed: () => Navigator.pop(context, controller.text),
              child: Text(context.l10n.dialogSave),
            ),
          ],
        ),
      );
      if (name != null && name.trim().isNotEmpty) {
        ref.read(equalizerProvider.notifier).savePreset(name);
      }
    } catch (error) {
      if (context.mounted) _error(context, error);
    } finally {
      controller.dispose();
    }
  }

  Future<void> _import(BuildContext context, WidgetRef ref) async {
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (file == null || !context.mounted) return;
      final source = await readEqualizerPreset(
        file.readAsByteStream(),
        declaredSize: file.lengthSync(),
      );
      if (!context.mounted) return;
      ref.read(equalizerProvider.notifier).importPreset(source);
    } catch (error) {
      if (context.mounted) _error(context, error);
    }
  }

  Future<void> _export(BuildContext context, WidgetRef ref) async {
    try {
      final data = ref
          .read(equalizerProvider.notifier)
          .exportPreset(context.l10n.equalizerCustom);
      final box = context.findRenderObject() as RenderBox?;
      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              Uint8List.fromList(utf8.encode(data)),
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
      if (context.mounted) _error(context, error);
    }
  }

  void _error(BuildContext context, Object error) {
    showAppDialog<void>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.equalizerTitle),
        content: Text(error.toString()),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.dialogCancel),
          ),
        ],
      ),
    );
  }

  Future<void> _presets(BuildContext context) => showAppBottomSheet<void>(
    context: context,
    title: context.l10n.equalizerPresets,
    maxHeightFactor: 0.85,
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final state = ref.watch(equalizerProvider);
        final presets = [...EqualizerPreset.builtIn, ...state.presets];
        return ListView.builder(
          shrinkWrap: true,
          itemCount: presets.length,
          itemBuilder: (context, index) {
            final preset = presets[index];
            return ListTile(
              title: Text(preset.name),
              trailing: state.presets.contains(preset)
                  ? IconButton(
                      tooltip: context.l10n.equalizerDeletePreset,
                      icon: const Icon(CupertinoIcons.delete),
                      onPressed: () => ref
                          .read(equalizerProvider.notifier)
                          .deletePreset(preset.name),
                    )
                  : null,
              onTap: () {
                ref.read(equalizerProvider.notifier).applyPreset(preset);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(equalizerProvider);
    final settings = state.settings;
    final control = ref.read(equalizerProvider.notifier);
    final l10n = context.l10n;
    Widget slider(
      String label,
      double value,
      double min,
      double max,
      ValueChanged<double> changed, {
      String unit = 'dB',
    }) => Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$label · ${value.toStringAsFixed(1)} $unit'),
          SizedBox(
            height: 48,
            child: AppLevelSlider(
              value: value,
              min: min,
              max: max,
              origin: min <= 0 && max >= 0 ? 0 : min,
              semanticLabel: label,
              onChanged: settings.enabled ? changed : null,
            ),
          ),
        ],
      ),
    );
    return AppSettingsTheme(
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: l10n.equalizerTitle),
            SliverToBoxAdapter(
              child: Column(
                children: [
                  SettingsGroup(
                    children: [
                      SettingsSwitchItem(
                        title: l10n.equalizerEnable,
                        titleTrailing: const BetaBadge(),
                        value: settings.enabled,
                        onChanged: (value) =>
                            control.update(settings.copyWith(enabled: value)),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(l10n.equalizerBypass),
                      ),
                      ValueListenableBuilder<String?>(
                        valueListenable: playbackEqualizerError,
                        builder: (context, error, _) =>
                            error == null && state.error == null
                            ? const SizedBox.shrink()
                            : Padding(
                                padding: const EdgeInsets.all(20),
                                child: Text(
                                  error ?? state.error!,
                                  style: TextStyle(
                                    color: Theme.of(context).colorScheme.error,
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                  SettingsGroup(
                    children: [
                      SettingsItem(
                        title: l10n.equalizerPresets,
                        onTap: () => _presets(context),
                        trailing: const Icon(CupertinoIcons.forward),
                      ),
                      SettingsItem(
                        title: l10n.equalizerSavePreset,
                        onTap: () => _presetName(context, ref),
                      ),
                      SettingsItem(
                        title: l10n.equalizerImport,
                        onTap: () => _import(context, ref),
                      ),
                      SettingsItem(
                        title: l10n.equalizerExport,
                        onTap: () => _export(context, ref),
                      ),
                      SettingsItem(
                        title: l10n.equalizerResetTitle,
                        onTap: () async {
                          final reset = await showAppDialog<bool>(
                            context: context,
                            builder: (context) => AppAlertDialog(
                              title: Text(l10n.equalizerResetTitle),
                              content: Text(l10n.equalizerResetDescription),
                              actions: [
                                AppDialogAction(
                                  onPressed: () =>
                                      Navigator.pop(context, false),
                                  child: Text(l10n.dialogCancel),
                                ),
                                AppDialogAction(
                                  onPressed: () => Navigator.pop(context, true),
                                  child: Text(l10n.dialogDone),
                                ),
                              ],
                            ),
                          );
                          if (reset == true) {
                            control.update(
                              EqualizerSettings(enabled: settings.enabled),
                            );
                          }
                        },
                      ),
                    ],
                  ),
                  SettingsSectionHeader(title: l10n.equalizerBands),
                  SettingsGroup(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: Wrap(
                          spacing: 8,
                          children: [
                            for (final count in EqualizerSettings.bandCounts)
                              AppChoiceChip(
                                label: Text('$count'),
                                selected: settings.gains.length == count,
                                onSelected: (_) => control.update(
                                  settings.withBandCount(count),
                                ),
                              ),
                          ],
                        ),
                      ),
                      SizedBox(
                        height: 250,
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: settings.gains.length,
                          itemBuilder: (context, index) {
                            final hz = settings.frequencies[index];
                            final label = hz < 1000
                                ? '${hz.round()} Hz'
                                : '${(hz / 1000).toStringAsFixed(1)} kHz';
                            return SizedBox(
                              width: 66,
                              child: Padding(
                                padding: const EdgeInsets.all(8),
                                child: Column(
                                  children: [
                                    Text(
                                      settings.gains[index].toStringAsFixed(1),
                                    ),
                                    const SizedBox(height: 8),
                                    Expanded(
                                      child: AppLevelSlider(
                                        vertical: true,
                                        knobRadius: 10,
                                        value: settings.gains[index],
                                        min: -15,
                                        max: 15,
                                        origin: 0,
                                        semanticLabel: label,
                                        onChanged: settings.enabled
                                            ? (value) {
                                                final gains = [
                                                  ...settings.gains,
                                                ];
                                                gains[index] = value;
                                                control.update(
                                                  settings.copyWith(
                                                    gains: gains,
                                                  ),
                                                );
                                              }
                                            : null,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    SizedBox(
                                      width: double.infinity,
                                      child: Text(label),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  SettingsSectionHeader(title: l10n.equalizerTone),
                  SettingsGroup(
                    children: [
                      slider(
                        l10n.equalizerPreamp,
                        settings.preamp,
                        -24,
                        12,
                        (value) =>
                            control.update(settings.copyWith(preamp: value)),
                      ),
                      slider(
                        l10n.equalizerBass,
                        settings.bass,
                        -12,
                        12,
                        (value) =>
                            control.update(settings.copyWith(bass: value)),
                      ),
                      slider(
                        l10n.equalizerTreble,
                        settings.treble,
                        -12,
                        12,
                        (value) =>
                            control.update(settings.copyWith(treble: value)),
                      ),
                      slider(
                        l10n.equalizerBalance,
                        settings.balance,
                        -1,
                        1,
                        (value) =>
                            control.update(settings.copyWith(balance: value)),
                        unit: '',
                      ),
                      Padding(
                        padding: const EdgeInsets.all(20),
                        child: Text(
                          '${l10n.equalizerEffectivePreamp}: ${settings.inputGain.toStringAsFixed(1)} dB',
                        ),
                      ),
                    ],
                  ),
                  SettingsSectionHeader(title: l10n.equalizerDynamics),
                  SettingsGroup(
                    children: [
                      SettingsSwitchItem(
                        title: l10n.equalizerHeadroom,
                        subtitle: l10n.equalizerHeadroomDescription,
                        value: settings.autoHeadroom,
                        onChanged: (value) => control.update(
                          settings.copyWith(autoHeadroom: value),
                        ),
                      ),
                      SettingsSwitchItem(
                        title: l10n.equalizerLimiter,
                        subtitle: l10n.equalizerLimiterDescription,
                        value: settings.limiter,
                        onChanged: (value) =>
                            control.update(settings.copyWith(limiter: value)),
                      ),
                      SettingsSwitchItem(
                        title: l10n.equalizerCompressor,
                        subtitle: l10n.equalizerCompressorDescription,
                        value: settings.compressor,
                        onChanged: (value) => control.update(
                          settings.copyWith(compressor: value),
                        ),
                      ),
                      if (settings.compressor) ...[
                        slider(
                          l10n.equalizerThreshold,
                          settings.threshold,
                          -60,
                          0,
                          (value) => control.update(
                            settings.copyWith(threshold: value),
                          ),
                        ),
                        slider(
                          l10n.equalizerRatio,
                          settings.ratio,
                          1,
                          20,
                          (value) =>
                              control.update(settings.copyWith(ratio: value)),
                          unit: ':1',
                        ),
                        slider(
                          l10n.equalizerAttack,
                          settings.attack,
                          1,
                          100,
                          (value) =>
                              control.update(settings.copyWith(attack: value)),
                          unit: 'ms',
                        ),
                        slider(
                          l10n.equalizerRelease,
                          settings.release,
                          20,
                          1000,
                          (value) =>
                              control.update(settings.copyWith(release: value)),
                          unit: 'ms',
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
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

/// An iOS-style slider: a thin rounded track and a white shadowed knob.
///
/// Unlike [CupertinoSlider], the active track can grow from an [origin]
/// inside the range (gain, balance) and the slider can stand [vertical], with
/// [min] at the bottom. A vertical slider only claims vertical drags, so a
/// row of them still scrolls sideways.
///
/// A horizontal slider's knob turns into liquid glass while touched when the
/// glass gate allows it; dense vertical faders keep the painted knob.
class AppLevelSlider extends ConsumerStatefulWidget {
  const AppLevelSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.origin,
    this.vertical = false,
    this.step,
    this.semanticLabel,
    this.semanticFormatterCallback,
    this.knobRadius = CupertinoThumbPainter.radius,
  });

  final double value, min, max;

  /// Smaller knobs keep a dense row of vertical faders from touching.
  final double knobRadius;
  final ValueChanged<double>? onChanged;

  /// Where the active track starts; [min] when null.
  final double? origin;
  final bool vertical;

  /// Accessibility increment; a hundredth of the range when null.
  final double? step;
  final String? semanticLabel;
  final String Function(double value)? semanticFormatterCallback;

  static const _trackThickness = 4.0;

  @override
  ConsumerState<AppLevelSlider> createState() => _AppLevelSliderState();
}

class _AppLevelSliderState extends ConsumerState<AppLevelSlider> {
  static const _activeKnobSize = Size(58, 38.33);
  static const _shadow = LiquidGlassShadow(inset: 3);

  /// Whether the current touch shows glass, decided at touch-down.
  bool? _touchGlass;

  double get value => widget.value;
  double get min => widget.min;
  double get max => widget.max;
  bool get vertical => widget.vertical;
  double get knobRadius => widget.knobRadius;
  ValueChanged<double>? get onChanged => widget.onChanged;

  double get _origin => (widget.origin ?? min).clamp(min, max);

  void _update(Offset local, Size size) {
    final extent = (vertical ? size.height : size.width) - knobRadius * 2;
    if (extent <= 0) return;
    var fraction = ((vertical ? local.dy : local.dx) - knobRadius) / extent;
    if (vertical) fraction = 1 - fraction;
    final next = min + fraction.clamp(0.0, 1.0) * (max - min);
    // A light tick when the knob reaches or crosses the origin.
    final at = _origin;
    if ((value - at).sign != (next - at).sign && value != next) {
      HapticFeedback.selectionClick();
    }
    onChanged?.call(next);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onChanged != null;
    final active = enabled ? scheme.primary : CupertinoColors.inactiveGray;
    final track = CupertinoColors.systemFill.resolveFrom(context);
    final increment = widget.step ?? (max - min) / 100;
    String format(double v) =>
        widget.semanticFormatterCallback?.call(v) ?? v.toStringAsFixed(1);
    final glassAllowed =
        enabled && !vertical && appGlassThumbsEnabled(context, ref);
    final glass = _touchGlass ?? glassAllowed;
    final outlines = glass && ref.watch(appGlassOutlinesProvider);
    void release() {
      if (_touchGlass != null) setState(() => _touchGlass = null);
    }

    return Semantics(
      slider: true,
      enabled: enabled,
      label: widget.semanticLabel,
      value: format(value),
      increasedValue: format((value + increment).clamp(min, max)),
      decreasedValue: format((value - increment).clamp(min, max)),
      onIncrease: enabled
          ? () => onChanged!((value + increment).clamp(min, max))
          : null,
      onDecrease: enabled
          ? () => onChanged!((value - increment).clamp(min, max))
          : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          // A 48 dp touch target across the track.
          final size = Size(
            vertical && !constraints.hasBoundedWidth
                ? 48
                : constraints.maxWidth,
            vertical ? constraints.maxHeight : 48,
          );
          void update(Offset local) => _update(local, size);
          final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
          final Widget gestures = GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: enabled ? (d) => update(d.localPosition) : null,
            onHorizontalDragStart: enabled && !vertical
                ? (d) => update(d.localPosition)
                : null,
            onHorizontalDragUpdate: enabled && !vertical
                ? (d) => update(d.localPosition)
                : null,
            onVerticalDragStart: enabled && vertical
                ? (d) => update(d.localPosition)
                : null,
            onVerticalDragUpdate: enabled && vertical
                ? (d) => update(d.localPosition)
                : null,
            child: CustomPaint(
              size: size,
              painter: _LevelPainter(
                fraction: fraction,
                origin: (_origin - min) / (max - min),
                vertical: vertical,
                active: active,
                track: track,
                knobRadius: knobRadius,
                paintKnob: !glass,
              ),
            ),
          );
          if (!glass) return gestures;
          final r = knobRadius;
          return Listener(
            onPointerDown: (_) {
              if (_touchGlass == null) {
                setState(() => _touchGlass = glassAllowed);
              }
            },
            onPointerUp: (_) => release(),
            onPointerCancel: (_) => release(),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                gestures,
                Positioned.fill(
                  child: AppGlassThumb(
                    center: Offset(
                      r + fraction * (size.width - r * 2),
                      size.height / 2,
                    ),
                    held: _touchGlass == true,
                    restSize: Size.square(r * 2),
                    activeSize: _activeKnobSize,
                    style: appGlassThumbStyle(outlines: outlines),
                    shadow: _shadow,
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _LevelPainter extends CustomPainter {
  const _LevelPainter({
    required this.fraction,
    required this.origin,
    required this.vertical,
    required this.active,
    required this.track,
    required this.knobRadius,
    this.paintKnob = true,
  });

  final double fraction, origin, knobRadius;
  final bool vertical;

  /// False while the knob is drawn as a glass thumb above the painter.
  final bool paintKnob;
  final Color active, track;

  @override
  void paint(Canvas canvas, Size size) {
    final r = knobRadius;
    const t = AppLevelSlider._trackThickness;
    final length = (vertical ? size.height : size.width) - r * 2;
    Offset at(double f) => vertical
        ? Offset(size.width / 2, r + (1 - f) * length)
        : Offset(r + f * length, size.height / 2);
    Rect span(double a, double b) {
      final p = at(a), q = at(b);
      return vertical
          ? Rect.fromLTRB(p.dx - t / 2, q.dy, p.dx + t / 2, p.dy)
          : Rect.fromLTRB(p.dx, p.dy - t / 2, q.dx, p.dy + t / 2);
    }

    const radius = Radius.circular(t / 2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(span(0, 1), radius),
      Paint()..color = track,
    );
    final low = fraction < origin ? fraction : origin;
    final high = fraction < origin ? origin : fraction;
    if (high > low) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(span(low, high), radius),
        Paint()..color = active,
      );
    }
    if (paintKnob) {
      const CupertinoThumbPainter().paint(
        canvas,
        Rect.fromCircle(center: at(fraction), radius: r),
      );
    }
  }

  @override
  bool shouldRepaint(_LevelPainter oldDelegate) =>
      oldDelegate.fraction != fraction ||
      oldDelegate.origin != origin ||
      oldDelegate.vertical != vertical ||
      oldDelegate.active != active ||
      oldDelegate.track != track ||
      oldDelegate.knobRadius != knobRadius ||
      oldDelegate.paintKnob != paintKnob;
}
