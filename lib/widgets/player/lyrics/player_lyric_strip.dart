import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/utils/lyrics/lyric_direction.dart';
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:sistrum/utils/lyrics/lyrics_parser.dart';

/// The line being sung, shown above the player's seek bar. It rebuilds only
/// when the active line changes, not on every position tick. Plain (unsynced)
/// lyrics have no timing, so the strip stays empty for them.
class PlayerLyricStrip extends ConsumerWidget {
  const PlayerLyricStrip({
    super.key,
    required this.lyrics,
    required this.color,
  });

  final ParsedLyrics lyrics;
  final Color color;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!lyrics.synced || lyrics.lines.isEmpty) return const SizedBox.shrink();
    final index = ref.watch(
      playbackPositionProvider.select(
        (position) => LyricsParser.activeIndex(lyrics.lines, position),
      ),
    );
    final text = index < 0 ? '' : lyrics.lines[index].text.trim();
    // A fixed height keeps the seek bar from moving when a line is empty.
    return SizedBox(
      height: 28,
      child: Center(
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          textDirection: lyricLineDirection(text, Directionality.of(context)),
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
