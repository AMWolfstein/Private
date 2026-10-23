import 'dart:io';
import 'package:spotiflac_android/theme/mornye_icons.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:flutter/cupertino.dart';
import 'package:spotiflac_android/providers/playback_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/models/unified_library_item.dart';
import 'package:spotiflac_android/services/batch_track_actions.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/widgets/local_song_file_actions.dart';
import 'package:path_provider/path_provider.dart';
import 'package:spotiflac_android/services/library_edited_metadata.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/screens/track_metadata_edit_sheet.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/widgets/audio_analysis_widget.dart';
import 'package:spotiflac_android/widgets/mornye_context_menu.dart';
import 'package:spotiflac_android/widgets/app_sliver_header.dart';

final localSongLookupProvider = FutureProvider.autoDispose
    .family<
      LocalLibraryItem?,
      ({String id, String name, String artist, String? isrc})
    >((ref, request) async {
      ref.watch(
        localLibraryProvider.select((state) => state.loadedIndexVersion),
      );
      // A menu can resolve a song without mounting a row listener. Keep the
      // lookup alive until its one-shot caller receives the result.
      final lease = ref.keepAlive();
      try {
        final db = LibraryDatabase.instance;
        final row =
            await db.getById(request.id) ??
            await db.findExisting(
              isrc: request.isrc,
              trackName: request.name,
              artistName: request.artist,
            );
        return row == null ? null : LocalLibraryItem.fromJson(row);
      } finally {
        lease.close();
      }
    });

Future<void> showCollectionSongMenu(
  BuildContext context,
  WidgetRef ref,
  Track track, {
  Rect? anchor,
}) async {
  try {
    final item = await ref.read(
      localSongLookupProvider((
        id: track.id,
        name: track.name,
        artist: track.artistName,
        isrc: track.isrc,
      )).future,
    );
    if (!context.mounted) return;
    if (item == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarFileNotFound)),
      );
      return;
    }
    await showLocalSongMenu(context, ref, item, anchor: anchor);
  } catch (_) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarFileNotFound)),
      );
    }
  }
}

Future<bool> showLocalSongMenu(
  BuildContext context,
  WidgetRef ref,
  LocalLibraryItem item, {
  Rect? anchor,
}) async {
  final cue = isCueSong(item);
  final action = await showMornyeContextMenu<String>(
    context: context,
    anchor: anchor,
    fitToAnchorSpace: true,
    builder: (menuContext) {
      final l10n = context.l10n;
      MornyeMenuAction option(
        String id,
        IconData icon,
        String label, {
        bool destructive = false,
      }) => MornyeMenuAction(
        icon: mornyeIconFor(icon),
        label: label,
        destructive: destructive,
        onPressed: () => Navigator.of(menuContext).pop(id),
      );
      return MornyeContextMenu(
        quickActions: [
          option('play', CupertinoIcons.play_fill, l10n.tooltipPlay),
          option('share', CupertinoIcons.share_solid, l10n.trackMetadataShare),
        ],
        groups: [
          [
            option('next', Icons.playlist_play, l10n.trackPlayNext),
            option('queue', Icons.queue_music, l10n.trackAddToQueue),
            if (item.albumName.trim().isNotEmpty)
              option('album', Icons.album_outlined, l10n.homeGoToAlbum),
            if (item.artistName.trim().isNotEmpty)
              option('artist', Icons.person_outline, l10n.mornyeGoToArtist),
          ],
          [
            if (!cue) ...[
              option('copy', Icons.copy_outlined, l10n.trackCopyFilePath),
              option('edit', Icons.edit_outlined, l10n.trackEditMetadata),
              option('gain', Icons.graphic_eq, l10n.trackReplayGain),
              option(
                'removeGain',
                Icons.remove_circle_outline,
                l10n.trackRemoveReplayGain,
              ),
              option(
                'analysis',
                Icons.analytics_outlined,
                l10n.audioAnalysisTitle,
              ),
            ] else
              option('split', Icons.call_split, l10n.cueSplitTitle),
          ],
          [
            option(
              'delete',
              Icons.delete_outline,
              l10n.trackRemoveFromDevice,
              destructive: true,
            ),
          ],
        ],
      );
    },
  );
  if (!context.mounted || action == null) return false;
  try {
    switch (action) {
      case 'copy':
        await copyLocalSongPath(context, item);
      case 'artist':
        await navigateToArtistCredits(context, artistNames: item.artistName);
      case 'album':
        await navigateToAlbum(
          context,
          albumName: item.albumName,
          artistName: item.albumArtist ?? item.artistName,
          coverUrl: item.coverPath,
        );
      case 'delete':
        return await deleteLocalSong(context, item);
      case 'analysis':
        await Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => AudioQualityAnalysisScreen(item: item),
          ),
        );
      case 'split':
        await splitLocalCue(context, item);
      case 'edit':
        return await editLocalSongMetadata(context, ref, item);
      case 'gain':
      case 'removeGain':
        return await runBatchReplayGain(
          context,
          [UnifiedLibraryItem.fromLocalLibrary(item)],
          onExitSelectionMode: () {},
          remove: action == 'removeGain',
        );
      default:
        if (isCueVirtualPath(item.filePath)) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text(cueVirtualTrackRequiresSplitMessage)),
          );
          return false;
        }
        if (!await fileExists(item.filePath)) {
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(context.l10n.snackbarFileNotFound)),
            );
          }
          return false;
        }
        if (!context.mounted) return false;
        switch (action) {
          case 'play':
            await ref.read(playbackProvider.notifier).playLocalLibraryQueue([
              item,
            ], startItem: item);
          case 'next':
          case 'queue':
            final controller = ref.read(musicPlayerControllerProvider);
            if (action == 'next') {
              await controller.playNextLocal(item);
            } else {
              await controller.addToQueueLocal(item);
            }
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    action == 'next'
                        ? context.l10n.snackbarPlayingNext
                        : context.l10n.snackbarAddedToQueueGeneric,
                  ),
                ),
              );
            }
          case 'share':
            await shareLocalSong(context, item);
        }
    }
  } catch (error) {
    if (context.mounted) showCannotOpenFileSnackBar(context, error);
  }
  return false;
}

Future<bool> editLocalSongMetadata(
  BuildContext context,
  WidgetRef ref,
  LocalLibraryItem item,
) async {
  if (isCueVirtualPath(item.filePath)) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text(cueVirtualTrackRequiresSplitMessage)),
    );
    return false;
  }
  final library = ref.read(localLibraryProvider.notifier);
  final artistTagMode = artistTagModeForExistingTags(
    ref.read(settingsProvider).artistTagMode,
  );
  final metadataSeparators = ref.read(settingsProvider).metadataSeparators;
  Map<String, dynamic> tags = {};
  try {
    tags = await PlatformBridge.readFileMetadata(item.filePath);
  } catch (_) {
    /* Use stored tags if reading fails. */
  }
  String val(String key, Object? fallback) =>
      tags[key]?.toString() ?? fallback?.toString() ?? '';
  final values = <String, String>{
    'title': val('title', item.trackName),
    'artist': val('artist', item.artistName),
    'album': val('album', item.albumName),
    'album_artist': val('album_artist', item.albumArtist),
    'date': val('date', item.releaseDate),
    'track_number': val('track_number', item.trackNumber),
    'total_tracks': val('total_tracks', item.totalTracks),
    'disc_number': val('disc_number', item.discNumber),
    'total_discs': val('total_discs', item.totalDiscs),
    'genre': val('genre', item.genre),
    'isrc': val('isrc', item.isrc),
    'composer': val('composer', item.composer),
    'label': val('label', item.label),
    'copyright': val('copyright', item.copyright),
    'explicit': (parseExplicitFlag(tags['explicit']) ?? item.explicit)
        ? '1'
        : '0',
    for (final key in ['comment', 'album_type', 'upc', 'lyrics'])
      key: val(key, ''),
  };
  if (!context.mounted) return false;
  final saved = await showModalBottomSheet<bool>(
    context: context,
    useRootNavigator: true,
    isScrollControlled: true,
    builder: (_) => EditMetadataSheet(
      colorScheme: Theme.of(context).colorScheme,
      initialValues: values,
      filePath: item.filePath,
      durationMs: (item.duration ?? 0) * 1000,
      artistTagMode: artistTagMode,
      metadataSeparators: metadataSeparators,
    ),
  );
  if (saved != true) return false;
  try {
    final fresh = await PlatformBridge.readFileMetadata(item.filePath);
    if (fresh['error'] == null) {
      final json = localMetadataAfterEdit(item, fresh);
      try {
        final directory = Directory(
          '${(await getApplicationSupportDirectory()).path}/library_covers',
        );
        await directory.create(recursive: true);
        final path =
            '${directory.path}/edited_${DateTime.now().microsecondsSinceEpoch}.jpg';
        final cover = await PlatformBridge.extractCoverToFile(
          item.filePath,
          path,
        );
        final file = File(path);
        if (cover['error'] == null &&
            await file.exists() &&
            await file.length() > 0) {
          json['coverPath'] = path;
          // Reference-aware cover pruning reclaims the old image only after
          // the database stops referring to it, including failed refreshes.
        } else if (await file.exists()) {
          await file.delete();
        }
      } catch (error) {
        AppLogger(
          'SongMetadata',
        ).w('Saved tags but could not refresh artwork: $error');
      }
      await LibraryDatabase.instance.upsert(json, sourceId: item.sourceId);
    }
    await library.reloadFromStorage();
  } catch (error) {
    AppLogger(
      'SongMetadata',
    ).w('Saved tags but could not refresh the library index: $error');
  }
  if (context.mounted) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.l10n.snackbarMetadataSaved)));
  }
  return true;
}

class AudioQualityAnalysisScreen extends StatelessWidget {
  const AudioQualityAnalysisScreen({super.key, required this.item});
  final LocalLibraryItem item;
  @override
  Widget build(BuildContext context) => Scaffold(
    body: CustomScrollView(
      slivers: [
        AppSliverHeader.page(title: context.l10n.audioAnalysisTitle),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: AudioAnalysisCard(
              filePath: item.filePath,
              codecHint: item.format,
              exportName: [
                item.artistName.trim(),
                item.trackName.trim(),
              ].where((part) => part.isNotEmpty).join(' - '),
            ),
          ),
        ),
      ],
    ),
  );
}
