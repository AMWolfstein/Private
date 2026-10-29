import 'package:sistrum/widgets/animation_utils.dart';
import 'dart:math';
import 'dart:io';

import 'package:sistrum/widgets/sheets/track_detail_actions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/widgets/collection_scaffold.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/theme/app_icons.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/library/local_collection_actions.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/widgets/cached_cover_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/services/library/m3u_playlist_service.dart';
import 'package:sistrum/utils/file_access.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/playback_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/local_library_cover_providers.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/screens/library/collapsing_header_scroll_mixin.dart';
import 'package:sistrum/screens/library/selection_mode_mixin.dart';
import 'package:sistrum/screens/library/library_tracks_folder_data.dart';
import 'package:sistrum/widgets/library/local_song_row.dart';
import 'package:sistrum/widgets/library/local_song_menu.dart';
import 'package:sistrum/widgets/selection/selection_action_button.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_sheet.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

String? _resolveRawCoverUrl(Track track) {
  final rawCover = track.coverUrl?.trim();
  if (rawCover != null &&
      rawCover.isNotEmpty &&
      !rawCover.startsWith('content://')) {
    return rawCover;
  }
  return null;
}

class LibraryCollectionTracksScreen extends ConsumerStatefulWidget {
  final LibraryCollectionMode mode;
  final String? playlistId;

  const LibraryCollectionTracksScreen({
    super.key,
    required this.mode,
    this.playlistId,
  });

  @override
  ConsumerState<LibraryCollectionTracksScreen> createState() =>
      _LibraryCollectionTracksScreenState();
}

class _LibraryCollectionTracksScreenState
    extends ConsumerState<LibraryCollectionTracksScreen>
    with
        SelectionModeMixin<LibraryCollectionTracksScreen>,
        CollapsingHeaderScrollMixin<LibraryCollectionTracksScreen> {
  UserPlaylistCollection? playlist;
  final _folderData = LibraryTracksFolderData();

  @override
  void initState() {
    super.initState();
    final playlistId = widget.playlistId;
    if (widget.mode == LibraryCollectionMode.playlist && playlistId != null) {
      Future.microtask(
        () => ref
            .read(libraryCollectionsProvider.notifier)
            .ensurePlaylistLoaded(playlistId),
      );
    }
  }

  /// Exports the collection as an .m3u8 shared via the system sheet. Tracks
  /// without a resolvable local file are skipped; SAF entries are written
  /// relative to the download tree root.
  Future<void> _exportAsM3u8(
    BuildContext context,
    String title,
    List<CollectionTrackEntry> entries,
  ) async {
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final tracks = entries.map((e) => e.track).toList(growable: false);
      final paths = await ref
          .read(playbackProvider.notifier)
          .resolveTrackFilePaths(tracks);

      final exportEntries = <M3uExportEntry>[];
      for (var i = 0; i < tracks.length; i++) {
        final path = paths[i];
        if (path == null || isCueVirtualPath(path)) continue;
        final entryPath = M3uPlaylistService.exportPathFor(path);
        if (entryPath == null) continue;
        exportEntries.add(M3uExportEntry(track: tracks[i], path: entryPath));
      }

      if (exportEntries.isEmpty) {
        messenger.showSnackBar(
          SnackBar(content: Text(l10n.collectionExportM3uNone)),
        );
        return;
      }

      final file = await M3uPlaylistService.writeExportEntries(
        title,
        exportEntries,
      );
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            l10n.collectionExportM3uDone(exportEntries.length, tracks.length),
          ),
        ),
      );
      await SharePlus.instance.share(
        ShareParams(files: [XFile(file.path)], text: title),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.collectionExportM3uFailed)),
      );
    }
  }

  IconData _modeIcon() {
    return switch (widget.mode) {
      LibraryCollectionMode.loved => Icons.favorite,
      LibraryCollectionMode.playlist => Icons.queue_music,
    };
  }

  /// Find the first available cover URL from entries.
  String? _firstRawCoverUrl(List<CollectionTrackEntry> entries) {
    for (final entry in entries) {
      final cover = _resolveRawCoverUrl(entry.track);
      if (cover != null && cover.isNotEmpty) {
        return cover;
      }
    }
    return null;
  }

  Future<void> _removeSelected(List<CollectionTrackEntry> entries) async {
    final keysToRemove = selectedIds.toSet();
    if (keysToRemove.isEmpty) return;

    final count = keysToRemove.length;
    final notifier = ref.read(libraryCollectionsProvider.notifier);

    try {
      switch (widget.mode) {
        case LibraryCollectionMode.loved:
          await notifier.removeLovedTracks(keysToRemove);
          break;
        case LibraryCollectionMode.playlist:
          if (widget.playlistId != null) {
            await notifier.removeTracksFromPlaylist(
              widget.playlistId!,
              keysToRemove,
            );
          }
          break;
      }
    } catch (error) {
      if (!mounted) return;
      final message = context.friendlyError(error);
      // The bar is painted over the snackbar, so leave selection mode first,
      // like the success path, or the error stays hidden behind the panel.
      exitSelectionMode();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
      return;
    }

    if (!mounted) return;
    exitSelectionMode();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.collectionRemovedTracks(count))),
    );
  }

  LocalLibraryCoverBatchRequest _coverBatchRequest(
    List<CollectionTrackEntry> entries,
  ) {
    return LocalLibraryCoverBatchRequest(
      entries
          .map(
            (entry) => LocalLibraryCoverRequest(
              isrc: entry.track.isrc?.trim(),
              trackName: entry.track.name,
              artistName: entry.track.artistName,
            ),
          )
          .toList(growable: false),
    );
  }

  void _addSelectedToPlaylist(List<CollectionTrackEntry> entries) {
    final selectedTracks = entries
        .where((e) => selectedIds.contains(e.key))
        .map((e) => e.track)
        .toList(growable: false);
    if (selectedTracks.isEmpty) return;

    showAddTracksToPlaylistSheet(context, ref, selectedTracks);
  }

  @override
  Widget build(BuildContext context) {
    // PERF-202: only the cover inputs are read here; the collection state is
    // selected in slices so an unrelated collection edit does not rebuild
    // this screen.
    final loved = widget.mode == LibraryCollectionMode.loved;
    final playlist = loved
        ? null
        : ref.watch(
            libraryCollectionsProvider.select(
              (state) => state.playlistById(widget.playlistId ?? ''),
            ),
          );
    final lovedEntries = loved
        ? ref.watch(libraryCollectionsProvider.select((state) => state.loved))
        : const <CollectionTrackEntry>[];
    final collection = playlist;
    final entries =
        (loved ? lovedEntries : playlist?.tracks) ??
        const <CollectionTrackEntry>[];
    String? nonempty(String? value) =>
        value?.trim().isNotEmpty == true ? value : null;
    final preferred =
        nonempty(collection?.coverImagePath) ??
        nonempty(collection?.previewCover) ??
        _firstRawCoverUrl(entries);
    final local = !loved && preferred == null && entries.isNotEmpty
        ? ref
              .watch(
                localLibraryFirstCoverProvider(_coverBatchRequest(entries)),
              )
              .asData
              ?.value
        : null;
    // Loved's heart has a neutral surface; playlist art is shared everywhere.
    final cover = loved ? null : preferred ?? local;
    {
      return AppArtistSurface(
        imageSource: cover,
        neutralActions: true,
        child: Builder(builder: (context) => _buildPage(context, cover)),
      );
    }
  }

  Widget _buildPage(BuildContext context, String? coverSource) {
    final colorScheme = Theme.of(context).colorScheme;
    ref.watch(localLibraryProvider.select((s) => s.loadedIndexVersion));
    final List<CollectionTrackEntry> entries;

    switch (widget.mode) {
      case LibraryCollectionMode.loved:
        playlist = null;
        entries = ref.watch(
          libraryCollectionsProvider.select((state) => state.loved),
        );
        break;
      case LibraryCollectionMode.playlist:
        final playlistId = widget.playlistId;
        playlist = playlistId == null
            ? null
            : ref.watch(
                libraryCollectionsProvider.select(
                  (state) => state.playlistById(playlistId),
                ),
              );
        entries = playlist?.tracks ?? const <CollectionTrackEntry>[];
        break;
    }

    _folderData.update(entries);
    pruneSelection(_folderData.keys);

    final title = switch (widget.mode) {
      LibraryCollectionMode.loved => context.l10n.collectionLoved,
      LibraryCollectionMode.playlist =>
        playlist?.name ?? context.l10n.collectionPlaylist,
    };

    final emptyTitle = switch (widget.mode) {
      LibraryCollectionMode.loved => context.l10n.collectionLovedEmptyTitle,
      LibraryCollectionMode.playlist =>
        context.l10n.collectionPlaylistEmptyTitle,
    };

    final emptySubtitle = switch (widget.mode) {
      LibraryCollectionMode.loved => context.l10n.collectionLovedEmptySubtitle,
      LibraryCollectionMode.playlist =>
        context.l10n.collectionPlaylistEmptySubtitle,
    };
    final folderTracks = _folderData.tracks;
    final loading =
        !ref.watch(
          libraryCollectionsProvider.select((state) => state.isLoaded),
        ) ||
        (widget.mode == LibraryCollectionMode.playlist &&
            playlist?.tracksLoaded == false);

    final bottomPadding = isSelectionMode
        ? MediaQuery.paddingOf(context).bottom
        : 0.0;

    return CollectionScaffold(
      scrollController: scrollController,
      isSelectionMode: isSelectionMode,
      onExitSelectionMode: exitSelectionMode,
      selectionBar: _buildSelectionBottomBar(
        context,
        colorScheme,
        entries,
        bottomPadding,
      ),
      appBar: _buildAppBar(
        context,
        colorScheme,
        title,
        entries,
        playlist,
        coverSource,
      ),
      slivers: [
        if (loading)
          const SliverToBoxAdapter(child: TrackListSkeleton())
        else if (entries.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyFolderState(
              title: emptyTitle,
              subtitle: emptySubtitle,
            ),
          )
        else
          SliverPadding(
            padding: EdgeInsets.symmetric(horizontal: wideListInset(context)),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final entry = entries[index];
                final isSelected = selectedIds.contains(entry.key);
                return KeyedSubtree(
                  key: ValueKey(entry.key),
                  // Collection contents must remain visible even when route
                  // or tab transitions pause animation tickers.
                  child: _CollectionTrackTile(
                    entry: entry,
                    mode: widget.mode,
                    playlistId: widget.playlistId,
                    folderTracks: folderTracks,
                    trackIndex: index,
                    isSelectionMode: isSelectionMode,
                    isSelected: isSelected,
                    onTap: isSelectionMode
                        ? () => toggleSelection(entry.key)
                        : null,
                    onLongPress: isSelectionMode
                        ? null
                        : () => enterSelectionMode(entry.key),
                  ),
                );
              }, childCount: entries.length),
            ),
          ),
        if (!loading && entries.isNotEmpty)
          buildTrackListFooter(
            context,
            colorScheme,
            folderTracks,
            excludeEpochReleaseDate: true,
          ),
      ],
    );
  }

  Widget _buildSelectionBottomBar(
    BuildContext context,
    ColorScheme colorScheme,
    List<CollectionTrackEntry> entries,
    double bottomPadding,
  ) {
    final selectedCount = selectedIds.length;
    final allSelected = selectedCount == entries.length && entries.isNotEmpty;

    return SelectionBottomBar(
      selectedCount: selectedCount,
      allSelected: allSelected,
      onClose: exitSelectionMode,
      onToggleSelectAll: () {
        if (allSelected) {
          exitSelectionMode();
        } else {
          selectAll(entries.map((e) => e.key));
        }
      },
      bottomPadding: bottomPadding,
      children: [
        Row(
          children: [
            Expanded(
              child: SelectionActionButton(
                icon: Icons.playlist_add,
                label:
                    '${context.l10n.collectionAddToPlaylist} ($selectedCount)',
                onPressed: selectedCount > 0
                    ? () => _addSelectedToPlaylist(entries)
                    : null,
                colorScheme: colorScheme,
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: selectedCount > 0
                ? () => _removeSelected(entries)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
            label: Text(
              selectedCount > 0
                  ? '${widget.mode == LibraryCollectionMode.playlist ? context.l10n.collectionRemoveFromPlaylist : context.l10n.collectionRemoveFromFolder} ($selectedCount)'
                  : widget.mode == LibraryCollectionMode.playlist
                  ? context.l10n.collectionRemoveFromPlaylist
                  : context.l10n.collectionRemoveFromFolder,
            ),
            style: FilledButton.styleFrom(
              backgroundColor: selectedCount > 0
                  ? colorScheme.error
                  : colorScheme.surfaceContainerHighest,
              foregroundColor: selectedCount > 0
                  ? colorScheme.onError
                  : colorScheme.onSurfaceVariant,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickCoverImage() async {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;

    Directory? materializedDir;
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null) return;

      var sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) {
        materializedDir = await Directory.systemTemp.createTemp(
          'sistrum_playlist_cover_',
        );
        final pickedExtension = p.extension(picked.name);
        final materializedFile = File(
          p.join(
            materializedDir.path,
            'selected_cover${pickedExtension.isEmpty ? '.img' : pickedExtension}',
          ),
        );
        await materializedFile.writeAsBytes(
          await picked.readAsBytes(),
          flush: true,
        );
        sourcePath = materializedFile.path;
      }

      await ref
          .read(libraryCollectionsProvider.notifier)
          .setPlaylistCover(playlistId, sourcePath);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.friendlyError(error))));
    } finally {
      try {
        if (materializedDir != null && await materializedDir.exists()) {
          await materializedDir.delete(recursive: true);
        }
      } catch (_) {
        // The cover has already been normalized into app storage.
      }
    }
  }

  Future<void> _removeCoverImage() async {
    final playlistId = widget.playlistId;
    if (playlistId == null) return;

    try {
      await ref
          .read(libraryCollectionsProvider.notifier)
          .removePlaylistCover(playlistId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.friendlyError(error))));
    }
  }

  Widget _buildAppBar(
    BuildContext context,
    ColorScheme colorScheme,
    String title,
    List<CollectionTrackEntry> entries,
    UserPlaylistCollection? playlist,
    String? coverSource,
  ) {
    final expandedHeight = calculateExpandedHeight(context);
    final customCoverPath = playlist?.coverImagePath;
    final isPlaylistMode = widget.mode == LibraryCollectionMode.playlist;
    final coverUrl = coverSource;
    final hasCustomCover =
        customCoverPath != null && customCoverPath.isNotEmpty;
    final hasCoverUrl = coverUrl != null;

    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (MediaQuery.sizeOf(context).width * dpr).round().clamp(
      320,
      2048,
    );
    final coverFallback = Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(_modeIcon(), size: 80, color: colorScheme.onSurfaceVariant),
    );
    Widget squarePlaceholder() => Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(_modeIcon(), size: 48, color: colorScheme.onSurfaceVariant),
    );

    final Widget background = hasCustomCover
        ? Image.file(
            File(customCoverPath),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            filterQuality: FilterQuality.low,
            gaplessPlayback: true,
            frameBuilder: (_, child, frame, wasSynchronouslyLoaded) {
              if (wasSynchronouslyLoaded || frame != null) {
                return child;
              }
              return coverFallback;
            },
            errorBuilder: (_, _, _) => coverFallback,
          )
        : hasCoverUrl
        ? LocalCoverImage(
            url: coverUrl,
            fit: BoxFit.cover,
            localCacheWidth: cacheWidth,
            fadeInDuration: Duration.zero,
            placeholder: (_) => Container(color: colorScheme.surface),
          )
        : coverFallback;

    return AlbumDetailHeader(
      title: title,
      immersive: context.isAppTheme,
      squareArtwork: true,
      appBarTitle: isSelectionMode
          ? context.l10n.selectionSelected(selectedIds.length)
          : null,
      expandedHeight: expandedHeight,
      showTitleInAppBar: showTitleInAppBar,
      background: background,
      paletteSource: coverSource,
      blurAndScrimBackground: hasCustomCover || hasCoverUrl,
      coverBuilder: (context, coverSize) {
        if (hasCustomCover) {
          return Image.file(
            File(customCoverPath),
            fit: BoxFit.cover,
            width: coverSize,
            height: coverSize,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => squarePlaceholder(),
          );
        }
        if (hasCoverUrl) {
          return LocalCoverImage(
            url: coverUrl,
            fit: BoxFit.cover,
            width: coverSize,
            height: coverSize,
            localCacheWidth: cacheWidth,
            placeholder: (_) => squarePlaceholder(),
          );
        }
        return squarePlaceholder();
      },
      meta: entries.isNotEmpty
          ? HeaderMetaRow(
              items: [
                HeaderMetaItem(
                  context.l10n.tracksCount(entries.length),
                  icon: _modeIcon(),
                ),
              ],
            )
          : null,
      actions: !isSelectionMode && entries.isNotEmpty
          ? _buildPlayAllCenterButton(entries)
          : null,
      appBarActions: [
        if (!isSelectionMode && entries.isNotEmpty)
          IconButton(
            icon: Icon(appIconFor(Icons.ios_share)),
            tooltip: context.l10n.collectionExportM3u,
            onPressed: () => _exportAsM3u8(context, title, entries),
          ),
        if (isPlaylistMode && !isSelectionMode) ...[
          IconButton(
            icon: Icon(appIconFor(Icons.edit_outlined)),
            tooltip: context.l10n.collectionRenamePlaylist,
            onPressed: () {
              final id = widget.playlistId ?? playlist?.id;
              if (id == null || id.isEmpty) return;
              _showRenamePlaylistDialog(context, id, playlist?.name ?? title);
            },
          ),
          IconButton(
            icon: Icon(appIconFor(Icons.camera_alt_outlined)),
            tooltip: context.l10n.collectionPlaylistChangeCover,
            onPressed: () => _showCoverOptionsSheet(context, hasCustomCover),
          ),
        ],
      ],
      leading: isSelectionMode
          ? HeaderCircleButton(
              icon: Icons.close,
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: exitSelectionMode,
            )
          : null,
    );
  }

  Widget _buildPlayAllCenterButton(List<CollectionTrackEntry> entries) {
    final tracks = entries.map((e) => e.track).toList(growable: false);
    final current = ref.watch(currentMediaItemProvider).asData?.value;
    final source = current?.extras?['source'];
    final inQueue =
        current != null &&
        tracks.any((track) => track.id == current.id || track.id == source);
    final playing = inQueue && ref.watch(playbackPlayingProvider);
    return LocalCollectionActions(
      tracks: tracks,
      isPlaying: playing,
      onPlay: inQueue
          ? () =>
                ref.read(musicPlayerControllerProvider).togglePlayPause(playing)
          : () => _playAll(tracks),
      onShuffle: () => _playAll(tracks, shuffle: true),
    );
  }

  Future<void> _playAll(List<Track> tracks, {bool shuffle = false}) async {
    if (tracks.isEmpty) return;
    try {
      final queue = tracks.toList();
      if (shuffle) queue.shuffle(Random());
      await ref.read(musicPlayerControllerProvider).setShuffle(shuffle);
      await ref.read(playbackProvider.notifier).playTrackList(queue);
    } catch (e) {
      if (mounted) showCannotOpenFileSnackBar(context, e);
    }
  }

  void _showCoverOptionsSheet(BuildContext context, bool hasCustomCover) {
    final colorScheme = Theme.of(context).colorScheme;

    showAppModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppSheetHandle(),
            const SizedBox(height: 16),
            AppSheetOption(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 4,
              ),
              leading: Icon(
                appIconFor(Icons.image_outlined),
                color: colorScheme.primary,
              ),
              title: Text(context.l10n.collectionPlaylistChangeCover),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickCoverImage();
              },
            ),
            if (hasCustomCover)
              AppSheetOption(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 4,
                ),
                leading: Icon(
                  appIconFor(Icons.delete_outline),
                  color: colorScheme.primary,
                ),
                title: Text(context.l10n.collectionPlaylistRemoveCover),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _removeCoverImage();
                },
              ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }

  Future<void> _showRenamePlaylistDialog(
    BuildContext context,
    String playlistId,
    String currentName,
  ) async {
    final controller = TextEditingController(text: currentName);
    final formKey = GlobalKey<FormState>();

    final String? nextName;
    try {
      nextName = await showAppDialog<String>(
        context: context,
        builder: (dialogContext) {
          return AppAlertDialog(
            title: Text(dialogContext.l10n.collectionRenamePlaylist),
            content: Form(
              key: formKey,
              child: TextFormField(
                controller: controller,
                autofocus: true,
                decoration: InputDecoration(
                  hintText: dialogContext.l10n.collectionPlaylistNameHint,
                ),
                validator: (value) {
                  final trimmed = value?.trim() ?? '';
                  if (trimmed.isEmpty) {
                    return dialogContext.l10n.collectionPlaylistNameRequired;
                  }
                  return null;
                },
                onFieldSubmitted: (_) {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.of(dialogContext).pop(controller.text.trim());
                },
              ),
            ),
            actions: [
              AppDialogAction(
                onPressed: () => Navigator.of(dialogContext).pop(),
                child: Text(dialogContext.l10n.dialogCancel),
              ),
              AppDialogAction(
                filled: true,
                onPressed: () {
                  if (formKey.currentState?.validate() != true) return;
                  Navigator.of(dialogContext).pop(controller.text.trim());
                },
                child: Text(dialogContext.l10n.dialogSave),
              ),
            ],
          );
        },
      );
    } finally {
      controller.dispose();
    }

    if (nextName == null || nextName.trim().isEmpty || !context.mounted) {
      return;
    }

    try {
      await ref
          .read(libraryCollectionsProvider.notifier)
          .renamePlaylist(playlistId, nextName.trim());
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.friendlyError(error))));
      return;
    }

    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.collectionPlaylistRenamed)),
    );
  }
}

class _CollectionTrackTile extends ConsumerWidget {
  final CollectionTrackEntry entry;
  final LibraryCollectionMode mode;
  final String? playlistId;
  final List<Track> folderTracks;
  final int trackIndex;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _CollectionTrackTile({
    required this.entry,
    required this.mode,
    required this.playlistId,
    required this.folderTracks,
    required this.trackIndex,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = entry.track;
    final rawCoverUrl = _resolveRawCoverUrl(track);
    final localCoverUrl = rawCoverUrl == null
        ? ref
              .watch(
                localLibraryCoverProvider(
                  LocalLibraryCoverRequest(
                    isrc: track.isrc?.trim(),
                    trackName: track.name,
                    artistName: track.artistName,
                  ),
                ),
              )
              .maybeWhen(data: (cover) => cover, orElse: () => null)
        : null;
    final effectiveCoverUrl = rawCoverUrl ?? localCoverUrl;

    final fresh = ref
        .watch(
          localSongLookupProvider((
            id: track.id,
            name: track.name,
            artist: track.artistName,
            isrc: track.isrc,
          )),
        )
        .asData
        ?.value;
    final current = ref.watch(currentMediaItemProvider).asData?.value;
    final source = current?.extras?['source'];
    final isCurrent =
        current != null &&
        (current.id == track.id ||
            source == track.id ||
            fresh != null &&
                (current.id == fresh.id ||
                    current.id == fresh.filePath ||
                    source == fresh.filePath));
    final playing = isCurrent && ref.watch(playbackPlayingProvider);
    return LocalSongRow(
      isPlaying: playing,
      title: fresh?.trackName ?? track.name,
      artist: fresh?.artistName ?? track.artistName,
      cover: fresh?.coverPath ?? effectiveCoverUrl,
      explicit: fresh?.explicit ?? track.isExplicit,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      onSelect: onTap,
      onLongPress: isSelectionMode ? onTap : onLongPress,
      onPlay: isCurrent
          ? () =>
                ref.read(musicPlayerControllerProvider).togglePlayPause(playing)
          : () => _playFromHere(context, ref),
      onMenu: (anchor) => fresh != null
          ? showLocalSongMenu(context, ref, fresh, anchor: anchor)
          : showCollectionSongMenu(context, ref, track, anchor: anchor),
    );
  }

  Future<void> _playFromHere(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(playbackProvider.notifier)
          .playTrackList(folderTracks, startIndex: trackIndex);
    } catch (error) {
      if (!context.mounted) return;
      showCannotOpenFileSnackBar(context, error);
    }
  }
}

class _EmptyFolderState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyFolderState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.folder_open,
              size: 60,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
