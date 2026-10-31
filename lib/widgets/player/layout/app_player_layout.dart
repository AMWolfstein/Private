import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:sistrum/providers/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/core/navigation/now_playing_route.dart';
import 'package:sistrum/utils/playback/playback_seek_preview.dart';
import 'package:sistrum/widgets/primitives/app_context_menu.dart';
import 'package:sistrum/widgets/player/layout/app_landscape_player.dart';
import 'package:sistrum/widgets/player/controls/app_player_favorite_button.dart';
import 'package:sistrum/widgets/player/layout/app_player_header_layout.dart';
import 'package:sistrum/widgets/player/lyrics/app_player_lyrics_viewport.dart';
import 'package:sistrum/widgets/player/queue/app_player_queue.dart';
import 'package:sistrum/widgets/player/controls/app_volume_control.dart';
import 'package:sistrum/widgets/animation/overflow_marquee.dart';
import 'package:sistrum/widgets/player/artwork/player_artwork.dart';
import 'package:sistrum/widgets/player/layout/player_gesture_regions.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics_controls.dart';
import 'package:sistrum/widgets/player/layout/player_metadata_title.dart';
import 'package:sistrum/widgets/player/controls/player_playback_controls.dart';
import 'package:sistrum/widgets/player/layout/player_track_swipe.dart';

part 'app_player_layout_members_1.dart';

/// Keys stay owned by the surface that measures contrast and route dismissal.
typedef AppPlayerArtworkKeys = ({
  GlobalKey header,
  GlobalKey controls,
  GlobalKey volume,
  GlobalKey expanded,
  GlobalKey compact,
});

class AppPlayerLayout extends ConsumerWidget {
  const AppPlayerLayout({
    super.key,
    required this.mediaItem,
    required this.metadata,
    required this.seekPreview,
    required this.colorScheme,
    required this.page,
    required this.motionArtwork,
    required this.insetArtwork,
    required this.artworkTopInset,
    required this.artworkKeys,
    required this.artworkForeground,
    required this.lyricsControlsHidden,
    required this.lyricsOptionsOpen,
    required this.lyricsBuilder,
    required this.lyricsOptions,
    required this.onPageChanged,
    required this.onTrackNavigation,
    required this.onMoreActions,
    this.artworkAspectRatio,
  });

  final MediaItem mediaItem;
  final PlayerMetadataController metadata;
  final PlaybackSeekPreview seekPreview;
  final ColorScheme colorScheme;
  final int page;
  final Widget motionArtwork;
  final double? artworkAspectRatio;
  final bool insetArtwork;
  final double artworkTopInset;
  final AppPlayerArtworkKeys artworkKeys;
  final ValueListenable<Map<String, Color>> artworkForeground;
  final bool lyricsControlsHidden;
  final bool lyricsOptionsOpen;
  final Widget Function(bool showOptions) lyricsBuilder;
  final Widget? lyricsOptions;
  final ValueChanged<int> onPageChanged;
  final Future<void> Function(BuildContext, MediaItem) onTrackNavigation;
  final Future<void> Function(BuildContext, MediaItem, Rect?) onMoreActions;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(musicPlayerControllerProvider);
    final showLyrics = page == 1;
    final showQueue = page == 2;
    final compactStage = showLyrics || showQueue;
    ColorScheme foreground(String region) {
      final color = compactStage
          ? null
          : artworkForeground.value[region] ?? colorScheme.onSurface;
      return color == null
          ? colorScheme
          : colorScheme.copyWith(
              onSurface: color,
              onSurfaceVariant: color.withValues(alpha: 0.72),
            );
    }

    final motion = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 380);
    final queue = ref.watch(playQueueProvider).value ?? const <MediaItem>[];
    final reportedIndex = ref.watch(
      playbackStateProvider.select((state) => state.value?.queueIndex),
    );
    final currentIndex =
        reportedIndex != null &&
            reportedIndex >= 0 &&
            reportedIndex < queue.length &&
            queue[reportedIndex].id == mediaItem.id
        ? reportedIndex
        : queue.indexWhere((item) => item.id == mediaItem.id);
    final landscape =
        MediaQuery.sizeOf(context).width > MediaQuery.sizeOf(context).height;
    Widget hideControls(Widget child) => PlayerLyricsControlsVisibility(
      hidden: showLyrics && lyricsControlsHidden && !landscape,
      child: child,
    );
    final body = LayoutBuilder(
      builder: (context, constraints) {
        final screenSize = MediaQuery.sizeOf(context);
        final landscape = screenSize.width > screenSize.height;
        final scale = MediaQuery.textScalerOf(context).scale(17) / 17;
        const compactCoverSize = 72.0;
        final compactHeaderHeight = (44 * scale + 4).clamp(
          compactCoverSize,
          double.infinity,
        );
        Widget stage({
          bool artworkOnly = false,
          double progress = 0,
        }) => LayoutBuilder(
          builder: (context, stage) {
            final compact = compactStage && !artworkOnly;
            final expandedArtwork =
                artworkOnly || (!compactStage && insetArtwork);
            final artSize = (stage.maxWidth - (artworkOnly ? 56 : 48)).clamp(
              0.0,
              (stage.maxHeight - (artworkOnly ? 24 : 8)).clamp(0.0, 360.0),
            );
            final ratio = artworkAspectRatio ?? 1.0;
            final artWidth = ratio < 1 ? artSize * ratio : artSize;
            final artHeight = ratio > 1 ? artSize / ratio : artSize;
            final fullBleed = !insetArtwork && !artworkOnly;
            // Match the background's bounds even while this cover is hidden.
            // Opening/closing a panel then moves the cover between the same
            // two positions, with the playback controls painted above it.
            final motionHeight = artworkAspectRatio != null
                ? (screenSize.width / ratio).clamp(
                    0.0,
                    screenSize.height * 0.75,
                  )
                : screenSize.height * 0.66;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: compact ? compactHeaderHeight + 8 : stage.maxHeight,
                  child: const PlayerTrackSwipeRegion(child: SizedBox.expand()),
                ),
                Positioned.fill(
                  top: 8 + compactHeaderHeight + 16,
                  child: IgnorePointer(
                    ignoring: !compact,
                    child: ExcludeSemantics(
                      excluding: !compact,
                      child: AnimatedSwitcher(
                        duration: motion,
                        switchInCurve: Curves.easeInOutCubic,
                        switchOutCurve: Curves.easeInOutCubic,
                        transitionBuilder: (child, animation) => FadeTransition(
                          opacity: animation,
                          child: SlideTransition(
                            position: Tween(
                              begin: const Offset(0, 0.035),
                              end: Offset.zero,
                            ).animate(animation),
                            child: child,
                          ),
                        ),
                        layoutBuilder: (currentChild, previousChildren) =>
                            Stack(
                              fit: StackFit.expand,
                              children: [
                                // Preserve each panel's parent and key when
                                // it becomes outgoing, including lyric scroll.
                                for (final child in [
                                  ...previousChildren,
                                  ?currentChild,
                                ])
                                  IgnorePointer(
                                    key: child.key,
                                    ignoring: child != currentChild,
                                    child: ExcludeSemantics(
                                      excluding: child != currentChild,
                                      child: child,
                                    ),
                                  ),
                              ],
                            ),
                        // Keep the outgoing panel until it fades out;
                        // closing the queue must never substitute lyrics.
                        child: compact
                            ? KeyedSubtree(
                                key: ValueKey(page),
                                child: showQueue
                                    ? AppPlayerQueue(colorScheme: colorScheme)
                                    : appLyricsViewport(
                                        context,
                                        lyricsBuilder(false),
                                        lyricsControlsHidden:
                                            lyricsControlsHidden,
                                        visibleHeight:
                                            stage.minHeight -
                                            (8 + compactHeaderHeight + 16),
                                      ),
                              )
                            : null,
                      ),
                    ),
                  ),
                ),
                Consumer(
                  builder: (context, ref, child) =>
                      TweenAnimationBuilder<double>(
                        tween: Tween(
                          end:
                              !insetArtwork ||
                                  ref.watch(playbackPlayingProvider)
                              ? 1
                              : 0.73,
                        ),
                        duration: motion,
                        curve: Curves.easeInOutCubic,
                        builder: (context, scale, child) => Positioned.fromRect(
                          // Both cover layers travel to the actual resting size,
                          // including the smaller cover used while paused.
                          rect: Rect.lerp(
                            Rect.fromLTWH(
                              fullBleed
                                  ? 0
                                  : (stage.maxWidth - artWidth * scale) / 2,
                              fullBleed
                                  ? -artworkTopInset
                                  : (stage.maxHeight - artHeight * scale) / 2,
                              fullBleed ? stage.maxWidth : artWidth * scale,
                              fullBleed ? motionHeight : artHeight * scale,
                            ),
                            const Rect.fromLTWH(
                              kAppPlayerContentInset,
                              8,
                              compactCoverSize,
                              compactCoverSize,
                            ),
                            progress,
                          )!,
                          child: child!,
                        ),
                        child: child,
                      ),
                  // Both layers share the header's progress, so reversing a
                  // transition reuses the live cover instead of inserting a
                  // duplicate while its previous instance is still fading.
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      for (final expanded in [true, false])
                        if (expanded
                            ? !fullBleed && (!compact || progress < 1)
                            : compact || progress > 0)
                          HeroMode(
                            key: ValueKey(expanded),
                            enabled: expanded ? expandedArtwork : compact,
                            child: IgnorePointer(
                              ignoring: expanded ? !expandedArtwork : !compact,
                              child: FadeTransition(
                                opacity: AlwaysStoppedAnimation(
                                  expanded ? 1 - progress : progress,
                                ),
                                child: KeyedSubtree(
                                  key: ValueKey(
                                    expanded
                                        ? 'full-player-artwork'
                                        : 'compact-player-artwork',
                                  ),
                                  child: PlayerArtworkDragRegion(
                                    child: Hero(
                                      tag: kNowPlayingArtworkHeroTag,
                                      child: expanded
                                          ? DecoratedBox(
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(12),
                                                boxShadow: const [
                                                  BoxShadow(
                                                    color: Color(0x40000000),
                                                    blurRadius: 28,
                                                    offset: Offset(0, 16),
                                                  ),
                                                ],
                                              ),
                                              child: PlayerTransitionArtwork(
                                                artworkKey:
                                                    artworkKeys.expanded,
                                                child: ClipRRect(
                                                  borderRadius:
                                                      BorderRadius.circular(12),
                                                  child: motionArtwork,
                                                ),
                                              ),
                                            )
                                          : Semantics(
                                              button: true,
                                              label: context
                                                  .l10n
                                                  .nowPlayingTabPlayer,
                                              child: GestureDetector(
                                                behavior:
                                                    HitTestBehavior.opaque,
                                                onTap: () => onPageChanged(0),
                                                child: PlayerTransitionArtwork(
                                                  artworkKey:
                                                      artworkKeys.compact,
                                                  child: ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                          12,
                                                        ),
                                                    child: PlayerArtwork(
                                                      artUri: mediaItem.artUri
                                                          ?.toString(),
                                                      colorScheme: colorScheme,
                                                      cacheWidth:
                                                          PlayerArtwork.transitionCacheWidth(
                                                            context,
                                                          ),
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                    ],
                  ),
                ),
              ],
            );
          },
        );

        // Portrait video must not push the metadata/transport below the
        // square-cover position. Leave room above the anchored volume row.
        final volumeGap = 8 + (constraints.maxHeight - 440).clamp(0.0, 24.0);
        // Keep transport close to the timeline; spare height belongs above
        // the volume row without moving either slider or the track header.
        final transportShift = landscape
            ? 0.0
            : ((volumeGap - 16) / 2).clamp(0.0, 8.0);
        Widget controls() => AnimatedBuilder(
          animation: artworkForeground,
          builder: (context, _) => PlayerPlaybackControls(
            key: artworkKeys.controls,
            mediaId: mediaItem.id,
            duration: mediaItem.duration ?? Duration.zero,
            seekPreview: seekPreview,
            colorScheme: foreground('controls'),
            metadata: metadata,
            compact: landscape,
            transportTopPadding: 16 + transportShift,
          ),
        );

        if (landscape) {
          return AppLandscapePlayer(
            page: page,
            isPlaying: ref.watch(playbackPlayingProvider),
            controlsHeldOpen: lyricsOptionsOpen,
            onPageChanged: onPageChanged,
            artwork: stage(artworkOnly: true),
            header: _trackHeader(context, colorScheme, compact: true),
            lyrics: lyricsBuilder(true),
            lyricsOptions: showLyrics ? lyricsOptions : null,
            queue: AppPlayerQueue(colorScheme: colorScheme),
            controls: controls(),
            volume: const AppVolumeControl(),
          );
        }

        final options = showLyrics ? lyricsOptions : null;
        Widget content() => TweenAnimationBuilder<double>(
          tween: Tween(begin: 0, end: compactStage ? 1 : 0),
          duration: motion,
          curve: Curves.easeInOutCubic,
          builder: (context, progress, controls) => CustomMultiChildLayout(
            delegate: AppPlayerHeaderLayout(
              progress: progress,
              compactHeight: compactHeaderHeight,
              compactLeft: kAppPlayerContentInset + compactCoverSize + 12,
              expandLyrics: showLyrics,
            ),
            children: [
              LayoutId(
                id: AppPlayerHeaderSlot.stage,
                child: stage(progress: progress),
              ),
              LayoutId(
                id: AppPlayerHeaderSlot.header,
                child: KeyedSubtree(
                  key: const ValueKey('player-track-header'),
                  child: AnimatedBuilder(
                    key: artworkKeys.header,
                    animation: artworkForeground,
                    builder: (context, _) => _trackHeader(
                      context,
                      foreground('header'),
                      compactProgress: progress,
                    ),
                  ),
                ),
              ),
              LayoutId(id: AppPlayerHeaderSlot.controls, child: controls!),
              if (options != null)
                LayoutId(
                  id: AppPlayerHeaderSlot.lyricsOptions,
                  child: hideControls(options),
                ),
            ],
          ),
          child: hideControls(
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                controls(),
                SizedBox(height: volumeGap - transportShift),
                AnimatedBuilder(
                  animation: artworkForeground,
                  builder: (context, _) => AppVolumeControl(
                    key: artworkKeys.volume,
                    foreground: foreground('volume').onSurface,
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        );

        // Controls keep their intrinsic height. Small portrait screens and
        // large accessibility text can scroll instead of clipping the volume.
        final minHeight = 480.0 + (scale - 1).clamp(0, 3) * 120;
        if (constraints.maxHeight < minHeight) {
          return SingleChildScrollView(
            child: SizedBox(height: minHeight, child: content()),
          );
        }
        return content();
      },
    );
    if (PlayerTrackSwipe.hasScope(context)) return body;
    return PlayerTrackSwipe(
      queue: queue,
      currentIndex: currentIndex,
      onSelected: (item) async {
        final latest = ref.read(playQueueProvider).value ?? const <MediaItem>[];
        final index = latest.indexWhere((entry) => identical(entry, item));
        if (index >= 0) await controller.jumpTo(index);
      },
      child: body,
    );
  }
}
