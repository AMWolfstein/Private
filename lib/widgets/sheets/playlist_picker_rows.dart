import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/widgets/cover/cached_cover_image.dart';

class PlaylistPickerRow extends StatelessWidget {
  const PlaylistPickerRow({
    super.key,
    required this.leading,
    required this.title,
    this.subtitle,
    this.enabled = true,
    this.selected,
    this.onTap,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final bool enabled;
  final bool? selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CupertinoButton(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            onPressed: enabled ? onTap : null,
            child: Opacity(
              opacity: enabled ? 1 : 0.5,
              child: Row(
                children: [
                  leading,
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        DefaultTextStyle(
                          style: theme.textTheme.bodyLarge!,
                          child: title,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 3),
                          DefaultTextStyle(
                            style: theme.textTheme.bodyMedium!.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                            child: subtitle!,
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (selected != null) ...[
                    const SizedBox(width: 14),
                    Icon(
                      selected!
                          ? CupertinoIcons.checkmark_circle_fill
                          : CupertinoIcons.circle,
                      size: 24,
                      color: selected!
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
          const Divider(height: 0.5, thickness: 0.5, indent: 20, endIndent: 20),
        ],
      ),
    );
  }
}

class PlaylistPickerThumbnail extends StatelessWidget {
  final PlaylistPickerSummary playlist;
  final bool isSelected;

  const PlaylistPickerThumbnail({
    super.key,
    required this.playlist,
    required this.isSelected,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    const double size = 48;
    final borderRadius = BorderRadius.circular(8);

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: borderRadius,
            child: _buildCoverImage(context, colorScheme, size),
          ),
          if (isSelected) ...[
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.3),
                  borderRadius: borderRadius,
                ),
              ),
            ),
            PositionedDirectional(
              end: 2,
              top: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(color: colorScheme.primary, width: 1.5),
                ),
                child: Icon(
                  Icons.check,
                  color: colorScheme.onPrimary,
                  size: 14,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoverImage(
    BuildContext context,
    ColorScheme colorScheme,
    double size,
  ) {
    final customCoverPath = playlist.coverImagePath;
    if (customCoverPath != null && customCoverPath.isNotEmpty) {
      return Image.file(
        File(customCoverPath),
        width: size,
        height: size,
        fit: BoxFit.cover,
        cacheWidth: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        cacheHeight: (size * MediaQuery.devicePixelRatioOf(context)).round(),
        filterQuality: FilterQuality.low,
        errorBuilder: (_, _, _) => _iconFallback(context, colorScheme, size),
      );
    }

    final firstCoverUrl = playlist.previewCover;
    if (firstCoverUrl != null) {
      return LocalCoverImage(
        url: firstCoverUrl,
        width: size,
        height: size,
        placeholder: (_) => _iconFallback(context, colorScheme, size),
      );
    }

    return _iconFallback(context, colorScheme, size);
  }

  Widget _iconFallback(
    BuildContext context,
    ColorScheme colorScheme,
    double size,
  ) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        CupertinoIcons.music_note_list,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }
}
