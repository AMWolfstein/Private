import 'package:flutter/material.dart' show Theme, Text;
import 'package:sistrum/widgets/sheets/track_detail_actions.dart'
    show loveAllTracks;
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/widgets/header/album_play_actions.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/sheets/playlist_picker_sheet.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

/// Sistrum album/playlist action row: Loved, Play, Shuffle, Add to playlist.
/// The primary action plays local files in place of the retired download action.
class LocalCollectionActions extends ConsumerStatefulWidget {
  const LocalCollectionActions({
    super.key,
    required this.tracks,
    required this.onPlay,
    required this.onShuffle,
    this.isPlaying = false,
  });
  final List<Track> tracks;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final bool isPlaying;
  @override
  ConsumerState<LocalCollectionActions> createState() =>
      _LocalCollectionActionsState();
}

class _LocalCollectionActionsState
    extends ConsumerState<LocalCollectionActions> {
  bool _saving = false;
  @override
  Widget build(BuildContext context) {
    final loved = ref.watch(
      libraryCollectionsProvider.select(
        (s) => widget.tracks.isNotEmpty && widget.tracks.every(s.isLoved),
      ),
    );
    return AlbumPlayActions(
      isPlaying: widget.isPlaying,
      playLabel: widget.isPlaying
          ? context.l10n.actionPause
          : context.l10n.tooltipPlay,
      shuffleTooltip: context.l10n.actionShuffle,
      onPlay: widget.onPlay,
      onShuffle: widget.onShuffle,
      leadingAction: HeaderCircleButton(
        icon: loved ? CupertinoIcons.heart_fill : CupertinoIcons.heart,
        buttonSize: 48,
        tonal: true,
        iconColor: loved ? Theme.of(context).colorScheme.error : null,
        tooltip: loved
            ? context.l10n.trackOptionRemoveFromLoved
            : context.l10n.trackOptionAddToLoved,
        onPressed: widget.tracks.isEmpty || _saving
            ? null
            : () async {
                setState(() => _saving = true);
                try {
                  await loveAllTracks(context, ref, widget.tracks);
                } catch (error) {
                  if (context.mounted) {
                    showAppSnackBar(
                      context,
                      content: Text(
                        context.l10n.snackbarError(error.toString()),
                      ),
                    );
                  }
                } finally {
                  if (mounted) setState(() => _saving = false);
                }
              },
      ),
      trailingAction: HeaderCircleButton(
        icon: CupertinoIcons.text_badge_plus,
        buttonSize: 48,
        tonal: true,
        tooltip: context.l10n.collectionAddToPlaylist,
        onPressed: widget.tracks.isEmpty
            ? null
            : () => showAddTracksToPlaylistSheet(context, ref, widget.tracks),
      ),
    );
  }
}
