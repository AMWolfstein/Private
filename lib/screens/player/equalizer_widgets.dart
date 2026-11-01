// SPDX-License-Identifier: LGPL-3.0-only
// Copyright 2026 zarzet and contributors; adapted from Mornye v5.3.0.
part of 'equalizer_screen.dart';

/// iOS section footer: secondary text under the group it explains.
class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final inset = wideListInset(context) + 16;
      final theme = Theme.of(context);
      return Padding(
        padding: EdgeInsets.fromLTRB(inset, 4, inset, 8),
        child: Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    },
  );
}

/// iOS "value" cell detail: the current choice in secondary text before the
/// disclosure chevron.
class _DetailValue extends StatelessWidget {
  const _DetailValue(this.value);

  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final secondary = theme.colorScheme.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 160),
          child: Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyLarge?.copyWith(color: secondary),
          ),
        ),
        const SizedBox(width: 6),
        _AppEqualizerIcon(Icons.chevron_right, size: 20, color: secondary),
      ],
    );
  }
}

/// iOS action cell: tinted text that runs a command instead of navigating.
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.onTap,
    this.destructive = false,
    this.last = false,
  });

  final String label;
  final VoidCallback? onTap;
  final bool destructive, last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final color = onTap == null
        ? theme.disabledColor
        : destructive
        ? colors.error
        : colors.primary;
    return Semantics(
      button: true,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: onTap,
            highlightColor: colors.onSurface.withValues(alpha: 0.06),
            splashFactory: NoSplash.splashFactory,
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: tokens.minTouchTarget),
              child: Padding(
                padding: EdgeInsets.symmetric(
                  horizontal: tokens.rowPaddingH,
                  vertical: tokens.rowPaddingV,
                ),
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    label,
                    style: theme.textTheme.bodyLarge?.copyWith(color: color),
                  ),
                ),
              ),
            ),
          ),
          if (!last)
            Divider(
              height: 1,
              indent: tokens.rowPaddingH,
              endIndent: tokens.rowPaddingH,
              color: colors.outlineVariant,
            ),
        ],
      ),
    );
  }
}

/// Status, master switch and the estimated response of the whole chain.
class _EqualizerOverview extends StatelessWidget {
  const _EqualizerOverview({required this.settings, required this.presetName});

  final EqualizerSettings settings;
  final String presetName;

  /// Shows the master switch beside the title; Mornye keeps it in its own
  /// row above.

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final enabled = settings.enabled;
    final curveColor = enabled ? colors.primary : colors.outline;
    return Padding(
      padding: EdgeInsetsDirectional.fromSTEB(
        tokens.rowPaddingH,
        tokens.gapLg,
        tokens.gapLg,
        tokens.gapLg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedDefaultTextStyle(
                      duration: tokens.motionMedium,
                      style: theme.textTheme.headlineSmall!.copyWith(
                        fontWeight: FontWeight.w600,
                        color: enabled
                            ? colors.onSurface
                            : colors.onSurfaceVariant,
                      ),
                      child: Text(
                        presetName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    SizedBox(height: tokens.gapXs),
                    Row(
                      children: [
                        const BetaBadge(),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Text(
                            '${settings.gains.length} ${l10n.equalizerBands.toLowerCase()} · ${l10n.equalizerPreamp} ${_signed(settings.inputGain)} dB',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colors.onSurfaceVariant,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: tokens.gapLg),
          Semantics(
            label: l10n.equalizerCurveDescription,
            child: SizedBox(
              height: 152,
              child: TweenAnimationBuilder<Color?>(
                tween: ColorTween(end: curveColor),
                duration: tokens.motionMedium,
                builder: (context, color, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _EqualizerCurve(
                    settings: settings,
                    color: color ?? curveColor,
                    grid: colors.outlineVariant,
                    label: colors.onSurfaceVariant,
                    labelStyle: theme.textTheme.labelSmall!,
                    textScaler: MediaQuery.textScalerOf(context),
                  ),
                ),
              ),
            ),
          ),
          SizedBox(height: tokens.gapSm),
          Text(
            l10n.equalizerCurve,
            style: theme.textTheme.bodySmall?.copyWith(
              color: colors.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Quick-apply chips for every preset, plus save, reset and overflow actions.
class _BandEditor extends StatelessWidget {
  const _BandEditor({required this.settings, required this.onChanged});

  final EqualizerSettings settings;
  final ValueChanged<EqualizerSettings> onChanged;

  static const _minColumnWidth = 32.0;
  static const _faderHeight = 208.0;

  void _setGain(int index, double value) {
    final gains = [...settings.gains];
    gains[index] = value;
    onChanged(settings.copyWith(gains: gains));
  }

  Widget _countPicker(BuildContext context) {
    final counts = EqualizerSettings.bandCounts;
    return Semantics(
      label: context.l10n.equalizerBands,
      child: AppSegmentedControl(
        labels: [for (final n in counts) '$n'],
        selectedIndex: counts.indexOf(settings.gains.length),
        onChanged: (i) => onChanged(settings.withBandCount(counts[i])),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final l10n = context.l10n;
    final count = settings.gains.length;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: tokens.gapLg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: tokens.gapLg),
            child: SizedBox(
              width: double.infinity,
              child: _countPicker(context),
            ),
          ),
          SizedBox(height: tokens.gapLg),
          LayoutBuilder(
            builder: (context, constraints) {
              final available = constraints.maxWidth - tokens.gapSm * 2;
              final width = math.max(_minColumnWidth, available / count);
              final scrolls = width * count > available + 0.5;
              final faders = Row(
                children: [
                  for (var i = 0; i < count; i++)
                    SizedBox(
                      width: width,
                      child: _BandFader(
                        frequency: settings.frequencies[i],
                        gain: settings.gains[i],
                        width: width,
                        height: _faderHeight,
                        resetLabel: l10n.libraryFilterReset,
                        onChanged: (v) => _setGain(i, v),
                      ),
                    ),
                ],
              );
              return Stack(
                children: [
                  // 0 dB reference across every fader.
                  Positioned(
                    left: tokens.gapSm,
                    right: tokens.gapSm,
                    top: _BandFader.labelExtent + _faderHeight / 2,
                    child: Divider(
                      height: 1,
                      color: colors.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  scrolls
                      ? SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.gapSm,
                          ),
                          child: faders,
                        )
                      : Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: tokens.gapSm,
                          ),
                          child: faders,
                        ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _BandFader extends StatelessWidget {
  const _BandFader({
    required this.frequency,
    required this.gain,
    required this.width,
    required this.height,
    required this.resetLabel,
    required this.onChanged,
  });

  final double frequency;
  final double gain;
  final double width;
  final double height;
  final String resetLabel;
  final ValueChanged<double> onChanged;

  /// Height of the gain label and its gap above the fader, so the 0 dB line
  /// can align with the faders' centers.
  static const labelExtent = 32.0 + 4;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final active = gain != 0;
    final mornye = context.isAppTheme;
    final hz = _frequency(frequency);
    final valueStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontFeatures: const [FontFeature.tabularFigures()],
      color: !active
          ? colors.onSurfaceVariant
          : mornye
          ? colors.primary
          : colors.onSecondaryContainer,
    );
    final semanticLabel = '$hz Hz';
    String semantics(double v) => '${v.toStringAsFixed(1)} dB';
    return Column(
      children: [
        // Tapping the gain returns the band to 0 dB.
        Tooltip(
          message: '$resetLabel $hz Hz',
          child: SizedBox(
            height: 32,
            child: Center(
              child: Material(
                // iOS shows the gain as plain tinted text, Material as a badge.
                color: active && !mornye
                    ? colors.secondaryContainer
                    : Colors.transparent,
                shape: const StadiumBorder(),
                clipBehavior: Clip.antiAlias,
                animationDuration: tokens.motionFast,
                child: InkWell(
                  onTap: active ? () => onChanged(0) : null,
                  child: Container(
                    height: 28,
                    constraints: BoxConstraints(maxWidth: width - 2),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    alignment: Alignment.center,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(_signed(gain), style: valueStyle),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: height,
          child: AppLevelSlider(
            vertical: true,
            value: gain,
            min: -15,
            max: 15,
            origin: 0,
            step: 0.5,
            knobRadius: ((width - 8) / 2).clamp(9.0, 14.0),
            semanticLabel: semanticLabel,
            semanticFormatterCallback: semantics,
            onChanged: (v) => onChanged(_snap(v, 0.5)),
          ),
        ),
        SizedBox(height: tokens.gapSm),
        SizedBox(
          height: 20,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              hz,
              style: theme.textTheme.labelSmall?.copyWith(
                color: colors.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A labelled slider row with its live value in a tonal badge.
class _SliderTile extends StatelessWidget {
  const _SliderTile({
    required this.title,
    required this.value,
    required this.min,
    required this.max,
    required this.step,
    required this.unit,
    required this.onChanged,
    this.subtitle,
    this.centered = false,
    this.signed = true,
    this.last = false,
  });

  final String title;
  final String? subtitle;
  final double value, min, max, step;
  final String unit;
  final bool centered, signed;

  /// Aligns an icon-less sub-setting with the text of the rows above it.

  /// Ends a Mornye group, which separates rows with hairlines.
  final bool last;
  final ValueChanged<double> onChanged;

  String _format(double v) {
    final digits = step < 1 ? 1 : 0;
    final text = signed && v > 0
        ? '+${v.toStringAsFixed(digits)}'
        : v.toStringAsFixed(digits).replaceFirst('-', '−');
    return unit == '%' || unit.startsWith(':') ? '$text$unit' : '$text $unit';
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    return SettingsSearchTarget(
      label: title,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
              tokens.rowPaddingH,
              tokens.rowPaddingVCompact,
              tokens.rowPaddingH,
              0,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: theme.textTheme.bodyLarge),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                    ),
                    Text(
                      _format(value),
                      style: theme.textTheme.bodyLarge?.copyWith(
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
                SizedBox(
                  height: 48,
                  child: AppLevelSlider(
                    value: value.clamp(min, max),
                    min: min,
                    max: max,
                    origin: centered ? (min + max) / 2 : null,
                    step: step,
                    semanticLabel: title,
                    semanticFormatterCallback: _format,
                    onChanged: (v) => onChanged(_snap(v, step).clamp(min, max)),
                  ),
                ),
              ],
            ),
          ),
          if (!last)
            Divider(
              height: 1,
              indent: tokens.rowPaddingH,
              endIndent: tokens.rowPaddingH,
              color: theme.colorScheme.outlineVariant,
            ),
        ],
      ),
    );
  }
}

class _PresetNameDialog extends StatefulWidget {
  const _PresetNameDialog();

  @override
  State<_PresetNameDialog> createState() => _PresetNameDialogState();
}

class _PresetNameDialogState extends State<_PresetNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AppAlertDialog(
    title: Text(context.l10n.equalizerSavePreset),
    content: TextField(
      controller: _controller,
      decoration: InputDecoration(labelText: context.l10n.equalizerPresetName),
      maxLength: 80,
      autofocus: true,
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      AppDialogAction(
        onPressed: () => Navigator.pop(context),
        child: Text(context.l10n.dialogCancel),
      ),
      AppDialogAction(onPressed: _submit, child: Text(context.l10n.dialogSave)),
    ],
  );
}

class _AppEqualizerIcon extends StatelessWidget {
  const _AppEqualizerIcon(this.icon, {this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) =>
      Icon(appIconFor(icon), size: size, color: color);
}
