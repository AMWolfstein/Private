part of 'library_section_tab.dart';

extension _LibrarySectionTabAlbumGrid on _LibrarySectionTabState {
  Widget _buildLocalAlbumGridItem(
    BuildContext context,
    _GroupedLocalAlbum album,
    ColorScheme colorScheme,
  ) {
    return LocalLibraryArtworkBuilder(
      coverPath: album.coverPath,
      filePath: album.sampleFilePath,
      builder: (context, coverPath) => _buildAlbumGridItemCore(
        context: context,
        albumName: album.albumName,
        artistName: album.artistName,
        trackCount: album.displayTrackCount,
        completeness: album.completeness,
        colorScheme: colorScheme,
        coverWidget: coverPath != null
            ? Image.file(
                File(coverPath),
                fit: BoxFit.cover,
                width: double.infinity,
                height: double.infinity,
                cacheWidth: 300,
                cacheHeight: 300,
                errorBuilder: (context, error, stackTrace) =>
                    _albumPlaceholder(colorScheme),
              )
            : null,
        badgeColor: colorScheme.tertiaryContainer,
        badgeTextColor: colorScheme.onTertiaryContainer,
        badgeIcon: Icons.folder,
        onTap: () => _navigateToLocalAlbum(album),
      ),
    );
  }

  Widget _albumPlaceholder(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(Icons.album, color: colorScheme.onSurfaceVariant, size: 48),
      ),
    );
  }

  Widget _buildAlbumGridItemCore({
    required BuildContext context,
    required String albumName,
    required String artistName,
    required int trackCount,
    required ColorScheme colorScheme,
    required Widget? coverWidget,
    required Color badgeColor,
    required Color badgeTextColor,
    required IconData badgeIcon,
    required VoidCallback onTap,
    String? coverUrl,
    AlbumCompleteness? completeness,
  }) {
    final completenessLabel = completeness == null
        ? null
        : completeness.status == 'unknown'
        ? context.l10n.libraryAlbumCompletenessUnknown
        : completeness.expected == null
        ? context.l10n.libraryFilterIncompleteAlbums
        : context.l10n.libraryAlbumMissingTracks(
            completeness.present,
            completeness.expected!,
            completeness.expected! - completeness.present,
          );
    return Semantics(
      button: true,
      label: [
        context.l10n.a11yOpenAlbumByArtistTrackCount(
          albumName,
          artistName,
          trackCount,
        ),
        ?completenessLabel,
      ].join('. '),
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: coverWidget ?? _albumPlaceholder(colorScheme),
                  ),
                  PositionedDirectional(
                    end: 8,
                    bottom: 8,
                    child: Tooltip(
                      message:
                          completenessLabel ??
                          context.l10n.tracksCount(trackCount),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: badgeColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(badgeIcon, size: 12, color: badgeTextColor),
                            const SizedBox(width: 4),
                            Text(
                              completeness?.badge ?? '$trackCount',
                              style: TextStyle(
                                color: badgeTextColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              albumName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
            ),
            ClickableArtistName(
              artistName: artistName,
              coverUrl: coverUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
