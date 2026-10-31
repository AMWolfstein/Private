part of 'album_detail_header.dart';

extension AlbumDetailHeaderPart2 on AlbumDetailHeader {
  /// Keep the toolbar at the collection scroll-view level so it stays pinned
  /// after the dynamically sized artwork and metadata have scrolled away.
  List<Widget> buildSlivers(BuildContext context) {
    if ((coverBuilder == null && !immersive)) {
      return [this];
    }
    final scheme = Theme.of(context).colorScheme;
    final screenSize = MediaQuery.sizeOf(context);
    final artworkSize = math.min(
      screenSize.width.clamp(0.0, 440.0),
      math.max(240.0, screenSize.height * 0.55),
    );
    final details = _buildAppDetails(context);
    Widget toolbar({bool collapsed = true}) => Consumer(
      builder: (context, ref, _) {
        final opaque =
            appHeaderMaterial(context, ref) == AppHeaderMaterial.opaque;
        final titleVisible =
            showTitleInAppBar ||
            appBarTitle != null ||
            (immersive && collapsed);
        final overArtwork = immersive && !collapsed;
        return _ArtworkBrightness(
          source: overArtwork ? paletteSource : null,
          builder: (context, artwork) => AppHeaderBrightness(
            brightness: artwork,
            child: SliverAppBar(
              pinned: true,
              backgroundColor: opaque && collapsed
                  ? scheme.surface
                  : Colors.transparent,
              surfaceTintColor: Colors.transparent,
              scrolledUnderElevation: 0,
              // Without artwork data the transparent toolbar keeps the light
              // status icons it always had over the cover.
              systemOverlayStyle: appHeaderOverlayStyle(
                artwork ?? (overArtwork ? Brightness.dark : scheme.brightness),
              ),
              flexibleSpace: opaque
                  ? null
                  : AppHeaderBacking(visible: immersive ? titleVisible : null),
              title: AnimatedOpacity(
                opacity: titleVisible ? 1 : 0,
                duration: const Duration(milliseconds: 180),
                // The only app bar title is the "N selected" counter, which
                // has to be announced whenever the selection changes.
                child: Semantics(
                  liveRegion: appBarTitle != null,
                  container: appBarTitle != null,
                  child: Text(
                    appBarTitle ?? title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              leadingWidth: kToolbarHeight,
              leading: AppHeaderControls(
                child:
                    leading ??
                    HeaderCircleButton(
                      icon: CupertinoIcons.back,
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).backButtonTooltip,
                      onPressed: () => Navigator.pop(context),
                    ),
              ),
              actionsPadding: EdgeInsetsDirectional.only(
                end: kAppHeaderEdgeGap,
              ),
              actions: [AppHeaderActions(actions: appBarActions ?? const [])],
            ),
          ),
        );
      },
    );
    if (immersive) {
      final detailsTop = (artworkSize - 20).clamp(0.0, double.infinity);
      final gradient = [
        Colors.black.withValues(alpha: 0.12),
        scheme.surface.withValues(alpha: 0),
        scheme.surface,
      ];
      // The header controls' ground: the cover under this gradient.
      final artwork = AppGroundAnchor(
        layout: AppGroundLayout(stops: const [0, 0.48, 1], colors: gradient),
        child: Stack(
          fit: StackFit.expand,
          children: [
            background,
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.48, 1],
                  colors: gradient,
                ),
              ),
            ),
            Positioned.fill(child: _AlbumScrollVeil(artworkBottom: detailsTop)),
          ],
        ),
      );
      return [
        // The toolbar paints above the header without reserving a second
        // status-bar inset. Metadata still has its natural, scrollable height.
        SliverLayoutBuilder(
          builder: (context, constraints) {
            final toolbarHeight =
                kToolbarHeight + MediaQuery.paddingOf(context).top;
            return _AlbumOverlayToolbar(
              child: toolbar(
                collapsed:
                    constraints.scrollOffset >= detailsTop - toolbarHeight,
              ),
            );
          },
        ),
        SliverToBoxAdapter(
          child: Stack(
            alignment: Alignment.topCenter,
            children: [
              Positioned.fill(
                child: squareArtwork
                    ? Align(
                        alignment: Alignment.topCenter,
                        child: SizedBox.square(
                          dimension: artworkSize,
                          child: _AlbumStretchArtwork(child: artwork),
                        ),
                      )
                    : _AlbumStretchArtwork(child: artwork),
              ),
              Column(
                children: [
                  SizedBox(height: detailsTop),
                  details,
                ],
              ),
            ],
          ),
        ),
      ];
    }
    return [
      Builder(builder: (_) => toolbar()),
      SliverToBoxAdapter(child: details),
    ];
  }
}
