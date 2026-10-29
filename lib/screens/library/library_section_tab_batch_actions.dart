part of 'library_section_tab.dart';

extension _LibrarySectionTabBatchActions on _LibrarySectionTabState {
  Future<void> _runBatchReplayGain(
    List<UnifiedLibraryItem> allItems, {
    bool remove = false,
  }) {
    return runBatchReplayGain(
      context,
      _selectedItemsFromAll(allItems),
      onExitSelectionMode: _exitSelectionMode,
      remove: remove,
      onConfirmOpen: () {
        _suppressSelectionOverlay = true;
        _hideSelectionOverlay();
        _hidePlaylistSelectionOverlay();
      },
      onConfirmClosed: (confirmed) async {
        if (!mounted) {
          _suppressSelectionOverlay = false;
          return;
        }
        if (confirmed) {
          _suppressSelectionOverlay = false;
          return;
        }
        // Restore after the dialog's exit animation.
        await Future<void>.delayed(const Duration(milliseconds: 220));
        if (!mounted) return;
        // A library refresh may have settled while the dialog hid the bar.
        // Rebuild from the current query rather than restore captured rows.
        _setState(() => _suppressSelectionOverlay = false);
      },
    );
  }
}
