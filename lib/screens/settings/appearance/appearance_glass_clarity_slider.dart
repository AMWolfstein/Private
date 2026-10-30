import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/core/models/app_glass.dart';
import 'package:sistrum/services/glass/app_glass_auto_probe.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome.dart';
import 'package:sistrum/widgets/primitives/app_slider.dart';

class AppGlassClaritySlider extends ConsumerStatefulWidget {
  const AppGlassClaritySlider({super.key});

  @override
  ConsumerState<AppGlassClaritySlider> createState() =>
      _AppGlassClaritySliderState();
}

class _AppGlassClaritySliderState extends ConsumerState<AppGlassClaritySlider> {
  /// Only the preview follows a drag; the rest of the app updates on release.
  int? _dragLevel;

  @override
  Widget build(BuildContext context) {
    // The saved level; glass may render lower where Auto measured it.
    final int level =
        _dragLevel ??
        ref.watch(settingsProvider.select((s) => s.glassClarityLevel));
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);
    final l10n = context.l10n;
    // Match the renderer's policy without changing the stored clarity value.
    final contrastBlocked = ref.watch(
      appGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );
    final quality = ref.watch(appGlassQualityProvider);
    // Auto measured that this device needs Level 1.
    final autoFrosted =
        quality == AppGlassQuality.auto &&
        ref.watch(appGlassClarityLevelProvider) == 1 &&
        ref.watch(appGlassAutoStepProvider) == AppGlassAutoStep.liteFrosted;
    final adjustable =
        !contrastBlocked && ref.watch(appBlurEnabledProvider) && !autoFrosted;
    final levelNames = [
      l10n.appearanceGlassLevelFrosted,
      l10n.appearanceGlassLevelSoft,
      l10n.appearanceGlassLevelBalanced,
      l10n.appearanceGlassLevelClear,
      l10n.appearanceGlassLevelCrystal,
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.appearanceGlassClarity, style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            l10n.appearanceGlassClaritySubtitle,
            style: theme.textTheme.bodySmall,
          ),
          if (!adjustable) ...[
            const SizedBox(height: 8),
            Text(
              contrastBlocked
                  ? l10n.appearanceGlassClarityContrast
                  : autoFrosted
                  ? l10n.appearanceGlassClarityAutoFrosted
                  : quality == AppGlassQuality.off
                  ? l10n.appearanceGlassClarityOff
                  : l10n.appearanceGlassClarityDeviceOpaque,
              key: const ValueKey('sistrum-glass-clarity-unavailable'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          const SizedBox(height: 16),
          // Separate layers: the thumb animation must not repaint the glass
          // preview, and preview blur must not repaint the slider.
          RepaintBoundary(
            child: ExcludeSemantics(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        for (final color in [
                          theme.colorScheme.primary,
                          const Color(0xff277f94),
                          const Color(0xffc69756),
                        ])
                          // Preview light glass over a light backdrop, as in the
                          // app. Dense sample colors make white glass look gray.
                          theme.brightness == Brightness.light
                              ? Color.lerp(Colors.white, color, 0.4)!
                              : color,
                      ],
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: AppGlassPanel(
                      radius: 22,
                      clarityLevel: level,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.music_note_rounded),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Sistrum',
                                style: theme.textTheme.titleMedium,
                              ),
                            ),
                            const Icon(Icons.play_arrow_rounded),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          RepaintBoundary(
            child: Semantics(
              label: l10n.appearanceGlassClarity,
              child: AppSlider(
                key: const ValueKey('sistrum-glass-clarity'),
                value: level.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                label: levelNames[level - 1],
                semanticFormatterCallback: (value) =>
                    levelNames[value.round().clamp(1, 5) - 1],
                onChanged: adjustable
                    ? (value) => setState(() => _dragLevel = value.round())
                    : null,
                onChangeEnd: adjustable
                    ? (value) {
                        // Commit, persist and update the app in a single step.
                        notifier.setGlassClarityLevel(value.round());
                        setState(() => _dragLevel = null);
                      }
                    : null,
              ),
            ),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                l10n.appearanceGlassTinted,
                style: theme.textTheme.bodySmall,
              ),
              Text(l10n.appearanceGlassClear, style: theme.textTheme.bodySmall),
            ],
          ),
          // Only full Crystal glass costs noticeably more to render.
          if (adjustable &&
              level == 5 &&
              ref.watch(appGlassLevelProvider) == AppGlassLevel.liquid) ...[
            const SizedBox(height: 8),
            Text(
              l10n.appearanceGlassClearPerformance,
              key: const ValueKey('sistrum-glass-clear-performance'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
