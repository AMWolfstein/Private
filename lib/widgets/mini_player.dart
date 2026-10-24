import 'package:flutter/gestures.dart' show DragStartBehavior;
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/theme/app_tokens.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/screens/now_playing_screen.dart';
import 'package:spotiflac_android/utils/string_utils.dart';
import 'package:spotiflac_android/widgets/audio_quality_badges.dart';
import 'package:spotiflac_android/widgets/overflow_marquee.dart';
import 'package:spotiflac_android/widgets/player_artwork.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key, this.compact = false, this.bottomPadding = 8});

  final bool compact;
  final double bottomPadding;

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  final _surfaceKey = GlobalKey();
  final _artworkKey = GlobalKey();

  Rect? _bounds(GlobalKey key) {
    final box = key.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final overlay = Navigator.of(
      context,
      rootNavigator: true,
    ).overlay?.context.findRenderObject();
    return MatrixUtils.transformRect(
      box.getTransformTo(overlay),
      Offset.zero & box.size,
    );
  }

  /// Upward travel of the current vertical drag, in logical pixels.
  double _dragUp = 0;

  void _openNowPlaying() {
    Navigator.of(context, rootNavigator: true).push(
      NowPlayingRoute(
        child: const NowPlayingScreen(),
        miniPlayerGeometry: () {
          if (!mounted) return null;
          final surface = _bounds(_surfaceKey);
          final artwork = _bounds(_artworkKey);
          if (surface == null || artwork == null) return null;
          return (surface: surface, artwork: artwork);
        },
      ),
    );
  }

  // Opens on release rather than under the finger: pushing a route cancels
  // every active pointer, so the drag could not keep steering the page.
  void _onVerticalDragEnd(DragEndDetails details) {
    final travel = _dragUp;
    _dragUp = 0;
    final velocity = -(details.primaryVelocity ?? 0);
    if (velocity > 300 || (velocity >= 0 && travel > 48)) _openNowPlaying();
  }

  // Hides the bar in the frames between a swipe-dismiss and the stopped
  // service clearing the media item (a dismissed Dismissible must leave the
  // tree immediately). Playing the same track again shows the bar normally.
  String? _dismissedItemId;
  bool _dismissalSawPause = false;

  @override
  Widget build(BuildContext context) {
    final mediaItem = ref.watch(currentMediaItemProvider).value;
    if (mediaItem == null) {
      _dismissedItemId = null;
      return const SizedBox.shrink();
    }

    final isPlaying = ref.watch(playbackPlayingProvider);
    final isLoading = ref.watch(playbackLoadingProvider);
    if (mediaItem.id != _dismissedItemId || (_dismissalSawPause && isPlaying)) {
      _dismissedItemId = null;
    }
    if (mediaItem.id == _dismissedItemId) {
      if (!isPlaying) _dismissalSawPause = true;
      return const SizedBox.shrink();
    }

    final controller = ref.read(musicPlayerControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    final compact = widget.compact;
    // Frosted and flat glass levels run on constrained Android hardware. They
    // skip keeping a paused video decoder for the full player's motion cover,
    // and stop the title marquee after a few passes: every marquee frame
    // re-filters the blurred chrome around it.
    final fullEffects = ref.watch(mornyeLiquidGlassProvider);
    final marqueeCycles = fullEffects ? null : 2;

    final player = Dismissible(
      key: ValueKey('mini-player-${mediaItem.id}'),
      direction: DismissDirection.horizontal,
      onDismissed: (_) {
        setState(() {
          _dismissedItemId = mediaItem.id;
          _dismissalSawPause = !isPlaying;
        });
        controller.stop();
      },
      child: DecoratedBox(
        key: _surfaceKey,
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(border: null),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: _openNowPlaying,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...[],
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 8 : 12,
                    vertical: 0,
                  ),
                  child: Row(
                    children: [
                      Hero(
                        tag: kNowPlayingArtworkHeroTag,
                        child: ClipRRect(
                          key: _artworkKey,
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: context.tokens.coverMini,
                            height: context.tokens.coverMini,
                            child: PlayerArtwork(
                              artUri: mediaItem.artUri?.toString(),
                              colorScheme: colorScheme,
                              cacheWidth: 132,
                              iconSize: 22,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(width: compact ? 8 : 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            OverflowMarquee(
                              resetKey: (mediaItem.id, mediaItem.title),
                              maxCycles: marqueeCycles,
                              child: ExplicitTrackTitle(
                                title: mediaItem.title,
                                explicit:
                                    parseExplicitFlag(
                                      mediaItem.extras?['explicit'],
                                    ) ==
                                    true,
                                style: Theme.of(context).textTheme.titleSmall
                                    ?.copyWith(fontWeight: FontWeight.w600),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            OverflowMarquee(
                              resetKey: (mediaItem.id, mediaItem.artist),
                              maxCycles: marqueeCycles,
                              child: Text(
                                mediaItem.artist ?? '',
                                style: Theme.of(context).textTheme.bodySmall
                                    ?.copyWith(
                                      color: Color.lerp(
                                        colorScheme.onSurfaceVariant,
                                        colorScheme.onSurface,
                                        colorScheme.brightness ==
                                                Brightness.dark
                                            ? 0.7
                                            : 0.6,
                                      ),
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        color: colorScheme.onSurface,
                        tooltip: isPlaying
                            ? context.l10n.actionPause
                            : context.l10n.tooltipPlay,
                        icon: isLoading
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.5,
                                ),
                              )
                            : Icon(
                                (isPlaying
                                    ? CupertinoIcons.pause_fill
                                    : CupertinoIcons.play_fill),
                              ),
                        onPressed: isLoading
                            ? null
                            : () => controller.togglePlayPause(isPlaying),
                      ),
                      if (!compact)
                        IconButton(
                          color: colorScheme.onSurface,
                          tooltip: context.l10n.nowPlayingNextTrack,
                          icon: Icon(CupertinoIcons.forward_fill),
                          onPressed: controller.next,
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    // Swiping up opens the full player; sideways swipes still dismiss.
    final swipeable = GestureDetector(
      // Measure from touch-down so the slop counts toward the swipe.
      dragStartBehavior: DragStartBehavior.down,
      onVerticalDragStart: (_) => _dragUp = 0,
      onVerticalDragUpdate: (details) => _dragUp -= details.primaryDelta ?? 0,
      onVerticalDragEnd: _onVerticalDragEnd,
      child: player,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: widget.bottomPadding),
      child: MornyeGlass.navigation(
        strongTint: true,
        tintOpacity: MornyeTheme.chromeOpacity(context),
        blurEnabled: ref.watch(mornyeBlurEnabledProvider),
        child: swipeable,
      ),
    );
  }
}
