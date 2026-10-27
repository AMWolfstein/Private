import 'package:flutter/material.dart';
import 'package:sistrum/widgets/sistrum_context_menu.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/widgets/track_card.dart';
import 'package:sistrum/widgets/cached_cover_image.dart';

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
            // Grows with the text scale so 2-3 digit track numbers keep a line.
            width: MediaQuery.textScalerOf(context).scale(24),
            child: Text(
              number?.toString() ?? '-',
              maxLines: 1,
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
            excludeSemantics: true,
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
            LocalSongPlayButton(
              isPlaying: isPlaying,
              onPressed: onPlay,
              tooltip: isPlaying
                  ? context.l10n.a11yPauseTrack(title)
                  : artist.trim().isEmpty
                  ? context.l10n.a11yPlayTrack(title)
                  : context.l10n.a11yPlayTrackByArtist(title, artist),
            ),
        Builder(
          builder: (buttonContext) => IconButton(
            tooltip: context.l10n.a11yMoreOptionsFor(title),
            onPressed: () => onMenu(sistrumMenuAnchor(buttonContext)),
            icon: const Icon(Icons.more_horiz),
          ),
        ),
      ],
    ),
  );
}

/// The outlined circular Play/Pause control of song rows.
class LocalSongPlayButton extends StatelessWidget {
  const LocalSongPlayButton({
    super.key,
    required this.isPlaying,
    required this.onPressed,
    this.tooltip,
  });

  final bool isPlaying;
  final VoidCallback onPressed;

  /// Names the track for screen readers; falls back to Play/Pause.
  final String? tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip:
        tooltip ??
        (isPlaying ? context.l10n.actionPause : context.l10n.tooltipPlay),
    onPressed: onPressed,
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
        child: Icon(isPlaying ? Icons.pause : Icons.play_arrow, size: 20),
      ),
    ),
  );
}
