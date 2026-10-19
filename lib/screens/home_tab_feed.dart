part of 'home_tab.dart';

/// Apple Music's editorial cards and horizontal shelves, backed entirely by
/// local tags, embedded artwork and saved collections.
extension _LocalHomeFeedUI on _HomeTabState {
  List<Widget> _buildLocalFeed(ColorScheme colors) {
    final newest = libraryBrowseProvider(
      localHomeBrowseRequest(sort: 'release-date-newest'),
    );
    final albums = libraryBrowseProvider(localHomeBrowseRequest());
    final artists = libraryBrowseProvider(
      localHomeBrowseRequest(artists: true, sort: 'a-z'),
    );
    final playlists = ref.watch(libraryCollectionsProvider).playlists.toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));

    return [
      SliverToBoxAdapter(
        child: ref
            .watch(newest)
            .when(
              data: (page) => page.entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        context.l10n.libraryEmptyCollection,
                        textAlign: TextAlign.center,
                      ),
                    )
                  : _feedShelf(
                      context.l10n.homeLatestReleases,
                      page.entries
                          .map(
                            (entry) =>
                                _feedRelease(entry, colors, featured: true),
                          )
                          .toList(),
                      featured: true,
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => _feedRetry(() => ref.invalidate(newest)),
            ),
      ),
      _buildRecentlyAdded(colors),
      SliverToBoxAdapter(
        child: ref
            .watch(albums)
            .when(
              data: (page) => _feedShelf(
                context.l10n.searchAlbums,
                page.entries
                    .map((entry) => _feedRelease(entry, colors))
                    .toList(),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => _feedRetry(() => ref.invalidate(albums)),
            ),
      ),
      if (playlists.isNotEmpty)
        SliverToBoxAdapter(
          child: _feedShelf(
            context.l10n.searchPlaylists,
            playlists
                .take(localHomeShelfLimit)
                .map(
                  (playlist) => _feedCard(
                    name: playlist.name,
                    subtitle: context.l10n.searchPlaylists,
                    cover: playlist.coverImagePath ?? playlist.previewCover,
                    icon: Icons.playlist_play,
                    colors: colors,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LibraryTracksFolderScreen(
                          mode: LibraryTracksFolderMode.playlist,
                          playlistId: playlist.id,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      SliverToBoxAdapter(
        child: ref
            .watch(artists)
            .when(
              data: (page) => _feedShelf(
                context.l10n.searchArtists,
                page.entries
                    .map(
                      (entry) => _feedCard(
                        cardKey: ValueKey('home-artist-${entry.key}'),
                        name: entry.name,
                        subtitle: '',
                        cover: entry.cover,
                        samplePath: entry.samplePath,
                        icon: Icons.person,
                        colors: colors,
                        round: true,
                        onTap: () => _openArtist(entry.name),
                      ),
                    )
                    .toList(),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) => _feedRetry(() => ref.invalidate(artists)),
            ),
      ),
    ];
  }

  Widget _feedRetry(VoidCallback retry) => Padding(
    padding: const EdgeInsets.all(16),
    child: Column(
      children: [
        Text(context.l10n.libraryLoadFailed),
        TextButton(onPressed: retry, child: Text(context.l10n.dialogRetry)),
      ],
    ),
  );

  Widget _feedRelease(
    LibraryBrowseEntry entry,
    ColorScheme colors, {
    bool featured = false,
  }) => _feedCard(
    name: entry.name,
    subtitle: entry.artist,
    heading: featured ? entry.releaseDate ?? context.l10n.searchAlbums : null,
    cover: entry.cover,
    samplePath: entry.samplePath,
    icon: Icons.album_outlined,
    colors: colors,
    featured: featured,
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => LocalAlbumScreen(
          albumName: entry.name,
          artistName: entry.artist,
          coverPath: entry.cover,
          loadTracks: () async =>
              (await LibraryDatabase.instance.getQueueLocalAlbumTracksByKey(
                entry.key,
              )).map(LocalLibraryItem.fromJson).toList(),
        ),
      ),
    ),
  );

  double _feedCardWidth(bool featured) => featured
      ? (MediaQuery.sizeOf(context).width - 48).clamp(160.0, 560.0)
      : MediaQuery.sizeOf(context).shortestSide >= 600
      ? 180
      : 156;

  Widget _feedShelf(String title, List<Widget> cards, {bool featured = false}) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final width = _feedCardWidth(featured);
    final scale = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: featured
              ? width / 1.5 +
                    scale.scale(12) * 1.5 +
                    scale.scale(22) * 1.4 +
                    scale.scale(16) * 1.5 +
                    20
              : width + scale.scale(16) * 1.5 + scale.scale(14) * 1.5 + 20,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: cards.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, index) => cards[index],
          ),
        ),
      ],
    );
  }

  Widget _feedCard({
    required String name,
    required String subtitle,
    required ColorScheme colors,
    required IconData icon,
    required VoidCallback onTap,
    Key? cardKey,
    String? cover,
    String? samplePath,
    String? heading,
    bool featured = false,
    bool round = false,
  }) {
    final width = _feedCardWidth(featured);
    final artwork = _DownloadedOrRemoteCover(
      downloadedFilePath: samplePath,
      imageUrl: cover,
      width: width,
      height: featured ? width / 1.5 : width,
      borderRadius: BorderRadius.circular(round ? width / 2 : 12),
      fallbackIcon: icon,
      fallbackIconSize: width * 0.3,
      colorScheme: colors,
    );
    final title = Text(
      name,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: featured ? 22 : 16,
        height: featured ? 1.4 : 1.5,
      ),
    );
    final artist = Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: featured ? 16 : 14,
        height: 1.5,
        color: colors.onSurfaceVariant,
      ),
    );
    return Semantics(
      key: cardKey,
      button: true,
      label: name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: round
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (featured) ...[
                Text(
                  heading ?? '',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    fontWeight: FontWeight.w600,
                    color: colors.primary,
                  ),
                ),
                title,
                artist,
                const SizedBox(height: 8),
                artwork,
              ] else ...[
                artwork,
                const SizedBox(height: 8),
                title,
                artist,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
