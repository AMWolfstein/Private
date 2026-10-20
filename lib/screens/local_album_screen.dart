import 'package:spotiflac_android/widgets/error_card.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';
import 'dart:io';
import 'dart:math';
import 'package:spotiflac_android/widgets/track_detail_actions.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:spotiflac_android/services/deleted_library_files.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';
import 'package:spotiflac_android/utils/audio_quality_badge_policy.dart';
import 'package:spotiflac_android/utils/confirm_and_delete_tracks.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/image_cache_utils.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/batch_track_actions.dart';
import 'package:spotiflac_android/models/album_track_order.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/screens/collapsing_header_scroll_mixin.dart';
import 'package:spotiflac_android/screens/selection_mode_mixin.dart';
import 'package:spotiflac_android/widgets/local_song_menu.dart';
import 'package:spotiflac_android/widgets/collection_scaffold.dart';
import 'package:spotiflac_android/widgets/album_track_tile.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:spotiflac_android/widgets/destructive_selection_button.dart';
import 'package:spotiflac_android/widgets/selection_action_button.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/widgets/library_selection_playback_actions.dart';
import 'package:spotiflac_android/widgets/disc_separator_chip.dart';
import 'package:spotiflac_android/widgets/album_detail_header.dart';
import 'package:spotiflac_android/widgets/mornye_artist_header.dart';
import 'package:spotiflac_android/widgets/local_collection_actions.dart';
import 'package:spotiflac_android/widgets/local_library_artwork_builder.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';

class LocalAlbumScreen extends ConsumerStatefulWidget {
  final String albumName;
  final String artistName;
  final String? coverPath;
  final List<LocalLibraryItem> tracks;
  final Future<List<LocalLibraryItem>> Function()? loadTracks;

  const LocalAlbumScreen({
    super.key,
    required this.albumName,
    required this.artistName,
    this.coverPath,
    this.tracks = const [],
    this.loadTracks,
  });

  @override
  ConsumerState<LocalAlbumScreen> createState() => _LocalAlbumScreenState();
}

class _LocalAlbumScreenState extends ConsumerState<LocalAlbumScreen>
    with
        SelectionModeMixin<LocalAlbumScreen>,
        CollapsingHeaderScrollMixin<LocalAlbumScreen> {
  late AlbumTrackOrder<LocalLibraryItem> _trackOrder;
  List<LocalLibraryItem> get _sortedTracksCache => _trackOrder.tracks;
  Map<int, List<LocalLibraryItem>> get _discGroupsCache =>
      _trackOrder.discGroups;
  List<LocalLibraryItem>? _loadedTracks;
  bool _loadingTracks = false;
  Object? _loadError;
  int _loadGeneration = 0;

  void _showCueVirtualTrackSnackBar() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(cueVirtualTrackRequiresSplitMessage)),
    );
  }

  List<int> get _sortedDiscNumbersCache => _trackOrder.discNumbers;
  bool get _hasMultipleDiscsCache => _trackOrder.discGroups.length > 1;
  String? _commonQualityCache;

  @override
  void initState() {
    super.initState();
    _rebuildTrackCaches();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final loader = widget.loadTracks;
    if (loader == null) return;
    final generation = ++_loadGeneration;
    _loadingTracks = true;
    _loadError = null;
    try {
      final tracks = await loader();
      if (!mounted || generation != _loadGeneration) return;
      _loadedTracks = tracks;
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      _loadError = error;
    }
    _loadingTracks = false;
    setState(_rebuildTrackCaches);
  }

  @override
  void didUpdateWidget(covariant LocalAlbumScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.tracks, widget.tracks) ||
        oldWidget.tracks.length != widget.tracks.length ||
        oldWidget.loadTracks != widget.loadTracks) {
      _loadGeneration++;
      _loadedTracks = null;
      _loadingTracks = false;
      _loadError = null;
      _rebuildTrackCaches();
      _loadTracks();
    }
  }

  void _rebuildTrackCaches() {
    _trackOrder = AlbumTrackOrder(
      _loadedTracks ?? widget.tracks,
      discNumber: (track) => track.discNumber,
      trackNumber: (track) => track.trackNumber,
      trackName: (track) => track.trackName,
    );
    _commonQualityCache = _computeCommonQuality(_sortedTracksCache);
  }

  Future<void> _deleteSelected(List<LocalLibraryItem> currentTracks) async {
    final container = ProviderScope.containerOf(context, listen: false);
    final libraryNotifier = ref.read(localLibraryProvider.notifier);
    final tracksById = {for (final track in currentTracks) track.id: track};

    final deletedCount = await confirmAndDeleteTracks(
      context: context,
      ids: selectedIds.toList(),
      deleteItem: (id) async {
        final item = tracksById[id];
        if (item == null) return false;
        if (!isCueVirtualPath(item.filePath)) {
          final deleted = await deleteFile(item.filePath);
          if (!deleted) return false;
        }
        return true;
      },
      persistDeletedItems: (ids) async {
        final items = ids.map((id) => tracksById[id]!);
        await removeDeletedLibraryFileEntries(
          container,
          items
              .where((item) => !isCueVirtualPath(item.filePath))
              .map((item) => item.filePath),
        );
        await libraryNotifier.removeItems(
          items
              .where((item) => isCueVirtualPath(item.filePath))
              .map((item) => item.id),
        );
      },
      onExitSelectionMode: exitSelectionMode,
    );

    if (deletedCount == currentTracks.length && mounted) {
      Navigator.pop(context);
    }
  }

  Future<void> _openFile(LocalLibraryItem track) async {
    if (isCueVirtualPath(track.filePath)) {
      _showCueVirtualTrackSnackBar();
      return;
    }
    try {
      await ref
          .read(playbackProvider.notifier)
          .playLocalLibraryQueue(_sortedTracksCache, startItem: track);
    } catch (e) {
      if (mounted) showCannotOpenFileSnackBar(context, e);
    }
  }

  Future<void> _showTrackMenu(LocalLibraryItem track, Rect? anchor) async {
    if (!await showLocalSongMenu(context, ref, track, anchor: anchor) ||
        !mounted) {
      return;
    }
    final row = await LibraryDatabase.instance.getById(track.id);
    if (!mounted) return;
    setState(() {
      _loadedTracks = [
        for (final item in _sortedTracksCache)
          if (item.id != track.id)
            item
          else if (row != null)
            LocalLibraryItem.fromJson(row),
      ];
      _rebuildTrackCaches();
    });
  }

  bool _isCurrentTrack(MediaItem? item, LocalLibraryItem track) {
    if (item == null) return false;
    // Playlist playback can use the file path rather than the Library row ID.
    final source = item.extras?['source'];
    return source is String && source.isNotEmpty
        ? source == track.filePath
        : item.id == track.id || item.id == track.filePath;
  }

  @override
  Widget build(BuildContext context) {
    final albumCover = widget.coverPath?.trim();
    final artworkTrack =
        _sortedTracksCache
            .where(
              (track) => albumCover?.isNotEmpty == true
                  ? track.coverPath == albumCover
                  : track.coverPath?.isNotEmpty == true,
            )
            .firstOrNull ??
        _sortedTracksCache.firstOrNull;
    return LocalLibraryArtworkBuilder(
      coverPath: albumCover?.isNotEmpty == true
          ? albumCover
          : artworkTrack?.coverPath,
      filePath: artworkTrack?.filePath,
      builder: (context, coverPath) => context.isMornye
          ? MornyeArtistSurface(
              imageSource: coverPath,
              neutralActions: true,
              child: Builder(
                builder: (context) => _buildPage(context, coverPath),
              ),
            )
          : _buildPage(context, coverPath),
    );
  }

  Widget _buildPage(BuildContext context, String? coverPath) {
    final colorScheme = Theme.of(context).colorScheme;
    final bottomPadding = isSelectionMode
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;
    final tracks = _sortedTracksCache;

    pruneSelection(tracks.map((t) => t.id).toSet());

    if (tracks.isEmpty && !_loadingTracks && _loadError == null) {
      return Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: widget.albumName),
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text(context.l10n.noTracksFoundForAlbum)),
            ),
          ],
        ),
      );
    }

    return CollectionScaffold(
      scrollController: scrollController,
      isSelectionMode: isSelectionMode,
      onExitSelectionMode: exitSelectionMode,
      appBar: _buildAppBar(context, colorScheme, coverPath),
      slivers: [
        if (_loadError != null)
          SliverToBoxAdapter(
            child: ErrorCard(
              error: _loadError.toString(),
              colorScheme: colorScheme,
              onRetry: () => setState(() {
                _loadTracks();
              }),
            ),
          )
        else if (_loadingTracks)
          const SliverToBoxAdapter(
            child: RepaintBoundary(child: AlbumTrackListSkeleton(itemCount: 8)),
          )
        else
          _buildTrackList(context, colorScheme, tracks),
        if (!_loadingTracks && _loadError == null)
          buildTrackListFooter(
            context,
            colorScheme,
            tracks
                .map(
                  (track) =>
                      UnifiedLibraryItem.fromLocalLibrary(track).toTrack(),
                )
                .toList(),
          ),
      ],
      selectionBar: _buildSelectionBottomBar(
        context,
        colorScheme,
        tracks,
        bottomPadding,
      ),
    );
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    String? coverPath,
  ) {
    final expandedHeight = calculateExpandedHeight(context);
    final cacheWidth = coverCacheWidthForViewport(context);
    final Widget background = coverPath != null
        ? Image.file(
            File(coverPath),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            filterQuality: FilterQuality.low,
            errorBuilder: (_, _, _) => Container(color: colorScheme.surface),
          )
        : Container(
            color: colorScheme.surfaceContainerHighest,
            child: Icon(
              Icons.album,
              size: 80,
              color: colorScheme.onSurfaceVariant,
            ),
          );

    return AlbumDetailHeader(
      title: widget.albumName,
      appBarTitle: isSelectionMode
          ? context.l10n.selectionSelected(selectedIds.length)
          : null,
      leading: isSelectionMode
          ? HeaderCircleButton(
              icon: Icons.close,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: exitSelectionMode,
            )
          : null,
      immersive: context.isMornye,
      squareArtwork: true,
      expandedHeight: expandedHeight,
      showTitleInAppBar: showTitleInAppBar,
      background: background,
      paletteSource: coverPath,
      blurAndScrimBackground: coverPath != null,
      coverBuilder: (context, coverSize) => coverPath != null
          ? Image.file(
              File(coverPath),
              fit: BoxFit.cover,
              width: coverSize,
              height: coverSize,
              cacheWidth: cacheWidth,
              gaplessPlayback: true,
              errorBuilder: (_, _, _) => Container(
                color: colorScheme.surfaceContainerHighest,
                child: Icon(
                  Icons.album,
                  size: 48,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            )
          : Container(
              color: colorScheme.surfaceContainerHighest,
              child: Icon(
                Icons.album,
                size: 48,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
      subtitle: ClickableArtistName(
        artistName: widget.artistName,
        coverUrl: coverPath,
        style: TextStyle(
          color: context.isMornye
              ? colorScheme.primary
              : HeaderPalette.of(context).onSurfaceVariant,
          fontSize: context.tokens.headerSubtitleSize,
          fontWeight: context.isMornye ? FontWeight.w400 : FontWeight.w600,
        ),
        textAlign: TextAlign.center,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      meta: _buildLocalHeaderMeta(context),
      actions: isSelectionMode
          ? null
          : Consumer(
              builder: (context, ref, _) {
                final isCurrent = ref.watch(
                  currentMediaItemProvider.select(
                    (state) => _sortedTracksCache.any(
                      (track) => _isCurrentTrack(state.value, track),
                    ),
                  ),
                );
                final isPlaying =
                    isCurrent && ref.watch(playbackPlayingProvider);
                final tracksForActions = _sortedTracksCache
                    .map(
                      (track) =>
                          UnifiedLibraryItem.fromLocalLibrary(track).toTrack(),
                    )
                    .toList();
                return LocalCollectionActions(
                  tracks: tracksForActions,
                  isPlaying: isPlaying,
                  onPlay: isCurrent
                      ? () => ref
                            .read(musicPlayerControllerProvider)
                            .togglePlayPause(isPlaying)
                      : _playAll,
                  onShuffle: _shuffleAll,
                );
              },
            ),
    );
  }

  Widget _buildLocalHeaderMeta(BuildContext context) {
    final tracks = _sortedTracksCache;
    final totalSeconds = tracks.fold<int>(
      0,
      (sum, t) => sum + ((t.duration ?? 0) > 0 ? t.duration! : 0),
    );
    final totalMinutes = (totalSeconds / 60).round();
    final quality = _commonQualityCache;

    return HeaderMetaRow(
      items: [
        if (tracks.firstOrNull?.releaseDate?.isNotEmpty == true)
          HeaderMetaItem(tracks.first.releaseDate!.split('-').first),
        HeaderMetaItem(context.l10n.queueTrackCount(tracks.length)),
        if (totalMinutes > 0) HeaderMetaItem('$totalMinutes min'),
        if (quality != null && quality.isNotEmpty)
          HeaderMetaItem(quality, icon: Icons.graphic_eq),
      ],
    );
  }

  Future<void> _playAll() async {
    final tracks = _sortedTracksCache;
    if (tracks.isEmpty) return;
    await ref.read(musicPlayerControllerProvider).setShuffle(false);
    await _openFile(tracks.first);
  }

  Future<void> _shuffleAll() async {
    final tracks = _sortedTracksCache
        .where((t) => !isCueVirtualPath(t.filePath))
        .toList();
    if (tracks.isEmpty) return;
    await ref.read(musicPlayerControllerProvider).setShuffle(true);
    await _openFile(tracks[Random().nextInt(tracks.length)]);
  }

  String? _computeCommonQuality(List<LocalLibraryItem> tracks) {
    if (tracks.isEmpty) return null;
    String? label(LocalLibraryItem track) => buildLibraryAudioQualityLabel(
      format: track.format,
      filePath: track.filePath,
      bitrateKbps: track.bitrate,
    );

    final firstQuality = label(tracks.first);
    if (firstQuality == null) return null;
    for (final track in tracks) {
      if (label(track) != firstQuality) return null;
    }
    return firstQuality;
  }

  Widget _buildTrackList(
    BuildContext context,
    ColorScheme colorScheme,
    List<LocalLibraryItem> tracks,
  ) {
    final discGroups = _discGroupsCache;
    final hasMultipleDiscs = _hasMultipleDiscsCache;

    final slivers = <Widget>[];

    for (final discNumber in _sortedDiscNumbersCache) {
      final discTracks = discGroups[discNumber]!;

      if (hasMultipleDiscs) {
        slivers.add(
          SliverToBoxAdapter(child: DiscSeparatorChip(discNumber: discNumber)),
        );
      }

      slivers.add(
        SliverList(
          delegate: SliverChildBuilderDelegate((context, index) {
            final track = discTracks[index];
            return KeyedSubtree(
              key: ValueKey(track.id),
              child: StaggeredListItem(
                index: index,
                animate: widget.loadTracks == null,
                child: _buildTrackItem(context, colorScheme, track),
              ),
            );
          }, childCount: discTracks.length),
        ),
      );
    }

    return SliverPadding(
      padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
      sliver: SliverMainAxisGroup(slivers: slivers),
    );
  }

  Widget _buildTrackItem(
    BuildContext context,
    ColorScheme colorScheme,
    LocalLibraryItem track,
  ) {
    return Consumer(
      builder: (context, ref, _) {
        final isCurrent = ref.watch(
          currentMediaItemProvider.select(
            (state) => _isCurrentTrack(state.value, track),
          ),
        );
        final isPlaying = isCurrent && ref.watch(playbackPlayingProvider);
        return AlbumTrackTile(
          isPlaying: isPlaying,
          trackNumber: track.trackNumber,
          trackName: track.trackName,
          explicit: track.explicit,
          subtitle: Text(
            track.artistName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: colorScheme.onSurfaceVariant),
          ),
          isSelectionMode: isSelectionMode,
          isSelected: selectedIds.contains(track.id),
          colorScheme: colorScheme,
          onToggleSelection: () => toggleSelection(track.id),
          onMenu: (anchor) => _showTrackMenu(track, anchor),
          onEnterSelectionMode: () => enterSelectionMode(track.id),
          onPlay: isCurrent
              ? () => ref
                    .read(musicPlayerControllerProvider)
                    .togglePlayPause(isPlaying)
              : () => _openFile(track),
        );
      },
    );
  }

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
          child: Text(context.l10n.trackEditMetadata),
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
