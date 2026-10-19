import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/local_song_row.dart';

/// Album-style track row: track number, title/subtitle, and a trailing play
/// button that's hidden once selection mode is active.
///
/// Uses [LocalSongRow] so album and collection controls stay consistent.
class AlbumTrackTile extends StatelessWidget {
  const AlbumTrackTile({
    super.key,
    required this.trackNumber,
    required this.trackName,
    required this.subtitle,
    required this.isSelectionMode,
    required this.isSelected,
    required this.colorScheme,
    required this.onToggleSelection,
    required this.onEnterSelectionMode,
    required this.onPlay,
    this.isPlaying = false,
    this.explicit = false,
    required this.onMenu,
  });

  final int? trackNumber;
  final String trackName;
  final Widget subtitle;
  final bool isSelectionMode;
  final bool isSelected;
  final ColorScheme colorScheme;
  final VoidCallback onToggleSelection;
  final VoidCallback onEnterSelectionMode;
  final VoidCallback onPlay;
  final bool isPlaying;
  final bool explicit;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    return LocalSongRow(
      title: trackName,
      artist: '',
      numbered: true,
      number: trackNumber,
      explicit: explicit,
      isPlaying: isPlaying,
      artistWidget: subtitle,
      isSelectionMode: isSelectionMode,
      isSelected: isSelected,
      onSelect: onToggleSelection,
      onLongPress: isSelectionMode ? null : onEnterSelectionMode,
      onPlay: onPlay,
      onMenu: onMenu,
    );
  }
}
