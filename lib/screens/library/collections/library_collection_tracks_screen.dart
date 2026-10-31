import 'package:sistrum/widgets/animation/animation_skeletons.dart';
import 'dart:math';
import 'dart:io';

import 'package:sistrum/widgets/sheets/track_detail_actions.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/widgets/collection/collection_scaffold.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:sistrum/widgets/header/album_detail_header.dart';
import 'package:sistrum/widgets/library/local_collection_actions.dart';
import 'package:sistrum/widgets/header/app_artist_header.dart';
import 'package:sistrum/widgets/cover/cached_cover_image.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/core/models/track.dart';
import 'package:sistrum/services/library/collections/m3u_playlist_service.dart';
import 'package:sistrum/utils/files/file_access.dart';
import 'package:sistrum/providers/library/library_collections_provider.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/playback/playback_provider.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/library/local_library_cover_providers.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/screens/library/shared/collapsing_header_scroll_mixin.dart';
import 'package:sistrum/screens/library/shared/selection_mode_mixin.dart';
import 'package:sistrum/screens/library/browse/library_tracks_folder_data.dart';
import 'package:sistrum/widgets/selection/selection_action_button.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_sheet.dart';
import 'package:sistrum/widgets/header/header_controls.dart';
import 'package:sistrum/screens/library/collections/collection_track_tile.dart';
import 'package:sistrum/screens/library/collections/collection_empty_folder_state.dart';

part 'library_collection_track_actions.dart';
part 'library_collection_track_chrome.dart';

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
}
