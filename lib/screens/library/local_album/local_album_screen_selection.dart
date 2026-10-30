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
        Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Text(
            context.l10n.selectionReplayGainCount(selectedCount),
            style: Theme.of(context).textTheme.labelLarge,
          ),
        ),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final columns = (constraints.maxWidth / 320).floor().clamp(2, 4);
            final itemWidth =
                (constraints.maxWidth - spacing * (columns - 1)) / columns;
            final actions = <Widget>[];

            for (final remove in [false, true]) {
              actions.add(
                SelectionActionButton(
                  icon: remove ? Icons.remove_circle_outline : Icons.graphic_eq,
                  label: remove
                      ? context.l10n.selectionRemoveReplayGainCount(
                          selectedCount,
                        )
                      : context.l10n.selectionReplayGainCount(selectedCount),
                  onPressed: selectedCount > 0
                      ? () => runBatchReplayGain(
                          this.context,
                          _selectedUnifiedItems(tracks),
                          database: ref.read(libraryDatabaseProvider),
                          onExitSelectionMode: exitSelectionMode,
                          remove: remove,
                        )
                      : null,
                  colorScheme: colorScheme,
                ),
              );
            }

            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final action in actions)
                  SizedBox(width: itemWidth, child: action),
              ],
            );
          },
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
