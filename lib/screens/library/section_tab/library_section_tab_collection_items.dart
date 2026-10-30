part of 'library_section_tab.dart';

extension _LibrarySectionTabCollectionItemWidgets on _LibrarySectionTabState {
  /// Dedicated Library sections use rows, so Playlists lists its cover, name
  /// and track count in a list tile instead of an album-style grid card.
  Widget _buildPlaylistCollectionRow({
    required BuildContext context,
    required ColorScheme colorScheme,
    required int playlistIndex,
    required LibraryCollectionsState collectionState,
    required List<UnifiedLibraryItem> filteredUnifiedItems,
  }) {
    final playlist = collectionState.playlists[playlistIndex];
    final isSelected = _selectedPlaylistIds.contains(playlist.id);
    return DragTarget<UnifiedLibraryItem>(
      onWillAcceptWithDetails: (_) => !_isPlaylistSelectionMode,
      onAcceptWithDetails: (details) {
        _onTrackDroppedOnPlaylist(
          context,
          details.data,
          playlist.id,
          playlist.name,
          allItems: filteredUnifiedItems,
        );
      },
      builder: (context, candidateData, rejectedData) {
        final isHovering = candidateData.isNotEmpty;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          child: Material(
            color: isHovering
                ? colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Semantics(
              // Selection mode changes what a tap does: report the state so
              // TalkBack does not just announce a plain "open playlist" row.
              selected: _isPlaylistSelectionMode ? isSelected : null,
              child: ListTile(
                key: ValueKey('plrow_${playlist.id}'),
                contentPadding: const EdgeInsetsDirectional.fromSTEB(
                  8,
                  4,
                  12,
                  4,
                ),
                leading: SizedBox.square(
                  dimension: 56,
                  child: _buildPlaylistCover(
                    context,
                    playlist,
                    colorScheme,
                    56,
                  ),
                ),
                title: Text(
                  playlist.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  context.l10n.collectionPlaylistTracks(playlist.trackCount),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: _isPlaylistSelectionMode
                    ? Semantics(
                        checked: isSelected,
                        label: isSelected
                            ? context.l10n.a11yDeselectPlaylist
                            : context.l10n.a11ySelectPlaylist,
                        child: AnimatedSelectionCheckbox(
                          visible: true,
                          selected: isSelected,
                          colorScheme: colorScheme,
                          size: 24,
                        ),
                      )
                    : const Icon(Icons.chevron_right),
                onTap: _isPlaylistSelectionMode
                    ? () => _togglePlaylistSelection(playlist.id)
                    : () => _openPlaylistById(playlist.id),
                onLongPress: _isPlaylistSelectionMode
                    ? () => _togglePlaylistSelection(playlist.id)
                    : () => _enterPlaylistSelectionMode(playlist.id),
              ),
            ),
          ),
        );
      },
    );
  }
}
