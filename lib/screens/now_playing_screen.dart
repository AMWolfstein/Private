import 'package:sistrum/screens/equalizer_screen.dart';
import 'package:sistrum/screens/lyrics_share_screen.dart';
import 'package:sistrum/utils/lyrics_parser.dart';
import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart' show SystemUiOverlayStyle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sistrum/controllers/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/theme_provider.dart';
import 'package:sistrum/models/theme_settings.dart';
import 'package:sistrum/routes/now_playing_route.dart';
import 'package:sistrum/screens/local_album_screen.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/utils/clickable_metadata.dart';
import 'package:sistrum/utils/playback_seek_preview.dart';
import 'package:sistrum/utils/logger.dart';
import 'package:sistrum/widgets/app_bottom_sheet.dart';
import 'package:sistrum/widgets/audio_output_button.dart';
import 'package:sistrum/widgets/lyrics_screen_awake.dart';
import 'package:sistrum/widgets/player/player_artwork.dart';
import 'package:sistrum/widgets/player/player_track_swipe.dart';
import 'package:sistrum/widgets/player/player_gesture_regions.dart';
import 'package:sistrum/widgets/player/player_details_sheet.dart';
import 'package:sistrum/widgets/player/sistrum_player_layout.dart';
import 'package:sistrum/widgets/player/player_lyrics_controls.dart';
import 'package:sistrum/widgets/player/player_lyrics_section.dart';
import 'package:sistrum/widgets/playlist_picker_sheet.dart';
import 'package:sistrum/widgets/settings_group.dart';
import 'package:sistrum/widgets/player/sistrum_player_background.dart';
import 'package:sistrum/widgets/player/sistrum_player_ground.dart';
import 'package:sistrum/widgets/glass/sistrum_artwork_contrast.dart';
import 'package:sistrum/widgets/player/sistrum_player_actions_sheet.dart';
import 'package:sistrum/widgets/sistrum_context_menu.dart';

export 'package:sistrum/routes/now_playing_route.dart';

final _log = AppLogger('NowPlaying');

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key, this.metadataControllerFactory});

  final PlayerMetadataController Function()? metadataControllerFactory;

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> {
  ProviderSubscription<AsyncValue<MediaItem?>>? _mediaItemSub;
  ProviderSubscription<bool>? _lyricsPlayingSub;
  late final _trackMetadata =
      widget.metadataControllerFactory?.call() ?? PlayerMetadataController();
  int _currentPage = 0;
  bool _landscape = false;

  bool _lyricsControlsHidden = false;
  bool _lyricsOptionsOpen = false;
  bool _audioOutputOpen = false;
  bool _sharingLyrics = false;
  double _lyricsScrollDistance = 0;
  Timer? _lyricsIdleTimer;
  final _lyricsPointers = <int, Offset>{};
  bool _lyricsPointerMoved = false;
  final _artworkHeaderKey = GlobalKey();
  final _artworkControlsKey = GlobalKey();
  final _artworkVolumeKey = GlobalKey();
  final _expandedArtworkKey = GlobalKey();
  final _immersiveArtworkKey = GlobalKey();
  final _compactArtworkKey = GlobalKey();
  final _artworkForeground = ValueNotifier<Map<String, Color>>({});
  final _seekPreview = PlaybackSeekPreview();
  NowPlayingRoute? _artworkRoute;

  @override
  void initState() {
    super.initState();
    _mediaItemSub = ref.listenManual<AsyncValue<MediaItem?>>(
      currentMediaItemProvider,
      (previous, next) {
        if (previous?.value?.id != next.value?.id) _seekPreview.reset();
        unawaited(
          _trackMetadata.load(
            next.value,
            inspectUnresolvedContentUri: _currentPage == 1,
          ),
        );
      },
    );
    _lyricsPlayingSub = ref.listenManual<bool>(playbackPlayingProvider, (
      previous,
      playing,
    ) {
      if (!playing && _lyricsControlsHidden) {
        setState(() => _lyricsControlsHidden = false);
      }
      _scheduleLyricsControlsHide();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_trackMetadata.load(ref.read(currentMediaItemProvider).value));
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final size = MediaQuery.sizeOf(context);
    _landscape = size.width > size.height;
    if (_landscape || MediaQuery.accessibleNavigationOf(context)) {
      _lyricsControlsHidden = false;
    }
    _scheduleLyricsControlsHide();
  }

  @override
  void dispose() {
    _artworkRoute?.readArtwork = null;
    _lyricsIdleTimer?.cancel();
    _mediaItemSub?.close();
    _lyricsPlayingSub?.close();
    _trackMetadata.dispose();
    _artworkForeground.dispose();
    _seekPreview.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LyricsScreenAwake(
      visible:
          _currentPage == 1 &&
          ref.watch(currentMediaItemProvider).value != null,
      child: _buildPlayer(context),
    );
  }

  Widget _buildPlayer(BuildContext context) {
    final immersive =
        !_landscape &&
        ref.watch(
          themeProvider.select(
            (settings) => settings.playerView == PlayerView.immersive,
          ),
        );
    final colorScheme = SistrumTheme.fromContext(
      context,
      brightness: Brightness.dark,
    ).colorScheme;
    final mediaItem = ref.watch(currentMediaItemProvider).value;

    if (mediaItem == null) {
      return Scaffold(
        appBar: AppBar(
          leading: IconButton(
            tooltip: context.l10n.nowPlayingMinimize,
            icon: const Icon(Icons.keyboard_arrow_down),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(child: Text(context.l10n.nowPlayingNothingPlaying)),
      );
    }

    // Kept alive while the track shows, so the ⋯ menu opens with its final
    // Loved state instead of rebuilding mid-flight after a fresh lookup.
    ref.listen(playerCollectionTrackProvider(mediaItem), (_, _) {});

    final screen = MediaQuery.sizeOf(context);
    final artworkRatio = immersive && screen.height > 0
        ? (screen.width / (screen.height * .56)).clamp(.5, 1.0)
        : null;

    Widget artwork() => Align(
      alignment: Alignment.topCenter,
      child: AspectRatio(
        aspectRatio: 1,
        child: PlayerArtwork(
          artUri: mediaItem.artUri?.toString(),
          colorScheme: colorScheme,
          cacheWidth: PlayerArtwork.transitionCacheWidth(context),
        ),
      ),
    );

    // The Sistrum route moves the entire player together. A second,
    // delayed content fade would make dismissal appear to pause partway down.
    final route = ModalRoute.of(context);

    if (_artworkRoute != route) {
      _artworkRoute?.readArtwork = null;
      _artworkRoute = null;
    }
    if (route is NowPlayingRoute) {
      _artworkRoute = route;
      route.readArtwork = () {
        final key = _landscape
            ? _expandedArtworkKey
            : _currentPage != 0
            ? _compactArtworkKey
            : immersive
            ? _immersiveArtworkKey
            : _expandedArtworkKey;
        final box = key.currentContext?.findRenderObject();
        if (box is! RenderBox || !box.attached || !box.hasSize) return null;
        final overlay = route.navigator?.overlay?.context.findRenderObject();
        return (
          bounds: MatrixUtils.transformRect(
            box.getTransformTo(overlay),
            Offset.zero & box.size,
          ),
          fullBleed: immersive && _currentPage == 0,
          child: Theme(
            data: SistrumTheme.fromContext(
              context,
              brightness: Brightness.dark,
            ),
            child: key == _compactArtworkKey || immersive
                ? PlayerArtwork(
                    artUri: mediaItem.artUri?.toString(),
                    colorScheme: colorScheme,
                    cacheWidth: PlayerArtwork.transitionCacheWidth(context),
                  )
                : artwork(),
          ),
        );
      };
    }
    final player = Scaffold(
      backgroundColor: Colors.transparent,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: colorScheme.onSurface,
        surfaceTintColor: Colors.transparent,
        systemOverlayStyle: SystemUiOverlayStyle.light,
        toolbarHeight:
            (MediaQuery.orientationOf(context) == Orientation.landscape
            ? 0
            : 48),
        automaticallyImplyLeading: false,
        title: MediaQuery.orientationOf(context) == Orientation.landscape
            ? null
            : IconButton(
                tooltip: context.l10n.nowPlayingMinimize,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: Container(
                  width: 36,
                  height: 5,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
        centerTitle: true,
        leading: null,
        actions: null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: NotificationListener<ScrollUpdateNotification>(
                onNotification: _onLyricsScroll,
                child: SistrumPlayerLayout(
                  mediaItem: mediaItem,
                  metadata: _trackMetadata,
                  seekPreview: _seekPreview,
                  colorScheme: colorScheme,
                  page: _currentPage,
                  motionArtwork: artwork(),
                  insetArtwork: !immersive,
                  artworkAspectRatio: artworkRatio,
                  artworkTopInset: MediaQuery.paddingOf(context).top + 48,
                  artworkKeys: (
                    header: _artworkHeaderKey,
                    controls: _artworkControlsKey,
                    volume: _artworkVolumeKey,
                    expanded: _expandedArtworkKey,
                    compact: _compactArtworkKey,
                  ),
                  artworkForeground: _artworkForeground,
                  lyricsControlsHidden: _lyricsControlsHidden,
                  lyricsOptionsOpen: _lyricsOptionsOpen,
                  lyricsBuilder: (showOptions) => _lyricsSection(
                    colorScheme,
                    isActive: _currentPage == 1,
                    showOptions: showOptions,
                  ),
                  lyricsOptions: _lyricsOptionsButton(colorScheme),
                  onPageChanged: _setSistrumPage,
                  onTrackNavigation: _showTrackNavigationMenu,
                  onMoreActions: (buttonContext, item, anchor) =>
                      _showMoreActions(
                        context: buttonContext,
                        mediaItem: item,
                        source: item.extras?['source']?.toString() ?? '',
                        colorScheme: colorScheme,
                        anchor: anchor,
                      ),
                ),
              ),
            ),
            _autoHidingLyricsControls(
              PlayerQueueSwipeRegion(
                onOpenQueue: () => _showQueueSheet(colorScheme),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!_landscape)
                      FractionallySizedBox(
                        widthFactor: 0.72,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton(
                              tooltip: _currentPage == 1
                                  ? context.l10n.nowPlayingTabPlayer
                                  : context.l10n.nowPlayingTabLyrics,
                              isSelected: _currentPage == 1,
                              color: Colors.white,
                              style: IconButton.styleFrom(
                                backgroundColor: _currentPage == 1
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : Colors.transparent,
                              ),
                              icon: const Icon(CupertinoIcons.quote_bubble),
                              onPressed: _toggleSistrumLyrics,
                            ),
                            AudioOutputButton(
                              color: Colors.white,
                              onPickerChanged: (open) {
                                if (!mounted) return;
                                setState(() => _audioOutputOpen = open);
                                _scheduleLyricsControlsHide();
                              },
                            ),
                            IconButton(
                              tooltip: context.l10n.nowPlayingUpNext,
                              color: Colors.white,
                              isSelected: _currentPage == 2,
                              style: IconButton.styleFrom(
                                backgroundColor: _currentPage == 2
                                    ? Colors.white.withValues(alpha: 0.16)
                                    : Colors.transparent,
                              ),
                              icon: const Icon(CupertinoIcons.list_bullet),
                              onPressed: () =>
                                  _setSistrumPage(_currentPage == 2 ? 0 : 2),
                            ),
                          ],
                        ),
                      )
                    else
                      ...[],
                    if (!_landscape) const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );

    final swipeQueue =
        ref.watch(playQueueProvider).value ?? const <MediaItem>[];
    final reportedIndex = ref.watch(
      playbackStateProvider.select((state) => state.value?.queueIndex),
    );
    final swipeIndex =
        reportedIndex != null &&
            reportedIndex >= 0 &&
            reportedIndex < swipeQueue.length &&
            swipeQueue[reportedIndex].id == mediaItem.id
        ? reportedIndex
        : swipeQueue.indexWhere((entry) => entry.id == mediaItem.id);
    return PlayerTrackSwipe(
      queue: swipeQueue,
      currentIndex: swipeIndex,
      onSelected: (item) async {
        final latest = ref.read(playQueueProvider).value ?? const <MediaItem>[];
        final index = latest.indexWhere((entry) => identical(entry, item));
        if (index >= 0) {
          await ref.read(musicPlayerControllerProvider).jumpTo(index);
        }
      },
      child: HeroMode(
        // A route Hero renders outside the panel's gradient and slide, briefly
        // exposing a detached rectangle. Keep Sistrum artwork inside its panel.
        enabled: false,
        child: Theme(
          data: SistrumTheme.fromContext(context, brightness: Brightness.dark),
          // The player's menus and sheets draw their glass from this ground.
          child: SistrumPlayerGround(
            source: _coverSource(mediaItem),
            immersive: immersive,
            showArtwork: _currentPage == 0,
            artworkAspectRatio: artworkRatio,
            fadeStart: immersive ? .72 : .58,
            insetArtworkKey: _expandedArtworkKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                SistrumArtworkContrast(
                  enabled: false,
                  targets: {
                    'header': _artworkHeaderKey,
                    'controls': _artworkControlsKey,
                    'volume': _artworkVolumeKey,
                  },
                  onChanged: (colors) {
                    if (!mounted) return;
                    _artworkForeground.value = colors;
                  },
                  child: SistrumPlayerBackground(
                    artUri: mediaItem.artUri,
                    squareArtwork: !immersive,
                    artworkAspectRatio: artworkRatio,
                    fadeStart: immersive ? .72 : .58,
                    showArtwork: _currentPage == 0,
                    artwork: immersive
                        ? PlayerArtworkDragRegion(
                            child: PlayerTransitionArtwork(
                              artworkKey: _immersiveArtworkKey,
                              child: Hero(
                                tag: kNowPlayingArtworkHeroTag,
                                child: PlayerArtwork(
                                  artUri: mediaItem.artUri?.toString(),
                                  colorScheme: colorScheme,
                                  cacheWidth:
                                      PlayerArtwork.transitionCacheWidth(
                                        context,
                                      ),
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
                ),
                Listener(
                  behavior: HitTestBehavior.translucent,
                  onPointerDown: (event) {
                    if (!_canAutoHideLyricsControls) return;
                    if (_lyricsPointers.isEmpty) _lyricsPointerMoved = false;
                    _lyricsPointers[event.pointer] = event.position;
                    _lyricsIdleTimer?.cancel();
                  },
                  onPointerMove: (event) {
                    final origin = _lyricsPointers[event.pointer];
                    if (origin != null &&
                        (event.position - origin).distance > 12) {
                      _lyricsPointerMoved = true;
                    }
                  },
                  onPointerUp: (event) => _endLyricsInteraction(event.pointer),
                  onPointerCancel: (event) =>
                      _endLyricsInteraction(event.pointer, cancelled: true),
                  child: player,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  static String? _coverSource(MediaItem item) {
    final art = item.artUri;
    return art?.scheme == 'file' ? art!.toFilePath() : art?.toString();
  }

  void _toggleSistrumLyrics() {
    _setSistrumPage(_currentPage == 1 ? 0 : 1);
  }

  void _setSistrumPage(int page) {
    setState(() {
      _currentPage = page;
      _lyricsControlsHidden = false;
      _lyricsScrollDistance = 0;
    });
    _scheduleLyricsControlsHide();
    if (_currentPage == 1) {
      unawaited(
        _trackMetadata.load(
          ref.read(currentMediaItemProvider).value,
          inspectUnresolvedContentUri: true,
        ),
      );
    }
  }

  bool get _canAutoHideLyricsControls =>
      !_landscape &&
      _currentPage == 1 &&
      ref.read(playbackPlayingProvider) &&
      !MediaQuery.accessibleNavigationOf(context);

  void _scheduleLyricsControlsHide() {
    _lyricsIdleTimer?.cancel();
    if (!_canAutoHideLyricsControls ||
        _lyricsOptionsOpen ||
        _audioOutputOpen ||
        _lyricsControlsHidden ||
        _lyricsPointers.isNotEmpty) {
      return;
    }
    _lyricsIdleTimer = Timer(const Duration(seconds: 5), () {
      if (!mounted || !_canAutoHideLyricsControls) return;
      if (ModalRoute.of(context)?.isCurrent == false) {
        _scheduleLyricsControlsHide();
        return;
      }
      setState(() => _lyricsControlsHidden = true);
    });
  }

  void _endLyricsInteraction(int pointer, {bool cancelled = false}) {
    if (_lyricsPointers.remove(pointer) == null || _lyricsPointers.isNotEmpty) {
      return;
    }
    if (!cancelled && !_lyricsPointerMoved && _lyricsControlsHidden) {
      setState(() => _lyricsControlsHidden = false);
    }
    _scheduleLyricsControlsHide();
  }

  bool _onLyricsScroll(ScrollUpdateNotification notification) {
    if (_currentPage != 1 ||
        _landscape ||
        notification.dragDetails == null ||
        notification.metrics.axis != Axis.vertical) {
      return false;
    }
    final delta = notification.scrollDelta ?? 0;
    if (delta.sign != _lyricsScrollDistance.sign) _lyricsScrollDistance = 0;
    _lyricsScrollDistance += delta;
    if (_lyricsScrollDistance.abs() >= 16) {
      final hidden = _lyricsScrollDistance > 0;
      if (hidden != _lyricsControlsHidden) {
        setState(() => _lyricsControlsHidden = hidden);
      }
      _lyricsScrollDistance = 0;
    }
    return false;
  }

  Widget _autoHidingLyricsControls(Widget child) =>
      PlayerLyricsControlsVisibility(
        hidden: _currentPage == 1 && _lyricsControlsHidden && !_landscape,
        child: child,
      );

  Widget _lyricsSection(
    ColorScheme colorScheme, {
    required bool isActive,
    bool showOptions = true,
  }) => PlayerLyricsSection(
    metadata: _trackMetadata,
    seekPreview: _seekPreview,
    colorScheme: colorScheme,
    isActive: isActive,
    onShareLyrics: _shareLyrics,
    options: showOptions && isActive && !_landscape
        ? _autoHidingLyricsControls(_lyricsOptionsButton(colorScheme))
        : null,
  );

  Future<void> _shareLyrics([LyricLine? line]) async {
    if (_sharingLyrics) return;
    final mediaItem = ref.read(currentMediaItemProvider).value;
    if (mediaItem == null) return;
    _sharingLyrics = true;
    try {
      // The menu offers sharing before the lyrics page has read the file, so
      // read it now (including an unresolved document) and wait for parsing.
      if (_trackMetadata.lyrics.isEmpty) {
        await _trackMetadata.load(mediaItem, inspectUnresolvedContentUri: true);
        await _untilMetadataLoaded();
      }
      if (!mounted ||
          ref.read(currentMediaItemProvider).value?.id != mediaItem.id) {
        return;
      }
      if (_trackMetadata.lyrics.isEmpty) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text(context.l10n.nowPlayingNoLyrics)),
          );
        return;
      }
      await openLyricsShare(
        context,
        mediaItem: mediaItem,
        lyrics: _trackMetadata.lyrics,
        initial: line,
      );
    } finally {
      _sharingLyrics = false;
    }
  }

  /// Completes once a load already in flight (started elsewhere) finishes.
  Future<void> _untilMetadataLoaded() {
    if (!_trackMetadata.loading) return Future.value();
    final done = Completer<void>();
    void listener() {
      if (_trackMetadata.loading || done.isCompleted) return;
      _trackMetadata.removeListener(listener);
      done.complete();
    }

    _trackMetadata.addListener(listener);
    return done.future.timeout(
      const Duration(seconds: 10),
      onTimeout: () => _trackMetadata.removeListener(listener),
    );
  }

  Widget _lyricsOptionsButton(ColorScheme colorScheme) => ListenableBuilder(
    listenable: _trackMetadata,
    builder: (context, _) =>
        _buildLyricsOptionsButton(colorScheme) ?? const SizedBox.shrink(),
  );

  Widget? _buildLyricsOptionsButton(ColorScheme colorScheme) {
    if (_trackMetadata.loading || !_trackMetadata.lyrics.synced) return null;
    final pronunciation = _trackMetadata.lyrics.lines.any(
      (line) => line.romanization?.trim().isNotEmpty == true,
    );
    final translation = _trackMetadata.lyrics.lines.any(
      (line) => line.translation?.trim().isNotEmpty == true,
    );
    if (!pronunciation && !translation) return null;
    return Builder(
      builder: (buttonContext) => IconButton.filledTonal(
        key: const ValueKey('lyrics-language-options'),
        tooltip: context.l10n.nowPlayingLyricsLanguageOptions,
        icon: const Icon(Icons.translate_rounded),
        style: IconButton.styleFrom(
          foregroundColor: _lyricsOptionsOpen
              ? colorScheme.surface
              : colorScheme.onSurface,
          backgroundColor: colorScheme.onSurface.withValues(
            alpha: _lyricsOptionsOpen ? 0.85 : 0.16,
          ),
        ),
        onPressed: () => _showLyricsOptions(
          buttonContext,
          pronunciation: pronunciation,
          translation: translation,
        ),
      ),
    );
  }

  Future<void> _showLyricsOptions(
    BuildContext buttonContext, {
    required bool pronunciation,
    required bool translation,
  }) async {
    final settings = ref.read(settingsProvider);
    final l10n = context.l10n;
    final actions = <(String, String, IconData)>[
      if (pronunciation)
        (
          'pronunciation',
          settings.playerShowPronunciation
              ? l10n.nowPlayingHidePronunciation
              : l10n.nowPlayingShowPronunciation,
          settings.playerShowPronunciation
              ? Icons.voice_over_off_outlined
              : Icons.record_voice_over_outlined,
        ),
      if (translation)
        (
          'translation',
          settings.playerShowTranslation
              ? l10n.nowPlayingHideTranslation
              : l10n.nowPlayingShowTranslation,
          Icons.translate_rounded,
        ),
    ];
    _lyricsIdleTimer?.cancel();
    setState(() => _lyricsOptionsOpen = true);
    try {
      final anchor = sistrumMenuAnchor(buttonContext);
      var menuWidth = 240.0;
      for (final (_, label, _) in actions) {
        final painter = TextPainter(
          text: TextSpan(
            text: label,
            style: Theme.of(
              context,
            ).textTheme.bodyLarge?.copyWith(fontSize: 15),
          ),
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();
        if (painter.width + 80 > menuWidth) menuWidth = painter.width + 80;
        painter.dispose();
      }
      final action = await showSistrumContextMenu<String>(
        context: buttonContext,
        anchor: anchor,
        preferAbove: true,
        maxWidth: menuWidth,
        builder: (menuContext) => SistrumContextMenu(
          dense: true,
          groups: [
            [
              for (final (value, label, icon) in actions)
                SistrumMenuAction(
                  icon: icon,
                  label: label,
                  onPressed: () => Navigator.of(menuContext).pop(value),
                ),
            ],
          ],
        ),
      );
      if (!mounted) return;
      final notifier = ref.read(settingsProvider.notifier);
      if (action == 'pronunciation') {
        notifier.setPlayerShowPronunciation(!settings.playerShowPronunciation);
      } else if (action == 'translation') {
        notifier.setPlayerShowTranslation(!settings.playerShowTranslation);
      }
    } finally {
      if (mounted) {
        setState(() => _lyricsOptionsOpen = false);
        _scheduleLyricsControlsHide();
      }
    }
  }

  Future<void> _showTrackNavigationMenu(
    BuildContext titleContext,
    MediaItem mediaItem,
  ) async {
    final action = await showSistrumContextMenu<String>(
      context: titleContext,
      preferAbove: true,
      maxWidth: 280,
      builder: (_) => SistrumPlayerNavigationMenu(mediaItem: mediaItem),
    );
    if (!mounted) return;
    if (action == 'album') {
      await _goToCurrentAlbum(mediaItem: mediaItem);
    } else if (action == 'artist') {
      await _goToCurrentArtist(mediaItem);
    }
  }

  Future<void> _goToCurrentArtist(MediaItem mediaItem) async {
    await navigateToArtist(context, artistName: mediaItem.artist ?? '');
  }

  Future<void> _updatePlayerCollection(
    MediaItem item, {
    required bool favorite,
  }) async {
    try {
      final provider = playerCollectionTrackProvider(item);
      if (ref.read(provider).hasError) ref.invalidate(provider);
      final track = await ref.read(provider.future);
      if (!mounted) return;
      if (favorite) {
        await ref.read(libraryCollectionsProvider.notifier).toggleLoved(track);
      } else {
        await showAddTrackToPlaylistSheet(context, ref, track);
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.l10n.snackbarError(context.friendlyError(error)),
          ),
        ),
      );
    }
  }

  Future<void> _showMoreActions({
    required BuildContext context,
    required MediaItem mediaItem,
    required String source,
    required ColorScheme colorScheme,
    Rect? anchor,
  }) async {
    final controller = ref.read(musicPlayerControllerProvider);
    final sleepTimerEndsAt = controller.sleepTimerEndsAt;
    final sleepTimerSubtitle = sleepTimerEndsAt == null
        ? null
        : context.l10n.nowPlayingSleepTimerActive(
            MaterialLocalizations.of(
              context,
            ).formatTimeOfDay(TimeOfDay.fromDateTime(sleepTimerEndsAt)),
          );
    final action = await showSistrumContextMenu<String>(
      context: context,
      anchor: anchor,
      preferAbove: true,
      maxWidth: 280,
      builder: (_) => SistrumPlayerActionsSheet(
        mediaItem: mediaItem,
        sleepTimerSubtitle: sleepTimerSubtitle,
      ),
    );
    if (!mounted || !context.mounted) return;
    switch (action) {
      case 'favorite':
        await _updatePlayerCollection(mediaItem, favorite: true);
        break;
      case 'playlist':
        await _updatePlayerCollection(mediaItem, favorite: false);
        break;
      case 'artist':
        await _goToCurrentArtist(mediaItem);
        break;
      case 'share':
        await SharePlus.instance.share(
          ShareParams(
            text: '${mediaItem.title} — ${mediaItem.artist ?? ''}',
            sharePositionOrigin:
                anchor ??
                Rect.fromCenter(
                  center: MediaQuery.sizeOf(context).center(Offset.zero),
                  width: 1,
                  height: 1,
                ),
          ),
        );
        break;
      case 'album':
        await _goToCurrentAlbum(mediaItem: mediaItem);
        break;
      case 'shareLyrics':
        await _shareLyrics();
        break;
      case 'details':
        unawaited(
          showPlayerDetailsSheet(
            context,
            colorScheme,
            metadata: _trackMetadata,
            mediaItem: ref.read(currentMediaItemProvider).value,
          ),
        );
        break;
      case 'equalizer':
        await Navigator.of(context).push<void>(
          MaterialPageRoute(builder: (_) => const EqualizerScreen()),
        );
        break;
      case 'sleepTimer':
        await _showSleepTimerSheet(context, controller, colorScheme);
        break;
    }
  }

  Future<void> _showSleepTimerSheet(
    BuildContext context,
    MusicPlayerController controller,
    ColorScheme colorScheme,
  ) async {
    const durations = [15, 30, 45, 60];
    final isActive = controller.sleepTimerEndsAt != null;
    final selection = await showAppBottomSheet<String>(
      context: context,
      useRootNavigator: true,
      backgroundColor: colorScheme.surfaceContainerHigh,
      title: context.l10n.nowPlayingSleepTimer,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SettingsGroup(
          children: [
            for (final minutes in durations)
              SettingsItem(
                icon: Icons.timer_outlined,
                title: sheetContext.l10n.nowPlayingSleepTimerMinutes(minutes),
                showDivider: isActive || minutes != durations.last,
                onTap: () => Navigator.of(sheetContext).pop('$minutes'),
              ),
            if (isActive)
              SettingsItem(
                icon: Icons.timer_off_outlined,
                title: sheetContext.l10n.nowPlayingSleepTimerOff,
                showDivider: false,
                onTap: () => Navigator.of(sheetContext).pop('off'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || !context.mounted || selection == null) return;

    if (selection == 'off') {
      controller.cancelSleepTimer();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.nowPlayingSleepTimerCancelled)),
      );
      return;
    }

    final minutes = int.tryParse(selection);
    if (minutes == null) return;
    controller.setSleepTimer(Duration(minutes: minutes));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.nowPlayingSleepTimerSet(
            context.l10n.nowPlayingSleepTimerMinutes(minutes),
          ),
        ),
      ),
    );
  }

  Future<void> _goToCurrentAlbum({required MediaItem mediaItem}) async {
    final albumName = (mediaItem.album ?? '').trim();
    if (albumName.isEmpty) return;

    try {
      final album = await ref
          .read(musicPlayerControllerProvider)
          .localAlbumFor(mediaItem.id);
      if (!mounted) return;
      if (album != null) {
        final (:item, :tracks) = album;
        final albumArtist = (item.albumArtist ?? '').trim();
        pushViaPreferredNavigator(
          context,
          (_) => LocalAlbumScreen(
            albumName: item.albumName,
            artistName: albumArtist.isNotEmpty ? albumArtist : item.artistName,
            coverPath: item.coverPath,
            tracks: tracks,
          ),
        );
        return;
      }
    } catch (e) {
      _log.w('Failed to resolve local album: $e');
    }

    if (!mounted) return;
    await navigateToAlbum(
      context,
      albumName: albumName,
      artistName: mediaItem.artist,
      coverUrl: mediaItem.artUri?.toString(),
    );
  }

  void _showQueueSheet(ColorScheme colorScheme) {
    {
      _setSistrumPage(2);
      return;
    }
  }
}
