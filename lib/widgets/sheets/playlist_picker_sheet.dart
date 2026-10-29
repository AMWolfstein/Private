import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/utils/logger.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/glass/app_chrome.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_name_prompt.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_rows.dart';

final _log = AppLogger('PlaylistPicker');

Future<void> showAddTrackToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  Track track,
) {
  return showAddTracksToPlaylistSheet(context, ref, [track]);
}

Future<void> showAddTracksToPlaylistSheet(
  BuildContext context,
  WidgetRef ref,
  List<Track> tracks, {
  String? playlistNamePrefill,
  bool preserveOccurrences = false,
}) async {
  if (tracks.isEmpty) return;

  if (!context.mounted) return;

  await showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    showDragHandle: !context.isAppTheme,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) {
      final content = _PlaylistPickerSheetContent(
        tracks: tracks,
        playlistNamePrefill: playlistNamePrefill,
        preserveOccurrences: preserveOccurrences,
      );
      return sheetContext.isAppTheme
          ? AppGlassPanel(tintOpacity: 0.78, child: content)
          : content;
    },
  );
}

class _PlaylistPickerSheetContent extends ConsumerStatefulWidget {
  final List<Track> tracks;
  final String? playlistNamePrefill;
  final bool preserveOccurrences;

  const _PlaylistPickerSheetContent({
    required this.tracks,
    this.playlistNamePrefill,
    required this.preserveOccurrences,
  });

  @override
  ConsumerState<_PlaylistPickerSheetContent> createState() =>
      _PlaylistPickerSheetContentState();
}

class _PlaylistPickerSheetContentState
    extends ConsumerState<_PlaylistPickerSheetContent> {
  late final PlaylistPickerSummaryRequest _summaryRequest;
  final Set<String> _selectedPlaylistIds = {};
  final Set<String> _committedPlaylistIds = {};
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _summaryRequest = PlaylistPickerSummaryRequest.fromTracks(
      widget.tracks,
      preserveOccurrences: widget.preserveOccurrences,
    );
  }

  Future<void> _handleDone(List<PlaylistPickerSummary> playlists) async {
    if (_isSubmitting) return;
    setState(() => _isSubmitting = true);
    final notifier = ref.read(libraryCollectionsProvider.notifier);
    final effectiveDisabledIds = <String>{
      ..._committedPlaylistIds,
      for (final playlist in playlists)
        if (playlist.containsAllRequestedTracks) playlist.id,
    };
    final idsToAdd = _selectedPlaylistIds.difference(effectiveDisabledIds);
    final playlistNamesById = {
      for (final playlist in playlists) playlist.id: playlist.name,
    };
    final addedNames = <String>[];

    try {
      for (final playlistId in idsToAdd) {
        await notifier.addTracksToPlaylist(
          playlistId,
          widget.tracks,
          preserveOccurrences: widget.preserveOccurrences,
        );
        _committedPlaylistIds.add(playlistId);
        final playlistName = playlistNamesById[playlistId];
        if (playlistName != null && playlistName.isNotEmpty) {
          addedNames.add(playlistName);
        }
      }
    } catch (error, stack) {
      _log.e('Failed to add tracks to selected playlists', error, stack);
      if (!mounted) return;
      setState(() => _isSubmitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.friendlyError(error))));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).pop();

    if (addedNames.isNotEmpty) {
      final name = addedNames.length == 1
          ? addedNames.first
          : addedNames.join(', ');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.collectionAddedToPlaylist(name))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final playlistSummariesValue = ref.watch(
      libraryPlaylistPickerSummariesProvider(_summaryRequest),
    );
    final notifier = ref.read(libraryCollectionsProvider.notifier);

    final String subtitle;
    if (widget.tracks.length == 1) {
      final track = widget.tracks.first;
      subtitle = '${track.name} • ${track.artistName}';
    } else {
      subtitle = context.l10n.tracksCount(widget.tracks.length);
    }

    final resolvedPlaylists = playlistSummariesValue.asData?.value ?? const [];
    final effectiveDisabledIds = <String>{
      ..._committedPlaylistIds,
      for (final playlist in resolvedPlaylists)
        if (playlist.containsAllRequestedTracks) playlist.id,
    };
    final idsToAdd = _selectedPlaylistIds.difference(effectiveDisabledIds);
    final hasNewSelections = idsToAdd.isNotEmpty;

    void onDone() {
      if (_isSubmitting) return;
      if (hasNewSelections) {
        _handleDone(resolvedPlaylists);
      } else {
        setState(() => _isSubmitting = true);
        Navigator.of(context).pop();
      }
    }

    return SafeArea(
      top: false,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ...[
            const AppSheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              child: SizedBox(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.collectionAddToPlaylist,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Divider(height: 1),
          PlaylistPickerRow(
            leading: Icon(
              CupertinoIcons.add_circled,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: Text(context.l10n.collectionCreatePlaylist),
            enabled: !_isSubmitting,
            onTap: () async {
              if (_isSubmitting) return;
              final name = await promptPlaylistName(
                context,
                widget.playlistNamePrefill,
              );
              final trimmed = name?.trim() ?? '';
              if (trimmed.isEmpty || !mounted) return;
              // Creating and filling the playlist must not race Done or a
              // second tap on this row.
              setState(() => _isSubmitting = true);
              try {
                final playlistId = await notifier.createPlaylist(trimmed);
                await notifier.addTracksToPlaylist(
                  playlistId,
                  widget.tracks,
                  preserveOccurrences: widget.preserveOccurrences,
                );
                if (!mounted) return;
                setState(() {
                  _committedPlaylistIds.add(playlistId);
                  _selectedPlaylistIds.remove(playlistId);
                });
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      context.l10n.collectionAddedToPlaylist(trimmed),
                    ),
                  ),
                );
              } catch (error) {
                _log.e('Failed to create playlist', error);
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(context.friendlyError(error))),
                );
              } finally {
                if (mounted) setState(() => _isSubmitting = false);
              }
            },
          ),
          Flexible(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: playlistSummariesValue.when(
                data: (playlists) {
                  if (playlists.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                      child: Text(
                        context.l10n.collectionNoPlaylistsYet,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    itemCount: playlists.length,
                    itemBuilder: (context, index) {
                      final playlist = playlists[index];
                      final isAlreadyIn = effectiveDisabledIds.contains(
                        playlist.id,
                      );
                      final isSelected =
                          _selectedPlaylistIds.contains(playlist.id) ||
                          isAlreadyIn;

                      return PlaylistPickerRow(
                        leading: PlaylistPickerThumbnail(
                          playlist: playlist,
                          isSelected: !context.isAppTheme && isSelected,
                        ),
                        title: Text(playlist.name),
                        subtitle: Text(
                          context.l10n.collectionPlaylistTracks(
                            playlist.trackCount,
                          ),
                        ),
                        enabled: !isAlreadyIn && !_isSubmitting,
                        selected: isSelected,
                        onTap: !isAlreadyIn && !_isSubmitting
                            ? () {
                                if (_isSubmitting) return;
                                setState(() {
                                  if (_selectedPlaylistIds.contains(
                                    playlist.id,
                                  )) {
                                    _selectedPlaylistIds.remove(playlist.id);
                                  } else {
                                    _selectedPlaylistIds.add(playlist.id);
                                  }
                                });
                              }
                            : null,
                      );
                    },
                  );
                },
                loading: () => const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
                error: (error, _) => Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        context.friendlyError(error),
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                      const SizedBox(height: 4),
                      TextButton.icon(
                        onPressed: () => ref.invalidate(
                          libraryPlaylistPickerSummariesProvider(
                            _summaryRequest,
                          ),
                        ),
                        icon: const Icon(Icons.refresh, size: 18),
                        label: Text(context.l10n.dialogRetry),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: SizedBox(
              width: double.infinity,
              child: AppActionButton(
                onPressed: _isSubmitting ? null : onDone,
                icon: const Icon(CupertinoIcons.checkmark),
                label: Text(context.l10n.dialogDone),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
