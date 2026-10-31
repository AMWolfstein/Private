import 'package:flutter/services.dart' show HapticFeedback;
import 'package:sistrum/utils/lyrics/lyric_models.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/playback/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/utils/playback/playback_seek_preview.dart';
import 'package:sistrum/widgets/primitives/app_loading_indicator.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics.dart';
import 'package:sistrum/widgets/lyrics/lyrics_text_scale.dart';

class PlayerLyricsSection extends ConsumerWidget {
  const PlayerLyricsSection({
    super.key,
    required this.metadata,
    required this.seekPreview,
    required this.colorScheme,
    required this.isActive,
    this.options,
    this.onShareLyrics,
  });

  final PlayerMetadataController metadata;
  final PlaybackSeekPreview seekPreview;
  final ColorScheme colorScheme;
  final bool isActive;
  final Widget? options;
  final ValueChanged<LyricLine?>? onShareLyrics;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final visibility = ref.watch(
      settingsProvider.select(
        (settings) =>
            (settings.playerShowPronunciation, settings.playerShowTranslation),
      ),
    );
    return ListenableBuilder(
      listenable: metadata,
      builder: (context, _) => _buildLyricsSection(context, visibility),
    );
  }

  Widget _buildLyricsSection(BuildContext context, (bool, bool) visibility) {
    // Center in the part the player's controls leave visible.
    final covered = LyricsCoveredBottom.of(context);
    if (metadata.loading) {
      return Padding(
        padding: EdgeInsets.only(bottom: covered),
        child: const Center(child: AppLoadingIndicator()),
      );
    }
    if (metadata.lyrics.isEmpty) {
      // Scrolls when a short screen leaves too little room above the
      // controls.
      return LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.only(bottom: covered),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minWidth: constraints.maxWidth,
              minHeight: constraints.hasBoundedHeight
                  ? (constraints.maxHeight - covered).clamp(
                      0.0,
                      double.infinity,
                    )
                  : 0,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.lyrics_outlined,
                      size: 40,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.nowPlayingNoLyrics,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }
    if (metadata.lyrics.synced) {
      return Stack(
        fit: StackFit.expand,
        children: [
          SyncedLyricsView(
            lyrics: metadata.lyrics,
            seekPreview: seekPreview,
            credits: _lyricsCredits(),
            colorScheme: colorScheme,
            isActive: isActive,
            showPronunciation: visibility.$1,
            showTranslation: visibility.$2,
            onLongPressLine: onShareLyrics,
          ),
          if (options != null)
            PositionedDirectional(
              start: appLyricsContentInset,
              bottom: 8,
              child: options!,
            ),
        ],
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onLongPress: onShareLyrics == null
                ? null
                : () {
                    HapticFeedback.mediumImpact();
                    onShareLyrics!(null);
                  },
            child: LyricsTextScale(
              child: Text(
                metadata.lyrics.plainText,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  height: 1.6,
                  color: colorScheme.onSurface,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          ?_lyricsCredits(),
        ],
      ),
    );
  }

  LyricsCredits? _lyricsCredits() {
    final (:writers, :provider) = metadata.credits;
    if (writers == null && provider == null) return null;
    return LyricsCredits(writers: writers, provider: provider);
  }
}
