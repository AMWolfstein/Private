import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/utils/clickable_metadata.dart';
import 'package:spotiflac_android/utils/local_playback.dart';
import 'package:spotiflac_android/widgets/audio_quality_badges.dart';
import 'package:spotiflac_android/widgets/track_card.dart';
import 'package:spotiflac_android/widgets/in_library_badge.dart';
import 'package:spotiflac_android/widgets/track_collection_quick_actions.dart';

/// Track row shared by the library and playlist screens. Tapping plays the
/// local copy when one exists. Long-press opens the track options sheet.
/// Callers supply [leading] (track number, cover art, ...) and choose whether
/// the artist name links to the artist screen.
class TrackListTile extends ConsumerWidget {
  final Track track;
  final Widget leading;
  final bool clickableArtist;
  final bool showQualityBadges;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback? onToggleSelection;
  final VoidCallback? onEnterSelectionMode;

  const TrackListTile({
    super.key,
    required this.track,
    required this.leading,
    this.clickableArtist = false,
    this.showQualityBadges = true,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.onToggleSelection,
    this.onEnterSelectionMode,
  }) : assert(!isSelectionMode || onToggleSelection != null);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorScheme = Theme.of(context).colorScheme;

    final showLocalLibraryIndicator = ref.watch(
      settingsProvider.select(
        (s) => s.localLibraryEnabled && s.localLibraryShowDuplicates,
      ),
    );
    final isInLocalLibrary = showLocalLibraryIndicator
        ? ref.watch(
            localLibraryProvider.select(
              (state) => state.existsInLibrary(
                isrc: track.isrc,
                trackName: track.name,
                artistName: track.artistName,
              ),
            ),
          )
        : false;

    return TrackCard(
      style: TrackCardStyle.flat,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      leading: leading,
      title: track.name,
      subtitle: TrackMetadataBadgesLine(
        primary: clickableArtist && !isSelectionMode
            ? ClickableArtistName(
                artistName: track.artistName,
                artistId: track.artistId,
                coverUrl: track.coverUrl,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              )
            : Text(
                track.artistName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
        badges: [
          ...buildQualityBadges(
            audioQuality: showQualityBadges ? track.audioQuality : null,
            audioModes: showQualityBadges ? track.audioModes : null,
            colorScheme: colorScheme,
            explicit: track.isExplicit,
          ),
          if (isInLocalLibrary) const InLibraryBadge(),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TrackCollectionQuickActions(
            track: track,
            hasLocalPlaybackCandidate: isInLocalLibrary,
          ),
        ],
      ),
      onTap: isSelectionMode
          ? onToggleSelection
          : () => _handleTap(context, ref),
      onLongPress: isSelectionMode
          ? null
          : onEnterSelectionMode ??
                () => TrackCollectionQuickActions.showTrackOptionsSheet(
                  context,
                  ref,
                  track,
                  hasLocalPlaybackCandidate: isInLocalLibrary,
                ),
    );
  }

  Future<void> _handleTap(BuildContext context, WidgetRef ref) async {
    final playedLocal = await playLocalIfAvailable(context, ref, track);
    if (playedLocal || !context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.snackbarFileNotFound)),
    );
  }
}
