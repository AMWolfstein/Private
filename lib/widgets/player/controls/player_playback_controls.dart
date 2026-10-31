import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyric_strip.dart';
import 'package:sistrum/widgets/sheets/audio_info_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/playback/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/utils/playback/playback_seek_preview.dart';
import 'package:sistrum/utils/text/string_utils.dart';
import 'package:sistrum/widgets/status/automix_status_badge.dart';
import 'package:sistrum/widgets/player/controls/app_playback_button.dart';
import 'package:sistrum/widgets/player/controls/app_playback_time.dart';
import 'package:sistrum/widgets/player/controls/app_player_slider.dart';
import 'package:sistrum/widgets/player/controls/playback_seek_slider.dart';

const _appTimelinePadding = 28.0;

class PlayerPlaybackControls extends ConsumerWidget {
  final String mediaId;
  final Duration duration;
  final PlaybackSeekPreview seekPreview;
  final ColorScheme colorScheme;
  final PlayerMetadataController metadata;
  final bool compact;
  final double transportTopPadding;

  const PlayerPlaybackControls({
    super.key,
    required this.mediaId,
    required this.duration,
    required this.seekPreview,
    required this.colorScheme,
    required this.metadata,
    this.compact = false,
    this.transportTopPadding = 16,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(musicPlayerControllerProvider);
    final sistrum = context.isAppTheme;
    final isPlaying = ref.watch(playbackPlayingProvider);
    final isLoading = ref.watch(playbackLoadingProvider);
    final playPauseSize = compact
        ? (isPlaying ? 44.0 : 40.0)
        : (isPlaying ? 60.0 : 54.0);
    final timeStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant);
    // Time runs left to right in every language: the timeline and the
    // transport keep their order in right-to-left layouts, as Material and
    // Apple's guidelines ask for media controls.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: Column(
        children: [
          ValueListenableBuilder<Duration?>(
            valueListenable: seekPreview,
            builder: (context, preview, _) => Consumer(
              builder: (context, ref, quality) {
                final position = ref.watch(playbackPositionProvider);
                final elapsedSeconds = (preview ?? position).inSeconds;
                final showLyrics = ref.watch(
                  settingsProvider.select((s) => s.lyricsAboveSeekBar),
                );
                return Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: sistrum ? _appTimelinePadding : 16,
                  ),
                  child: Column(
                    children: [
                      if (showLyrics)
                        // Lyrics arrive after the controls are built.
                        ListenableBuilder(
                          listenable: metadata,
                          builder: (context, _) => PlayerLyricStrip(
                            lyrics: metadata.lyrics,
                            color: colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 4,
                          activeTrackColor: sistrum
                              ? colorScheme.onSurface
                              : colorScheme.primary,
                          inactiveTrackColor: colorScheme.onSurface.withValues(
                            alpha: 0.18,
                          ),
                          thumbColor: sistrum
                              ? colorScheme.onSurface
                              : colorScheme.primary,
                          // A 7dp thumb was hard to grab; 10dp with a 24dp overlay
                          // gives the drag gesture a full-size target.
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 10,
                          ),
                          overlayShape: const RoundSliderOverlayShape(
                            overlayRadius: 24,
                          ),
                        ),
                        child: PlaybackSeekSlider(
                          key: ValueKey(mediaId),
                          position: position,
                          duration: duration,
                          onSeek: controller.seek,
                          preview: seekPreview,
                          playing: isPlaying && !isLoading,
                        ),
                      ),
                      if (!sistrum) const SizedBox(height: 8),
                      Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: sistrum
                              ? AppPlayerSlider.horizontalInset
                              : 12,
                        ),
                        child: Row(
                          children: [
                            if (sistrum)
                              AppPlaybackTime(
                                key: ValueKey('elapsed:$mediaId'),
                                seconds: elapsedSeconds,
                                style: timeStyle,
                              )
                            else
                              Text(
                                formatClock(elapsedSeconds),
                                style: timeStyle,
                              ),
                            Expanded(child: Center(child: quality)),
                            if (sistrum)
                              AppPlaybackTime(
                                key: ValueKey('remaining:$mediaId'),
                                // Subtract whole seconds so both labels roll together,
                                // even when the track duration includes milliseconds.
                                seconds: (duration.inSeconds - elapsedSeconds)
                                    .clamp(0, duration.inSeconds),
                                remaining: true,
                                style: timeStyle,
                              )
                            else
                              Text(
                                formatClock(duration.inSeconds),
                                style: timeStyle,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _QualityBadge(metadata: metadata, colorScheme: colorScheme),
                  const AutoMixStatusBadge(),
                ],
              ),
            ),
          ),
          SizedBox(height: compact ? 8 : transportTopPadding + (0)),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: (compact ? 16 : 32)),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ...[],
                AppPlaybackButton(
                  icon: CupertinoIcons.backward_fill,
                  color: colorScheme.onSurface,
                  tooltip: context.l10n.nowPlayingPreviousTrack,
                  onPressed: controller.previous,
                ),
                AppPlaybackButton(
                  icon: isPlaying
                      ? CupertinoIcons.pause_fill
                      : CupertinoIcons.play_fill,
                  tooltip: isPlaying
                      ? context.l10n.actionPause
                      : context.l10n.tooltipPlay,
                  color: colorScheme.onSurface,
                  iconSize: playPauseSize,
                  padding: EdgeInsets.all((68 - playPauseSize) / 2),
                  loading: isLoading,
                  onPressed: () => controller.togglePlayPause(isPlaying),
                ),
                AppPlaybackButton(
                  icon: CupertinoIcons.forward_fill,
                  color: colorScheme.onSurface,
                  tooltip: context.l10n.nowPlayingNextTrack,
                  onPressed: controller.next,
                ),
                ...[],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityBadge extends StatelessWidget {
  final PlayerMetadataController metadata;
  final ColorScheme colorScheme;

  const _QualityBadge({required this.metadata, required this.colorScheme});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: metadata,
    builder: (context, _) => _buildBadge(context),
  );

  Widget _buildBadge(BuildContext context) {
    final text = metadata.qualityLabel;
    if (text == null || text.isEmpty) return const SizedBox.shrink();

    final badge = Container(
      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.graphic_eq, size: 11, color: colorScheme.onSurfaceVariant),
          SizedBox(width: 5),
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontSize: 10.5,
                color: colorScheme.onSurfaceVariant,
                letterSpacing: 0.2,
              ),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      label: context.l10n.audioInfoTitle,
      child: Tooltip(
        message: context.l10n.audioInfoTitle,
        excludeFromSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => showAudioInfoSheet(context, metadata: metadata),
            child: badge,
          ),
        ),
      ),
    );
  }
}
