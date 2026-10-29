import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/widgets/animation_utils.dart';

/// How a [TrackCard] paints its container.
enum TrackCardStyle {
  /// Filled card surface. Used where rows are discrete objects the user acts
  /// on individually: the local library.
  filled,

  /// Transparent container. Used inside a collection that already has its own
  /// header and reads as one continuous list: album, playlist and folder track
  /// lists.
  flat,
}

/// The one track row in the app.
///
/// Screens provide [leading], [subtitle], [trailing], and an optional
/// [background] layer for download progress.
class TrackCard extends StatelessWidget {
  const TrackCard({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.titleTrailing,
    this.trailing,
    this.background,
    this.style = TrackCardStyle.filled,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
    this.margin,
  });

  /// Track number, cover art, or anything else that identifies the row.
  final Widget leading;

  final String title;
  final Widget? titleTrailing;

  /// Secondary line. A widget rather than a string because callers mix in
  /// clickable artist names, quality badges and status text.
  final Widget? subtitle;

  /// Hidden while [isSelectionMode] is active, so the row cannot be acted on
  /// while the user is picking items.
  final Widget? trailing;

  /// Painted behind the content, clipped to the card. Used for the queue's
  /// progress fill.
  final Widget? background;

  final TrackCardStyle style;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Overrides the default outer margin. Prefer the default so track lists stay
  /// aligned with each other.
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final borderRadius = tokens.borderRadiusCover;
    final contentPadding = style == TrackCardStyle.flat
        ? EdgeInsetsDirectional.fromSTEB(
            tokens.gapMd,
            tokens.gapMd,
            6,
            tokens.gapMd,
          )
        : EdgeInsetsDirectional.all(tokens.gapMd);

    final Color? cardColor;
    if (isSelected) {
      cardColor = colorScheme.primaryContainer.withValues(alpha: 0.3);
    } else {
      cardColor = Colors.transparent;
    }

    final card = Card(
      elevation: 0,
      // The two styles carry their own outer margin so no call site has to
      // repeat it: flat rows sit tight inside a collection list, filled cards
      // get the Material list margin.
      margin:
          margin ??
          (style == TrackCardStyle.flat
              ? EdgeInsets.symmetric(horizontal: tokens.gapSm, vertical: 2)
              : EdgeInsets.symmetric(
                  horizontal: tokens.gapLg,
                  vertical: tokens.gapXs,
                )),
      color: cardColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: borderRadius,
        child: Stack(
          children: [
            if (background != null) Positioned.fill(child: background!),
            Padding(
              padding: contentPadding,
              child: Row(
                children: [
                  if (isSelectionMode) ...[
                    Semantics(
                      checked: isSelected,
                      label: isSelected
                          ? context.l10n.a11yDeselectTrack
                          : context.l10n.a11ySelectTrack,
                      child: AnimatedSelectionCheckbox(
                        visible: true,
                        selected: isSelected,
                        colorScheme: colorScheme,
                        size: 24,
                      ),
                    ),
                    SizedBox(width: tokens.gapMd),
                  ],
                  leading,
                  SizedBox(width: tokens.gapMd),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                            if (titleTrailing != null) ...[
                              const SizedBox(width: 6),
                              titleTrailing!,
                            ],
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          subtitle!,
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null && !isSelectionMode) ...[
                    SizedBox(width: tokens.gapSm),
                    trailing!,
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        card,
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: tokens.coverList + 40,
            end: 20,
          ),
          child: const Divider(),
        ),
      ],
    );
  }
}

/// Square artwork placeholder shared by every track row and grid cell.
class TrackCoverPlaceholder extends StatelessWidget {
  const TrackCoverPlaceholder({super.key, this.size, this.borderRadius});

  /// Omit to fill the available space (grid cells).
  final double? size;

  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: borderRadius ?? tokens.borderRadiusThumb,
      ),
      child: Icon(
        Icons.music_note,
        color: colorScheme.onSurfaceVariant,
        size: size == null ? null : size! * 0.45,
      ),
    );
  }
}
