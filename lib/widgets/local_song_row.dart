import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/mornye_context_menu.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/widgets/track_card.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';

/// Shared local song layout. Albums supply a number instead of artwork.
class LocalSongRow extends StatelessWidget {
  const LocalSongRow({
    super.key,
    required this.title,
    required this.artist,
    required this.onPlay,
    required this.onMenu,
    this.cover,
    this.number,
    this.numbered = false,
    this.explicit = false,
    this.isPlaying = false,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onSelect,
    this.onLongPress,
    this.artistWidget,
    this.playControl,
  });
  final String title, artist;
  final String? cover;
  final int? number;
  final bool numbered, explicit, isPlaying, isSelectionMode, isSelected;
  final Widget? artistWidget, playControl;
  final VoidCallback onPlay;
  final ValueChanged<Rect?> onMenu;
  final VoidCallback? onSelect, onLongPress;
  @override
  Widget build(BuildContext context) => TrackCard(
    style: TrackCardStyle.flat,
    isSelectionMode: isSelectionMode,
    isSelected: isSelected,
    onTap: isSelectionMode ? onSelect : onPlay,
    onLongPress: onLongPress,
    leading: numbered
        ? SizedBox(
            width: 24,
            child: Text(
              number?.toString() ?? '-',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          )
        : SizedBox.square(
            dimension: 48,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: cover?.isNotEmpty == true
                  ? LocalCoverImage(
                      url: cover!,
                      width: 48,
                      height: 48,
                      placeholder: (_) => const TrackCoverPlaceholder(size: 48),
                    )
                  : const TrackCoverPlaceholder(size: 48),
            ),
          ),
    title: title,
    titleTrailing: explicit
        ? Semantics(
            label: context.l10n.metadataExplicitValue,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                'E',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.surface,
                ),
              ),
            ),
          )
        : null,
    subtitle:
        artistWidget ??
        Text(
          artist,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
    trailing: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        playControl ??
            IconButton(
              tooltip: isPlaying
                  ? context.l10n.actionPause
                  : context.l10n.tooltipPlay,
              onPressed: onPlay,
              icon: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    width: 1.5,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    isPlaying ? Icons.pause : Icons.play_arrow,
                    size: 20,
                  ),
                ),
              ),
            ),
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
            onPressed: () => onMenu(mornyeMenuAnchor(buttonContext)),
            icon: const Icon(Icons.more_horiz),
          ),
        ),
      ],
    ),
  );
}
