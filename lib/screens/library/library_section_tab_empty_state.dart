part of 'library_section_tab.dart';

extension _LibrarySectionTabEmptyState on _LibrarySectionTabState {
  Widget _buildEmptyState(
    BuildContext context,
    ColorScheme colorScheme,
    String filterMode,
  ) {
    String message;
    String subtitle;
    IconData icon;

    switch (filterMode) {
      case 'albums':
        message = context.l10n.queueEmptyAlbums;
        subtitle = context.l10n.queueEmptyAlbumsSubtitle;
        icon = Icons.album;
        break;
      case 'singles':
        message = context.l10n.queueEmptySingles;
        subtitle = context.l10n.queueEmptySinglesSubtitle;
        icon = Icons.music_note;
        break;
      case 'playlists':
        message = context.l10n.collectionNoPlaylistsYet;
        subtitle = context.l10n.queueEmptyPlaylistsSubtitle;
        icon = Icons.queue_music;
        break;
      default:
        message = context.l10n.libraryEmpty;
        subtitle = context.l10n.libraryEmptySubtitle;
        icon = Icons.history;
    }

    return EmptyState(
      icon: icon,
      title: message,
      message: subtitle,
      // Playlists start empty on a fresh install, so their empty state has to
      // offer creation instead of sending the user to another section.
      action: filterMode == 'playlists'
          ? FilledButton.icon(
              onPressed: () => _showCreatePlaylistDialog(context),
              icon: const Icon(Icons.add),
              label: Text(context.l10n.collectionCreatePlaylist),
            )
          // Every other empty branch means the library has nothing of this kind
          // yet, so the way forward is always search.
          : FilledButton.icon(
              onPressed: () => ShellNavigationService.requestTab(ShellTab.home),
              icon: const Icon(Icons.search),
              label: Text(context.l10n.navHome),
            ),
    );
  }
}
