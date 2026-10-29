import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/utils/release_date_display.dart';
import 'package:sistrum/widgets/status/error_card.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'dart:io';
import 'dart:math';
import 'package:sistrum/widgets/sheets/track_detail_actions.dart';
import 'package:audio_service/audio_service.dart' show MediaItem;
import 'package:sistrum/services/library/deleted_library_files.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/utils/audio_quality_badge_policy.dart';
import 'package:sistrum/widgets/selection/confirm_and_delete_tracks.dart';
import 'package:sistrum/utils/file_access.dart';
import 'package:sistrum/utils/image_cache_utils.dart';
import 'package:sistrum/widgets/library/batch_track_actions.dart';
import 'package:sistrum/models/unified_library_item.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/screens/library/collapsing_header_scroll_mixin.dart';
import 'package:sistrum/screens/library/selection_mode_mixin.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/collection_scaffold.dart';
import 'package:sistrum/widgets/library/album_track_tile.dart';
import 'package:sistrum/widgets/animation_utils.dart';
import 'package:sistrum/widgets/animation_skeletons.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/selection/selection_action_button.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/widgets/library/library_selection_playback_actions.dart';
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/header/album_ken_burns.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/widgets/library/local_collection_actions.dart';
import 'package:sistrum/widgets/library/local_library_artwork_builder.dart';
import 'package:sistrum/navigation/detail_navigation.dart';
import 'package:sistrum/utils/detail_page_route.dart';
import 'package:sistrum/widgets/header/header_controls.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/library_database_provider.dart';
import 'dart:collection';
import 'package:sistrum/widgets/primitives/app_action_button.dart';

part 'local_album_screen_header.dart';
part 'local_album_screen_track_list.dart';
part 'local_album_screen_selection.dart';

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

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Go to Album from this page's own songs keeps the page instead of
    // stacking a copy.
    DetailPage.mark(
      context,
      DetailPage.album(widget.albumName, artistName: widget.artistName),
    );
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
    final tracksById = {for (final track in currentTracks) track.id: track};
    final deletedIds = <String>{};

    final result = await confirmAndDeleteTracks(
      context: context,
      ids: selectedIds.toList(),
      deleteItems: (ids) async {
        final deleted = await deleteLocalLibraryTracks(
          container.read(localLibraryProvider.notifier),
          [for (final id in ids) ?tracksById[id]],
        );
        deletedIds.addAll(deleted.deletedIds);
        return deleted;
      },
      onExitSelectionMode: exitSelectionMode,
    );

    if (result == null || result.deletedCount == 0 || !mounted) return;

    final remaining = [
      for (final item in _loadedTracks ?? widget.tracks)
        if (!deletedIds.contains(item.id)) item,
    ];
    if (remaining.isEmpty) {
      Navigator.pop(context);
      return;
    }
    // The caller passes a static track list and this page does not watch the
    // library, so drop the deleted rows ourselves or they would stay on screen
    // with a stale footer until the page is reopened.
    setState(() {
      _loadedTracks = remaining;
      _rebuildTrackCaches();
    });
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
    final row = await ref.read(libraryDatabaseProvider).getById(track.id);
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
      builder: (context, coverPath) => AppArtistSurface(
        imageSource: coverPath,
        neutralActions: true,
        child: Builder(builder: (context) => _buildPage(context, coverPath)),
      ),
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
}

/// Album order shared by playback, metadata navigation, and disc sections.
/// Missing disc tags belong to disc 1; missing track tags use 999.
class AlbumTrackOrder<T> {
  final List<T> tracks;
  final Map<int, List<T>> discGroups;
  final List<int> discNumbers;

  AlbumTrackOrder._(this.tracks, this.discGroups, this.discNumbers);

  factory AlbumTrackOrder(
    Iterable<T> items, {
    required int? Function(T) discNumber,
    required int? Function(T) trackNumber,
    required String Function(T) trackName,
  }) {
    final tracks = items.toList();
    tracks.sort((a, b) {
      final disc = (discNumber(a) ?? 1).compareTo(discNumber(b) ?? 1);
      if (disc != 0) return disc;
      final number = (trackNumber(a) ?? 999).compareTo(trackNumber(b) ?? 999);
      return number != 0 ? number : trackName(a).compareTo(trackName(b));
    });
    final discGroups = <int, List<T>>{};
    for (final track in tracks) {
      discGroups.putIfAbsent(discNumber(track) ?? 1, () => []).add(track);
    }
    return AlbumTrackOrder._(
      UnmodifiableListView(tracks),
      UnmodifiableMapView({
        for (final entry in discGroups.entries)
          entry.key: UnmodifiableListView(entry.value),
      }),
      UnmodifiableListView(discGroups.keys.toList()..sort()),
    );
  }
}

/// Full-width delete action for selection-mode bottom bars: destructive
/// (error) styling once at least one item is selected, disabled/neutral
/// otherwise.
class DestructiveSelectionButton extends StatelessWidget {
  const DestructiveSelectionButton({
    super.key,
    required this.count,
    required this.colorScheme,
    required this.onPressed,
  });

  final int count;
  final ColorScheme colorScheme;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: AppActionButton(
        isDestructive: true,
        onPressed: count > 0 ? onPressed : null,
        icon: const Icon(Icons.delete_outline),
        label: Text(
          count > 0
              ? context.l10n.collectionDeleteCount(count)
              : context.l10n.collectionSelectToDelete,
        ),
        style: FilledButton.styleFrom(
          backgroundColor: count > 0
              ? colorScheme.error
              : colorScheme.surfaceContainerHighest,
          foregroundColor: count > 0
              ? colorScheme.onError
              : colorScheme.onSurfaceVariant,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }
}

/// "Disc N" chip with a trailing hairline, shown between disc groups in
/// album track lists.
class DiscSeparatorChip extends StatelessWidget {
  const DiscSeparatorChip({super.key, required this.discNumber});

  final int discNumber;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
        child: Text(
          context.l10n.collectionDiscHeader(discNumber),
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }
  }
}
