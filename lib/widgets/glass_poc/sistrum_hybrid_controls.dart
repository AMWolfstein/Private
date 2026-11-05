import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';

/// Developer controls for Sistrum Hybrid. A control that the selected tier
/// does not implement is shown disabled, with its reason, never as working.
class SistrumHybridControls extends ConsumerWidget {
  const SistrumHybridControls({required this.running, super.key});

  /// Disables every control while a benchmark run holds the configuration.
  final bool running;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref.watch(glassPocHybridProvider);
    final caps = config.capabilities;
    final notifier = ref.read(glassPocHybridProvider.notifier);
    void update(SistrumHybridConfig Function(SistrumHybridConfig) change) {
      if (!running) notifier.update(change);
    }

    String unsupported(String what) =>
        '$what: not implemented for Sistrum Hybrid';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            'Sistrum Hybrid tier',
            style: Theme.of(context).textTheme.titleSmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SegmentedButton<SistrumHybridTier>(
            segments: [
              for (final tier in SistrumHybridTier.values)
                ButtonSegment(value: tier, label: Text(tier.label)),
            ],
            selected: {config.tier},
            onSelectionChanged: running
                ? null
                : (s) => update((c) => c.copyWith(tier: s.first)),
          ),
        ),
        ListTile(
          dense: true,
          enabled: caps.blur && !running,
          title: Text('Blur radius: ${config.blurSigma.toStringAsFixed(1)} px'),
          subtitle: Text(
            caps.blur
                ? 'Gaussian sigma of the live backdrop (Frosted)'
                : unsupported('Blur (this tier has no backdrop blur)'),
          ),
        ),
        Slider(
          value: config.blurSigma,
          min: 0,
          max: 24,
          divisions: 48,
          onChanged: caps.blur && !running
              ? (v) => update((c) => c.copyWith(blurSigma: v))
              : null,
        ),
        ListTile(
          dense: true,
          enabled: caps.tint && !running,
          title: Text('Tint opacity: ${(config.tintOpacity * 100).round()}%'),
          subtitle: Text(
            caps.tint
                ? 'Theme-adaptive tint over the surface'
                : unsupported('Tint (the Full tier uses the package tint)'),
          ),
        ),
        Slider(
          value: config.tintOpacity,
          min: 0,
          max: 1,
          divisions: 20,
          onChanged: caps.tint && !running
              ? (v) => update((c) => c.copyWith(tintOpacity: v))
              : null,
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Genuine refraction'),
          subtitle: Text(
            caps.refraction
                ? (config.refraction
                      ? 'Full tier: refractive surface'
                      : 'Off: FakeGlass is drawn, which is not refraction')
                : unsupported('Refraction (Full tier only)'),
          ),
          value: config.refraction,
          onChanged: caps.refraction && !running
              ? (v) => update((c) => c.copyWith(refraction: v))
              : null,
        ),
        SwitchListTile(
          dense: true,
          title: const Text('Chromatic aberration'),
          subtitle: Text(
            caps.chromaticAberration
                ? 'Dispersion of the Full tier (needs refraction on)'
                : unsupported('Chromatic aberration (Full tier only)'),
          ),
          value: config.chromaticAberration,
          onChanged: caps.chromaticAberration && config.refraction && !running
              ? (v) => update((c) => c.copyWith(chromaticAberration: v))
              : null,
        ),
        ListTile(
          dense: true,
          enabled: false,
          title: Text(unsupported('Sampling scale (0.33 reference)')),
          subtitle: const Text(
            'Flutter cannot downsample a BackdropFilter input; the tiers sample at native resolution.',
          ),
        ),
        ListTile(
          dense: true,
          enabled: false,
          title: Text(
            unsupported('Saturation (1.5 reference) and shared backdrop'),
          ),
          subtitle: const Text(
            'Not applied to any Sistrum Hybrid tier. See docs/performance for the reasons.',
          ),
        ),
      ],
    );
  }
}
