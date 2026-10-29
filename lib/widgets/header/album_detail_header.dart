import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxySliver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/cover_palette_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/library/cover_palette.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/widgets/glass/app_artwork_page_ground.dart';
import 'package:sistrum/widgets/glass/app_floating_header.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

part 'album_detail_header_parts.dart';

/// Collapsing album-detail header shared by the album and local-album
/// screens: full-bleed [background] (optionally blurred and
/// scrimmed), bottom gradient, centered square cover, title, optional
/// subtitle/meta/actions rows, and a circular back button. Content fades out
/// below 30% expansion; the [title] fades into the toolbar instead.
///
/// Colours come from a scheme derived from [paletteSource] (see [CoverPalette])
/// and are published to descendants through [HeaderPalette], so the header
/// follows both the artwork and the app's light/dark mode instead of assuming a
/// black backdrop with white text.
class AlbumDetailHeader extends StatelessWidget {
  const AlbumDetailHeader({
    super.key,
    required this.title,
    required this.expandedHeight,
    required this.showTitleInAppBar,
    required this.background,
    this.paletteSource,
    this.blurAndScrimBackground = true,
    this.coverBuilder,
    this.subtitle,
    this.meta,
    this.actions,
    this.appBarActions,
    this.appBarTitle,
    this.leading,
    this.backgroundColor,
    this.immersive = false,
    this.squareArtwork = true,
  });

  final String title;
  final double expandedHeight;
  final bool showTitleInAppBar;

  /// Full-bleed background content (cover image, motion banner, placeholder).
  final Widget background;

  /// Cover URL or local path the header palette is derived from. Null keeps the
  /// app's own colour scheme.
  final String? paletteSource;

  /// Blur the background and dim it 35%; disable for motion banners and
  /// placeholder backgrounds.
  final bool blurAndScrimBackground;

  /// Builds the centered square cover for the given side length; null hides
  /// the cover block (the header wraps it in the shared shadow + rounding).
  final Widget Function(BuildContext context, double coverSize)? coverBuilder;

  /// Artist line under the title (plain text or a clickable artist widget).
  final Widget? subtitle;

  /// "•"-joined meta row under the subtitle.
  final Widget? meta;

  /// Action row (play/shuffle, download-all, ...) under the meta row.
  final Widget? actions;

  /// Extra toolbar actions (top-right).
  final List<Widget>? appBarActions;

  /// Toolbar title when it should differ from [title] (e.g. a selection
  /// count); defaults to [title].
  final String? appBarTitle;

  /// Replaces the default circular back button.
  final Widget? leading;

  final Color? backgroundColor;
  final bool immersive;

  /// Ordinary cover art stays 1:1; provider-supplied banners may fill a header.
  final bool squareArtwork;

  /// Shrinks long titles so up to three lines fit the header.
  double _titleFontSize() {
    final length = title.trim().length;
    if (length > 45) return 18;
    if (length > 30) return 21;
    return 24;
  }

  @override
  Widget build(BuildContext context) {
    if ((coverBuilder != null || immersive)) {
      final scheme = Theme.of(context).colorScheme;
      return HeaderPalette(
        scheme: scheme,
        child: Builder(
          builder: (context) =>
              SliverMainAxisGroup(slivers: buildSlivers(context)),
        ),
      );
    }
    return CoverPaletteBuilder(
      palette: paletteOf(context),
      imageSource: paletteSource,
      builder: (context, headerScheme) => _buildAppBar(context, headerScheme),
    );
  }

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
                  : AppHeaderBacking(
                      visible: immersive ? titleVisible : null,
                    ),
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
              actions: [
                AppHeaderActions(actions: appBarActions ?? const []),
              ],
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
        layout: AppGroundLayout(
          stops: const [0, 0.48, 1],
          colors: gradient,
        ),
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

/// Primary action pill in a detail header (download all, play all). Reads its
/// colours from [HeaderPalette] so it works on light and dark headers alike.
