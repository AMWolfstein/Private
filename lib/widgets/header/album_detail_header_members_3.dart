part of 'album_detail_header.dart';

extension _AlbumDetailHeaderPart3 on AlbumDetailHeader {
  Widget _buildAppDetails(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, immersive ? 0 : 20, 20, 28),
    child: Column(
      children: [
        if (!immersive)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: AspectRatio(
              aspectRatio: 1,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.16),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                // The cover scrolls under the header controls' glass.
                child: AppGroundAnchor(
                  layout: const AppGroundLayout(radius: 14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(14),
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          coverBuilder!(context, constraints.maxWidth),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!immersive) const SizedBox(height: 22),
        Text(
          title,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w700,
          ),
        ),
        if (subtitle != null) ...[const SizedBox(height: 5), subtitle!],
        if (meta != null) ...[const SizedBox(height: 5), meta!],
        if (actions != null) ...[
          SizedBox(height: immersive ? 16 : 24),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: actions!,
          ),
        ],
      ],
    ),
  );
  Widget _buildAppBar(BuildContext context, ColorScheme headerScheme) {
    final tokens = context.tokens;
    final plainArtworkHeader = coverBuilder != null;
    // Scrim and gradient are drawn from the palette surface instead of black,
    // so a light theme gets a light header with dark text and a dark theme
    // keeps the familiar dark treatment — both tinted by the artwork.
    final scrimColor = headerScheme.surface;
    final onHeader = headerScheme.onSurface;

    return SliverAppBar(
      expandedHeight: expandedHeight,
      pinned: true,
      stretch: true,
      backgroundColor: backgroundColor ?? headerScheme.surface,
      surfaceTintColor: Colors.transparent,
      title: AnimatedOpacity(
        duration: tokens.motionFast,
        opacity: showTitleInAppBar ? 1.0 : 0.0,
        child: Text(
          appBarTitle ?? title,
          style: TextStyle(
            color: onHeader,
            fontWeight: FontWeight.w600,
            fontSize: 16,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          final collapseRatio =
              (constraints.maxHeight - kToolbarHeight) /
              (expandedHeight - kToolbarHeight);
          final showContent = collapseRatio > 0.3;

          return FlexibleSpaceBar(
            collapseMode: CollapseMode.pin,
            background: Stack(
              fit: StackFit.expand,
              children: [
                if (plainArtworkHeader)
                  ColoredBox(color: headerScheme.surface)
                else if (blurAndScrimBackground)
                  ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 32, sigmaY: 32),
                    child: background,
                  )
                else
                  background,
                if (!plainArtworkHeader && blurAndScrimBackground)
                  ColoredBox(color: scrimColor.withValues(alpha: 0.4)),
                if (!plainArtworkHeader)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: expandedHeight * 0.65,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            scrimColor.withValues(alpha: 0),
                            scrimColor.withValues(alpha: 0.92),
                          ],
                        ),
                      ),
                    ),
                  ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 40,
                  child: AnimatedOpacity(
                    duration: tokens.motionFast,
                    opacity: showContent ? 1.0 : 0.0,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (coverBuilder != null) ...[
                          Builder(
                            builder: (context) {
                              final toolbarBottom =
                                  MediaQuery.paddingOf(context).top +
                                  kToolbarHeight;
                              final detailsHeight =
                                  40 +
                                  20 +
                                  58 +
                                  (subtitle == null ? 0 : 28) +
                                  (meta == null ? 0 : 34) +
                                  (actions == null ? 0 : 64);
                              final coverSize = math.min(
                                (constraints.maxWidth * 0.5).clamp(
                                  150.0,
                                  210.0,
                                ),
                                math.max(
                                  96.0,
                                  expandedHeight -
                                      toolbarBottom -
                                      detailsHeight,
                                ),
                              );
                              return Container(
                                width: coverSize,
                                height: coverSize,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(
                                    plainArtworkHeader
                                        ? tokens.radiusCover
                                        : tokens.radiusControl,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: headerScheme.shadow.withValues(
                                        alpha: 0.45,
                                      ),
                                      blurRadius: 24,
                                      offset: const Offset(0, 8),
                                    ),
                                  ],
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(
                                    tokens.radiusControl,
                                  ),
                                  child: coverBuilder!(context, coverSize),
                                ),
                              );
                            },
                          ),
                          const SizedBox(height: 20),
                        ],
                        Text(
                          title,
                          style: TextStyle(
                            color: onHeader,
                            fontSize: _titleFontSize(),
                            fontWeight: FontWeight.bold,
                            height: 1.2,
                          ),
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 6),
                          subtitle!,
                        ],
                        if (meta != null) ...[
                          const SizedBox(height: 12),
                          meta!,
                        ],
                        if (actions != null) ...[
                          const SizedBox(height: 16),
                          actions!,
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
            stretchModes: const [StretchMode.zoomBackground],
          );
        },
      ),
      leadingWidth: kToolbarHeight,
      leading:
          leading ??
          IconButton.filledTonal(
            tooltip: MaterialLocalizations.of(context).backButtonTooltip,
            icon: Icon(Icons.chevron_left),
            style: IconButton.styleFrom(
              minimumSize: Size.square(tokens.minTouchTarget),
              backgroundColor: headerScheme.surfaceContainerHigh.withValues(
                alpha: 0.75,
              ),
              foregroundColor: headerScheme.onSurfaceVariant,
            ),
            onPressed: () => Navigator.pop(context),
          ),
      actions: appBarActions,
    );
  }
}
