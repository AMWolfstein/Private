import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/lyrics_share_card.dart';
import 'package:sistrum/core/theme/app_theme.dart';

class BackgroundPicker extends StatelessWidget {
  const BackgroundPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final LyricsCardBackground value;
  final ValueChanged<LyricsCardBackground> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final labels = {
      LyricsCardBackground.artwork: l10n.lyricsShareBackgroundArtwork,
      LyricsCardBackground.color: l10n.lyricsShareBackgroundColor,
      LyricsCardBackground.dark: l10n.lyricsShareBackgroundDark,
      LyricsCardBackground.light: l10n.lyricsShareBackgroundLight,
    };
    final swatches = {
      LyricsCardBackground.artwork: const LinearGradient(
        colors: [Color(0xFF8E6BBF), Color(0xFF2C5E8C)],
      ),
      LyricsCardBackground.color: LinearGradient(
        colors: [colors.primary, colors.primaryContainer],
      ),
      LyricsCardBackground.dark: const LinearGradient(
        colors: [Color(0xFF2A2A2A), Color(0xFF0E0E0E)],
      ),
      LyricsCardBackground.light: const LinearGradient(
        colors: [Color(0xFFFFFFFF), Color(0xFFE8E4DC)],
      ),
    };
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      decoration: ShapeDecoration(
        color: colors.surfaceContainerHigh,
        shape: const StadiumBorder(),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (final option in LyricsCardBackground.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: option == value,
                inMutuallyExclusiveGroup: true,
                label: labels[option],
                child: Tooltip(
                  message: labels[option],
                  excludeFromSemantics: true,
                  // The whole cell stays tappable; the ripple lives inside
                  // the swatch so it takes the swatch's shape.
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onChanged(option),
                    child: SizedBox(
                      height: 52,
                      child: Center(
                        // Sistrum keeps round swatches with a selected ring.
                        child: AnimatedContainer(
                          duration: reduceMotion
                              ? Duration.zero
                              : const Duration(milliseconds: 260),
                          curve: Curves.easeOutCubic,
                          width: 36,
                          height: 36,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            gradient: swatches[option],
                            border: Border.all(
                              color: option == value
                                  ? colors.primary
                                  : colors.outlineVariant,
                              width: option == value ? 2.5 : 1,
                            ),
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              onTap: () => onChanged(option),
                              child: Center(
                                child: option == value
                                    ? Icon(
                                        Icons.check_rounded,
                                        size: 20,
                                        color:
                                            option == LyricsCardBackground.light
                                            ? const Color(0xFF111111)
                                            : Colors.white,
                                      )
                                    : option == LyricsCardBackground.artwork
                                    ? const Icon(
                                        Icons.image_outlined,
                                        size: 16,
                                        color: Colors.white,
                                      )
                                    : null,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// How many lines are quoted, against the card's limit.
class SelectionCount extends StatelessWidget {
  const SelectionCount({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final active = count > 0;
    return AnimatedContainer(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 200),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: ShapeDecoration(
        color: active ? colors.primaryContainer : colors.surfaceContainerHigh,
        shape: const StadiumBorder(),
      ),
      child: Semantics(
        liveRegion: true,
        container: true,
        child: Text(
          '$count/$lyricsShareMaxLines',
          style: theme.textTheme.labelLarge?.copyWith(
            color: active ? colors.onPrimaryContainer : colors.onSurfaceVariant,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}

class LineChoice extends StatelessWidget {
  const LineChoice({
    super.key,
    required this.line,
    required this.selected,
    required this.first,
    required this.last,
    required this.onTap,
  });

  final LyricsShareLine line;
  final bool selected;
  final bool first;
  final bool last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    // Inset Sistrum rows retain their corners while selection changes.
    const outer = Radius.circular(20);
    const inner = Radius.circular(6);
    final radius = BorderRadius.vertical(
      top: first ? outer : inner,
      bottom: last ? outer : inner,
    );
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220);
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 2),
      child: MergeSemantics(
        child: Semantics(
          checked: selected,
          // The container clips its own ink, so the press highlight follows
          // the corners while they animate.
          child: AnimatedContainer(
            duration: duration,
            curve: Curves.easeOutCubic,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: selected
                  ? colors.secondaryContainer
                  : AppTheme.controlFill(context),
              borderRadius: radius,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          duration: duration,
                          curve: Curves.easeOutCubic,
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: selected ? colors.primary : null,
                            borderRadius: BorderRadius.circular(12),
                            border: selected
                                ? null
                                : Border.all(color: colors.outline, width: 2),
                          ),
                          child: selected
                              ? Icon(
                                  Icons.check_rounded,
                                  size: 18,
                                  color: colors.onPrimary,
                                )
                              : null,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Text(
                            line.text,
                            style:
                                (line.background
                                        ? theme.textTheme.bodyMedium
                                        : theme.textTheme.bodyLarge)
                                    ?.copyWith(
                                      color: selected
                                          ? colors.onSecondaryContainer
                                          : colors.onSurface,
                                    ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
