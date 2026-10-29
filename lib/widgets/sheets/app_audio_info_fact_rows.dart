import 'package:flutter/material.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/widgets/sheets/audio_info_facts.dart';

/// Sistrum sheets are glass, so a settings cell color would vanish into them;
/// rows use the translucent control fill, like the track details page.
class AppAudioInfoFactGroup extends StatelessWidget {
  const AppAudioInfoFactGroup({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: AppTheme.controlFill(context),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }
}

class AppAudioInfoFactRow extends StatelessWidget {
  const AppAudioInfoFactRow({
    super.key,
    required this.fact,
    required this.last,
  });

  final AudioInfoFact fact;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;

    // Sistrum rows line up with the section header, as in iOS inset lists.
    final inset = 16.0;
    final valueStyle = (theme.textTheme.bodyLarge)?.copyWith(
      color: fact.emphasis ? colors.primary : colors.onSurfaceVariant,
      fontWeight: fact.emphasis ? FontWeight.w600 : null,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return MergeSemantics(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(minHeight: tokens.minTouchTarget),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: inset,
                vertical: tokens.rowPaddingVCompact,
              ),
              child: LayoutBuilder(
                // The value keeps its natural width up to just over half the
                // row, so short values never squeeze long labels onto two lines.
                builder: (context, constraints) => Row(
                  children: [
                    Expanded(
                      child: Text(fact.label, style: theme.textTheme.bodyLarge),
                    ),
                    SizedBox(width: tokens.gapMd),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: constraints.maxWidth * 0.55,
                      ),
                      child: Text(
                        fact.value,
                        textAlign: TextAlign.end,
                        style: valueStyle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (!last)
            Divider(
              height: 1,
              indent: inset,
              endIndent: 0,
              color: AppTheme.metadataDividerColor(context),
            ),
        ],
      ),
    );
  }
}
