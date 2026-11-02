part of 'local_album_screen.dart';

extension _LocalAlbumSelection on _LocalAlbumScreenState {
  List<UnifiedLibraryItem> _selectedUnifiedItems(
    List<LocalLibraryItem> tracks,
  ) {
    final tracksById = {for (final t in tracks) t.id: t};
    return [
      for (final t in selectedIds.map((id) => tracksById[id]))
        if (t != null) UnifiedLibraryItem.fromLocalLibrary(t),
    ];
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<LocalLibraryItem> tracks,
    double bottomPadding,
  ) {
    final selectedCount = selectedIds.length;
    final allSelected = selectedCount == tracks.length && tracks.isNotEmpty;

    return SelectionBottomBar(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: exitSelectionMode,
      onToggleSelectAll: () {
        if (allSelected) {
          exitSelectionMode();
        } else {
          selectAll(tracks.map((e) => e.id));
        }
      },
      bottomPadding: bottomPadding,
      children: [
        LibrarySelectionPlaybackActions(
          items: _selectedUnifiedItems(tracks),
          onClose: exitSelectionMode,
        ),
        const SizedBox(height: 8),
        DestructiveSelectionButton(
          count: selectedCount,
          colorScheme: colorScheme,
          onPressed: () => _deleteSelected(tracks),
        ),
      ],
    );
  }
}
