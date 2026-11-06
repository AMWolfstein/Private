import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_atlas.dart';

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
                ? 'Gaussian sigma of the live backdrop (Frosted and Full)'
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
                : unsupported('Tint (the Opaque tier has no transparency)'),
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
                      ? 'Full tier: blur, then the Sistrum lens shader'
                      : 'Off: the Frosted blur is drawn, which is not refraction')
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
        SwitchListTile(
          key: const Key('hybridSharedBackdrop'),
          dense: true,
          title: const Text('Shared backdrop read (matrix variant E)'),
          subtitle: Text(
            config.sharedAtlas
                ? 'Disabled while the shared backdrop atlas is on'
                : caps.sharedBackdrop
                ? 'One backdrop read for surfaces that cannot see each other '
                      '(BackdropFilter.backdropGroupKey)'
                : unsupported('Shared backdrop (this tier reads no backdrop)'),
          ),
          value: config.sharedBackdrop,
          onChanged: caps.sharedBackdrop && !config.sharedAtlas && !running
              ? (v) => update((c) => c.copyWith(sharedBackdrop: v))
              : null,
        ),
        SwitchListTile(
          key: const Key('hybridSharedAtlas'),
          dense: true,
          title: const Text('Shared backdrop atlas (experimental)'),
          subtitle: Text(_atlasSubtitle(config)),
          value: config.sharedAtlas,
          onChanged: running
              ? null
              : (v) => update((c) => c.copyWith(sharedAtlas: v)),
        ),
        ListTile(
          dense: true,
          enabled: config.sharedAtlas && !running,
          title: const Text('Atlas resolution (experimental)'),
          subtitle: Text(
            config.sharedAtlas
                ? 'Capture resolution as a fraction of native pixels. Blur '
                      'stays at the same logical radius.'
                : 'Applies when the shared backdrop atlas is on.',
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Align(
            alignment: AlignmentDirectional.centerStart,
            child: DropdownButton<SistrumAtlasResolution>(
              key: const Key('hybridAtlasResolution'),
              isExpanded: true,
              value: config.atlasResolution,
              items: [
                for (final r in SistrumAtlasResolution.values)
                  DropdownMenuItem(value: r, child: Text(r.label)),
              ],
              onChanged: config.sharedAtlas && !running
                  ? (v) {
                      if (v != null) {
                        update((c) => c.copyWith(atlasResolution: v));
                      }
                    }
                  : null,
            ),
          ),
        ),
        ListTile(
          dense: true,
          enabled: false,
          title: Text(unsupported('Saturation (1.5 reference)')),
          subtitle: const Text(
            'Not applied to any Sistrum Hybrid tier. See docs/performance for the reasons.',
          ),
        ),
      ],
    );
  }
}

/// What the atlas switch does for [config], including unsupported cases,
/// which keep the existing pipeline and are reported instead of degraded.
String _atlasSubtitle(SistrumHybridConfig config) {
  final reason = config.copyWith(sharedAtlas: true).atlasUnsupportedReason;
  final what =
      'One capture of the content under all glass, blurred once at low '
      'resolution and sampled per surface, in the same frame';
  if (reason == null) return what;
  final why = switch (reason) {
    'refraction_not_supported_by_atlas' =>
      'Not supported with refraction on: the lens needs a backdrop filter',
    'zero_blur_bypass' => 'Not used at blur 0: nothing reads the backdrop',
    'tier_reads_no_backdrop' => 'Not used: this tier reads no backdrop',
    _ => 'Not supported: $reason',
  };
  return config.sharedAtlas
      ? '$why. The existing pipeline is drawn and the reason is reported.'
      : '$what. $why.';
}
