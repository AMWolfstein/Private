part of 'home_tab.dart';

/// Apple Music's editorial cards and horizontal shelves, backed entirely by
/// local tags, embedded artwork and saved collections.
extension _LocalHomeFeedUI on _HomeTabState {
  List<Widget> _buildLocalFeed(ColorScheme colors) {
    final newest = libraryBrowseProvider(
      localHomeBrowseRequest(sort: 'release-date-newest'),
    );
    final albums = libraryBrowseProvider(
      localHomeBrowseRequest(releaseKind: LibraryReleaseKind.albums),
    );
    final singles = libraryBrowseProvider(
      localHomeBrowseRequest(releaseKind: LibraryReleaseKind.singles),
    );
    final artists = libraryBrowseProvider(
      localHomeBrowseRequest(artists: true, sort: 'a-z'),
    );
    final playlistsList = ref.watch(
      libraryCollectionsProvider.select((state) => state.playlists),
    );
    // PERF-603: select the playlists list and reuse its sorted copy, so a
    // Loved toggle or unrelated collection edit does not rebuild all of Home.
    if (!identical(playlistsList, _sortedPlaylistsSource)) {
      _sortedPlaylistsSource = playlistsList;
      _sortedPlaylists = playlistsList.toList()
        ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    final playlists = _sortedPlaylists!;

    final albumData = ref.watch(albums);
    final artistData = ref.watch(artists);
    final newestData = ref.watch(newest);
    final tracks = ref.watch(localHomeTracksProvider);
    final empty =
        ref.watch(libraryCollectionsProvider.select((s) => s.isLoaded)) &&
        [
          albumData,
          ref.watch(singles),
          artistData,
          newestData,
        ].every((p) => p.hasValue && !p.hasError && p.value!.entries.isEmpty) &&
        tracks.hasValue &&
        !tracks.hasError &&
        tracks.value!.isEmpty &&
        playlists.isEmpty;
    if (empty) {
      final scanning = ref.watch(
        localLibraryProvider.select((s) => s.isLoading || s.isScanning),
      );
      return [
        SliverToBoxAdapter(child: scanning ? _feedSkeleton() : _feedEmpty()),
      ];
    }
    return [
      SliverToBoxAdapter(
        child: ref
            .watch(newest)
            .when(
              skipLoadingOnReload: true,
              data: (page) => page.entries.isEmpty
                  ? const SizedBox.shrink()
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
              loading: _feedSkeleton,
              error: (_, _) => _feedRetry(() => ref.invalidate(newest)),
            ),
      ),
      _buildRecentlyAdded(colors),
      SliverToBoxAdapter(
        child: ref
            .watch(localLibraryMixesProvider)
            .when(
              skipLoadingOnReload: true,
              data: (mixes) => _feedShelf(
                context.l10n.homeLocalMixes,
                mixes
                    .map(
                      (mix) => _feedCard(
                        cardKey: ValueKey('home-mix-${mix.id}'),
                        semanticType: context.l10n.homeLocalMixes,
                        name: switch (mix.kind) {
                          LocalMixKind.daily => context.l10n.homeDailyMix,
                          LocalMixKind.favorites =>
                            context.l10n.homeFavoritesMix,
                          LocalMixKind.fresh => context.l10n.homeFreshMix,
                          _ => context.l10n.homeNamedMix(mix.label),
                        },
                        subtitle: context.l10n.homeMixTrackCount(
                          mix.tracks.length,
                        ),
                        cover: mix.tracks.first.coverPath,
                        samplePath: mix.tracks.first.filePath,
                        icon: Icons.auto_awesome,
                        colors: colors,
                        onTap: () => ref
                            .read(playbackProvider.notifier)
                            .playLocalLibraryQueue(
                              mix.tracks,
                              startItem: mix.tracks.first,
                            ),
                      ),
                    )
                    .toList(),
              ),
              loading: () => const SizedBox.shrink(),
              error: (_, _) =>
                  _feedRetry(() => ref.invalidate(localLibraryMixesProvider)),
            ),
      ),
      SliverToBoxAdapter(
        child: ref
            .watch(albums)
            .when(
              skipLoadingOnReload: true,
              data: (page) => _feedShelf(
                context.l10n.searchAlbums,
                page.entries
                    .map((entry) => _feedRelease(entry, colors))
                    .toList(),
              ),
              loading: _feedSkeleton,
              error: (_, _) => _feedRetry(() => ref.invalidate(albums)),
            ),
      ),
      SliverToBoxAdapter(
        child: ref
            .watch(singles)
            .when(
              skipLoadingOnReload: true,
              data: (page) => _feedShelf(
                context.l10n.libraryKindSingles,
                page.entries
                    .map((entry) => _feedRelease(entry, colors))
                    .toList(),
              ),
              loading: _feedSkeleton,
              error: (_, _) => _feedRetry(() => ref.invalidate(singles)),
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
                    cardKey: ValueKey('home-playlist-${playlist.id}'),
                    semanticType: context.l10n.searchPlaylists,
                    name: playlist.name,
                    subtitle: context.l10n.searchPlaylists,
                    cover: playlist.coverImagePath ?? playlist.previewCover,
                    icon: Icons.playlist_play,
                    colors: colors,
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => LibraryCollectionTracksScreen(
                          mode: LibraryCollectionMode.playlist,
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
              skipLoadingOnReload: true,
              data: (page) => _feedShelf(
                context.l10n.searchArtists,
                page.entries
                    .map(
                      (entry) => _feedCard(
                        cardKey: ValueKey('home-artist-${entry.key}'),
                        semanticType: context.l10n.searchArtists,
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
              loading: _feedSkeleton,
              error: (_, _) => _feedRetry(() => ref.invalidate(artists)),
            ),
      ),
    ];
  }

  Future<void> _refreshHome() async {
    final requests = [
      localHomeBrowseRequest(sort: 'release-date-newest'),
      localHomeBrowseRequest(releaseKind: LibraryReleaseKind.albums),
      localHomeBrowseRequest(releaseKind: LibraryReleaseKind.singles),
      localHomeBrowseRequest(artists: true, sort: 'a-z'),
    ];
    for (final request in requests) {
      ref.invalidate(libraryBrowseProvider(request));
    }
    ref.invalidate(localHomeTracksProvider);
    ref.invalidate(localLibraryMixesProvider);
    // Errors stay in their respective shelf's retry card.
    await Future.wait<void>([
      for (final request in requests)
        ref
            .read(libraryBrowseProvider(request).future)
            .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
      ref
          .read(localHomeTracksProvider.future)
          .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    ]);
  }

  Widget _feedEmpty() {
    final hasFolder = ref.watch(
      localLibraryProvider.select((s) => s.sources.isNotEmpty),
    );
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          const Icon(Icons.library_music_outlined, size: 56),
          const SizedBox(height: 16),
          Text(
            context.l10n.libraryEmptyCollection,
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            !hasFolder
                ? context.l10n.homeChooseLibraryFolder
                : context.l10n.homeLibraryEmpty,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const LibrarySettingsPage(),
              ),
            ),
            child: Text(context.l10n.settingsLocalLibrary),
          ),
        ],
      ),
    );
  }

  Widget _feedSkeleton() => ExcludeSemantics(
    child: ShimmerLoading(
      child: Padding(
        padding: EdgeInsets.all(16 + wideListInset(context)),
        child: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SkeletonBox(width: 160, height: 22),
            SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: SkeletonBox(width: double.infinity, height: 140),
                ),
                SizedBox(width: 12),
                Expanded(
                  child: SkeletonBox(width: double.infinity, height: 140),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  Widget _feedRetry(VoidCallback retry) => Padding(
    padding: const EdgeInsets.all(16),
    child: ErrorCard(
      error: context.l10n.libraryLoadFailed,
      colorScheme: Theme.of(context).colorScheme,
      onRetry: retry,
    ),
  );

  Widget _feedRelease(
    LibraryBrowseEntry entry,
    ColorScheme colors, {
    bool featured = false,
  }) => _feedCard(
    cardKey: ValueKey('home-release-${entry.key}-$featured'),
    semanticType: context.l10n.searchAlbums,
    name: entry.name,
    subtitle: entry.artist,
    heading: featured
        ? formatReleaseTag(
            entry.releaseDate,
            Localizations.localeOf(context).toString(),
          )
        : null,
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
              (await ref
                      .read(libraryDatabaseProvider)
                      .getBrowseLocalAlbumRowsByKey(entry.key))
                  .map(LocalLibraryItem.fromJson)
                  .toList(),
        ),
      ),
    ),
  );

  double _feedCardWidth(bool featured) {
    final width = MediaQuery.sizeOf(context).width;
    if (featured) {
      return ((width - 2 * wideListInset(context)) * .64).clamp(160.0, 360.0);
    }
    final textScale = MediaQuery.textScalerOf(context).scale(16) / 16;
    return 145 *
        (width / 400).clamp(.82, 1.32) *
        (1 + (textScale - 1).clamp(0, 2) * .14);
  }

  double _featuredCardHeight(double width) {
    final scale = MediaQuery.textScalerOf(context);
    return math.max(
      width / .75,
      scale.scale(13) * 1.5 +
          scale.scale(18) * 1.3 * 2 +
          scale.scale(14) * 1.4 * 2 +
          64,
    );
  }

  Widget _feedShelf(String title, List<Widget> cards, {bool featured = false}) {
    if (cards.isEmpty) return const SizedBox.shrink();
    final width = _feedCardWidth(featured);
    final scale = MediaQuery.textScalerOf(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            16 + wideListInset(context),
            20,
            16 + wideListInset(context),
            12,
          ),
          child: Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: featured
              ? _featuredCardHeight(width)
              : width + scale.scale(16) * 1.7 + scale.scale(14) * 1.7 + 20,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: 16 + wideListInset(context),
            ),
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
    bool explicit = false,
    String? semanticType,
    String? cover,
    String? samplePath,
    String? heading,
    bool featured = false,
    bool round = false,
  }) {
    final width = _feedCardWidth(featured);
    final artwork = _LocalFeedCover(
      filePath: samplePath,
      coverPath: cover,
      width: width,
      height: featured ? _featuredCardHeight(width) : width,
      borderRadius: BorderRadius.circular(round ? width / 2 : 10),
      fallbackIcon: icon,
      fallbackIconSize: width * 0.3,
      colorScheme: colors,
    );
    final title = ExplicitTrackTitle(
      title: name,
      explicit: explicit,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          (featured
                  ? Theme.of(context).textTheme.titleLarge
                  : Theme.of(context).textTheme.bodyMedium)
              ?.copyWith(fontWeight: FontWeight.w600, height: 1.5),
    );
    final artist = Text(
      subtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style:
          (featured
                  ? Theme.of(context).textTheme.bodyLarge
                  : Theme.of(context).textTheme.bodySmall)
              ?.copyWith(height: 1.5, color: colors.onSurfaceVariant),
    );
    return Semantics(
      key: cardKey,
      button: true,
      label: {
        semanticType,
        name,
        if (subtitle.isNotEmpty) subtitle,
        if (explicit) context.l10n.metadataExplicitValue,
      }.whereType<String>().join(', '),
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: SizedBox(
          width: width,
          child: Column(
            crossAxisAlignment: round
                ? CrossAxisAlignment.center
                : CrossAxisAlignment.start,
            children: [
              if (featured) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: _featuredCardHeight(width),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        artwork,
                        const DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              stops: [0, .4, 1],
                              colors: [
                                Colors.transparent,
                                Color(0x10000000),
                                Color(0xE6000000),
                              ],
                            ),
                          ),
                        ),
                        PositionedDirectional(
                          start: 16,
                          end: 16,
                          bottom: 18,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (heading?.isNotEmpty ?? false)
                                Text(
                                  heading!,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.5,
                                    color: Color(0xE6FFFFFF),
                                  ),
                                ),
                              Text(
                                name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 18,
                                  height: 1.3,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                              if (subtitle.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  subtitle,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    height: 1.4,
                                    color: Color(0xE6FFFFFF),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                artwork,
                const SizedBox(height: 8),
                title,
                if (subtitle.isNotEmpty) artist,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
