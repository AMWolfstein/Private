part of 'now_playing_screen.dart';

extension _NowPlayingPlayer on _NowPlayingScreenState {
  static String? _coverSource(MediaItem item) {
    final art = item.artUri;
    return art?.scheme == 'file' ? art!.toFilePath() : art?.toString();
  }

  Widget _buildPlayer(BuildContext context) {
    final immersive =
        !_landscape &&
        ref.watch(
          themeProvider.select(
            (settings) => settings.playerView == PlayerView.immersive,
          ),
        );
    final colorScheme = AppTheme.fromContext(
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
            data: AppTheme.fromContext(context, brightness: Brightness.dark),
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
                child: AppPlayerLayout(
                  mediaItem: mediaItem,
                  metadata: _trackMetadata,
                  seekPreview: _seekPreview,
                  colorScheme: colorScheme,
                  page: _currentPage,
                  motionArtwork: AlbumKenBurns(
                    active: _currentPage == 0,
                    child: artwork(),
                  ),
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
                  onPageChanged: _setAppPage,
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
                              onPressed: _toggleAppLyrics,
                            ),
                            AudioOutputButton(
                              color: Colors.white,
                              onPickerChanged: (open) {
                                if (!mounted) return;
                                _rebuild(() => _audioOutputOpen = open);
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
                                  _setAppPage(_currentPage == 2 ? 0 : 2),
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
          data: AppTheme.fromContext(context, brightness: Brightness.dark),
          // The player's menus and sheets draw their glass from this ground.
          child: AppPlayerGround(
            source: _coverSource(mediaItem),
            immersive: immersive,
            showArtwork: _currentPage == 0,
            artworkAspectRatio: artworkRatio,
            fadeStart: immersive ? .72 : .58,
            insetArtworkKey: _expandedArtworkKey,
            child: Stack(
              fit: StackFit.expand,
              children: [
                AppArtworkContrast(
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
                  child: AppPlayerBackground(
                    artUri: mediaItem.artUri,
                    squareArtwork: !immersive,
                    artworkAspectRatio: artworkRatio,
                    fadeStart: immersive ? .72 : .58,
                    showArtwork: _currentPage == 0,
                    // The background fades this cover, then drifts it.
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
}
