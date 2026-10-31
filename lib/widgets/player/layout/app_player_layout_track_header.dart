part of 'app_player_layout.dart';

extension _AppPlayerLayoutPart1 on AppPlayerLayout {
  Widget _trackHeader(
    BuildContext context,
    ColorScheme colorScheme, {
    bool compact = false,
    double? compactProgress,
  }) {
    final progress = compactProgress ?? (compact ? 1.0 : 0.0);
    final actionSize = compactProgress == null
        ? (page == 0 ? 24.0 : kAppPlayerCompactIconSize)
        : 24 + (kAppPlayerCompactIconSize - 24) * progress;
    return Builder(
      builder: (context) => Row(
        children: [
          Expanded(
            child: PlayerTrackSwipeTitles(
              current: mediaItem,
              builder: (mediaItem) => Builder(
                builder: (titleContext) => InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap:
                      (mediaItem.artist ?? '').trim().isEmpty &&
                          (mediaItem.album ?? '').trim().isEmpty
                      ? null
                      : () => onTrackNavigation(titleContext, mediaItem),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OverflowMarquee(
                        resetKey: (mediaItem.id, mediaItem.title),
                        child: PlayerMetadataTitle(
                          mediaItem: mediaItem,
                          metadata: metadata,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 22 - 4 * progress,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      OverflowMarquee(
                        resetKey: (mediaItem.id, mediaItem.artist),
                        child: Text(
                          mediaItem.artist ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20 - 4 * progress,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.72,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AppPlayerFavoriteButton(
            key: ValueKey(mediaItem.id),
            mediaItem: mediaItem,
            compact: page != 0,
            iconSize: actionSize,
            color: colorScheme.onSurface,
          ),
          Builder(
            builder: (buttonContext) => SizedBox.square(
              dimension: kAppPlayerHeaderButtonSize,
              child: IconButton(
                tooltip: MaterialLocalizations.of(context).moreButtonTooltip,
                color: colorScheme.onSurface,
                iconSize: actionSize,
                icon: const Icon(CupertinoIcons.ellipsis),
                onPressed: () => onMoreActions(
                  buttonContext,
                  mediaItem,
                  appMenuAnchor(buttonContext),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
