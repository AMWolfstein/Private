import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderProxySliver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/theme/cover_palette.dart';
import 'package:sistrum/widgets/sistrum_artwork_glass.dart';
import 'package:sistrum/theme/sistrum_icons.dart';
import 'package:sistrum/widgets/sistrum_chrome.dart';
import 'package:sistrum/widgets/sistrum_floating_header.dart';
import 'package:sistrum/utils/adaptive_layout.dart';

/// Collapsing album-detail header shared by the album, local-album, and
/// downloaded-album screens: full-bleed [background] (optionally blurred and
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
    final edgeInset = detailHeaderEdgeInset(context);
    final screenSize = MediaQuery.sizeOf(context);
    final artworkSize = math.min(
      screenSize.width.clamp(0.0, 440.0),
      math.max(240.0, screenSize.height * 0.55),
    );
    final details = _buildSistrumDetails(context);
    Widget toolbar({bool collapsed = true}) => Consumer(
      builder: (context, ref, _) {
        final opaque =
            sistrumHeaderMaterial(context, ref) == SistrumHeaderMaterial.opaque;
        final titleVisible =
            showTitleInAppBar ||
            appBarTitle != null ||
            (immersive && collapsed);
        final overArtwork = immersive && !collapsed;
        return _ArtworkBrightness(
          source: overArtwork ? paletteSource : null,
          builder: (context, artwork) => SistrumHeaderBrightness(
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
              systemOverlayStyle: sistrumHeaderOverlayStyle(
                artwork ?? (overArtwork ? Brightness.dark : scheme.brightness),
              ),
              flexibleSpace: opaque
                  ? null
                  : SistrumHeaderBacking(
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
              leadingWidth: kToolbarHeight + edgeInset,
              leading: Padding(
                padding: EdgeInsetsDirectional.only(start: edgeInset),
                child: SistrumHeaderControls(
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
              ),
              actionsPadding: EdgeInsetsDirectional.only(
                end: edgeInset + kSistrumHeaderEdgeGap,
              ),
              actions: [
                SistrumHeaderActions(actions: appBarActions ?? const []),
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
      final artwork = SistrumGroundAnchor(
        layout: SistrumGroundLayout(
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

  Widget _buildSistrumDetails(BuildContext context) => Padding(
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
                child: SistrumGroundAnchor(
                  layout: const SistrumGroundLayout(radius: 14),
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
    // iOS does not add horizontal safe-area padding in portrait. Give toolbar
    // controls and header content an explicit inset so circular actions do not
    // sit against the glass edge on either iPhone or iPad. Android retains its
    // existing spacing.
    final iosEdgeInset = detailHeaderEdgeInset(context);
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
                  left: 20 + iosEdgeInset,
                  right: 20 + iosEdgeInset,
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
      leadingWidth: kToolbarHeight + iosEdgeInset,
      leading: Padding(
        padding: EdgeInsetsDirectional.only(start: iosEdgeInset),
        child:
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
      ),
      actionsPadding: EdgeInsetsDirectional.only(end: iosEdgeInset),
      actions: appBarActions,
    );
  }
}

/// Softens the cover as it scrolls under the toolbar by dissolving into the
/// page's pre-blurred ground (no live blur), fully soft once the cover's
/// [artworkBottom] reaches the toolbar.
class _AlbumScrollVeil extends ConsumerWidget {
  const _AlbumScrollVeil({required this.artworkBottom});

  final double artworkBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (MediaQuery.disableAnimationsOf(context) ||
        !ref.watch(sistrumLiquidGlassProvider)) {
      return const SizedBox.shrink();
    }
    // Read here, not by the header: an inset change rebuilds only the veil.
    final extent =
        artworkBottom - kToolbarHeight - MediaQuery.paddingOf(context).top;
    final position = Scrollable.of(context).position;
    return AnimatedBuilder(
      animation: position,
      builder: (context, _) {
        final scrolled = position.hasPixels ? position.pixels : 0.0;
        final progress = extent > 0 ? (scrolled / extent).clamp(0.0, 1.0) : 0.0;
        return SistrumGroundVeil(opacity: Curves.easeOut.transform(progress));
      },
    );
  }
}

class _AlbumStretchArtwork extends StatelessWidget {
  const _AlbumStretchArtwork({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final position = Scrollable.of(context).position;
    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: position,
        child: RepaintBoundary(child: child),
        builder: (context, artwork) {
          final overscroll = position.hasContentDimensions
              ? (position.minScrollExtent - position.pixels).clamp(
                  0.0,
                  double.infinity,
                )
              : 0.0;
          final height = constraints.maxHeight;
          final scale = height > 0 ? 1 + overscroll / height : 1.0;
          // The viewport moves the details down during a pull. Keep the image
          // at the top and enlarge it without changing the scrollable layout.
          return Transform.translate(
            offset: Offset(0, -overscroll),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: artwork,
            ),
          );
        },
      ),
    );
  }
}

/// Keeps the pinned toolbar above the artwork without shifting the artwork or
/// metadata down by the toolbar's safe-area height.
/// Resolves whether the artwork behind a transparent toolbar reads as dark or
/// light; null for no [source] or while unknown.
class _ArtworkBrightness extends StatefulWidget {
  const _ArtworkBrightness({required this.source, required this.builder});

  final String? source;
  final Widget Function(BuildContext context, Brightness? brightness) builder;

  @override
  State<_ArtworkBrightness> createState() => _ArtworkBrightnessState();
}

class _ArtworkBrightnessState extends State<_ArtworkBrightness> {
  // Resolved once per source: the toolbar rebuilds on every scroll frame.
  String? _source;
  Future<double?>? _lightness;

  @override
  Widget build(BuildContext context) {
    final source = widget.source;
    if (source == null) return widget.builder(context, null);
    if (source != _source) {
      _source = source;
      _lightness = CoverPalette.topLightness(source);
    }
    return FutureBuilder<double?>(
      future: _lightness,
      initialData: CoverPalette.peekTopLightness(source),
      builder: (context, snapshot) =>
          widget.builder(context, sistrumArtworkBrightness(snapshot.data)),
    );
  }
}

class _AlbumOverlayToolbar extends SingleChildRenderObjectWidget {
  const _AlbumOverlayToolbar({required super.child});

  @override
  RenderProxySliver createRenderObject(BuildContext context) =>
      _RenderAlbumOverlayToolbar();
}

class _RenderAlbumOverlayToolbar extends RenderProxySliver {
  @override
  void performLayout() {
    super.performLayout();
    final childGeometry = geometry!;
    if (childGeometry.scrollOffsetCorrection != null) return;
    geometry = childGeometry.copyWith(
      scrollExtent: 0,
      layoutExtent: 0,
      cacheExtent: 0,
    );
  }
}

/// Centered Play/Shuffle pills with optional outer Loved and playlist controls.
/// Colours and translucent fills follow the existing detail-header design.
class AlbumPlayActions extends StatelessWidget {
  const AlbumPlayActions({
    super.key,
    required this.playLabel,
    required this.shuffleTooltip,
    required this.onPlay,
    required this.onShuffle,
    this.isPlaying = false,
    this.leadingAction,
    this.trailingAction,
  });

  final String playLabel;
  final String shuffleTooltip;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final bool isPlaying;
  final Widget? leadingAction;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    {
      final compact = leadingAction != null || trailingAction != null;
      final gap = compact ? 6.0 : 12.0;
      return Row(
        textDirection: TextDirection.ltr,
        children: [
          if (leadingAction != null) ...[leadingAction!, SizedBox(width: gap)],
          Expanded(
            child: HeaderFilledButton(
              icon: isPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              label: playLabel,
              compact: compact,
              onPressed: onPlay,
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: _SistrumHeaderButton(
              icon: CupertinoIcons.shuffle,
              label: shuffleTooltip,
              compact: compact,
              onPressed: onShuffle,
            ),
          ),
          if (trailingAction != null) ...[
            SizedBox(width: gap),
            trailingAction!,
          ],
        ],
      );
    }
  }
}

/// Primary action pill in a detail header (download all, play all). Reads its
/// colours from [HeaderPalette] so it works on light and dark headers alike.
class HeaderFilledButton extends StatelessWidget {
  const HeaderFilledButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tonal = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool tonal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    {
      return _SistrumHeaderButton(
        icon: sistrumIconFor(icon),
        label: label,
        onPressed: onPressed,
        prominent: !tonal,
        compact: compact,
      );
    }
  }
}

/// Circular header icon button (add-to-playlist, love-all, ...). Sized to the
/// minimum touch target and tinted from the [HeaderPalette].
class HeaderCircleButton extends ConsumerWidget {
  const HeaderCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
    this.tonal = false,
    this.buttonSize,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Overrides the palette foreground, e.g. to mark an active "loved" state.
  final Color? iconColor;

  /// Uses the same translucent fill as the local album's Play/Shuffle pills.
  final bool tonal;

  final double? buttonSize;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = HeaderPalette.of(context);
    {
      if (tonal) {
        return Tooltip(
          message: tooltip,
          child: SizedBox.square(
            dimension: buttonSize ?? kSistrumHeaderControlSize,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(
                (buttonSize ?? kSistrumHeaderControlSize) / 2,
              ),
              color: scheme.onSurface.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.10 : 0.06,
              ),
              onPressed: onPressed,
              child: Icon(
                sistrumIconFor(icon),
                size: iconSize,
                color: onPressed == null
                    ? scheme.onSurfaceVariant
                    : iconColor ?? scheme.primary,
              ),
            ),
          ),
        );
      }
      final blurEnabled = ref.watch(sistrumBlurEnabledProvider);
      final button = IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(sistrumIconFor(icon), size: iconSize),
        style: IconButton.styleFrom(
          minimumSize: Size.square(buttonSize ?? kSistrumHeaderControlSize),
          foregroundColor: iconColor ?? scheme.onSurface,
        ),
      );
      return Center(
        widthFactor: 1,
        child: SistrumGlass.navigation(
          radius: (buttonSize ?? kSistrumHeaderControlSize) / 2,
          tintColor: scheme.brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
          tintOpacity: scheme.brightness == Brightness.dark ? 0.45 : 0.55,
          blurEnabled: blurEnabled,
          allowLens: sistrumLiquidChromeEnabled(context, ref),
          child: button,
        ),
      );
    }
  }
}

class _SistrumHeaderButton extends StatelessWidget {
  const _SistrumHeaderButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.prominent = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    final foreground = onPressed == null
        ? scheme.onSurfaceVariant
        : prominent
        ? scheme.onPrimary
        : scheme.primary;
    // The compact Play/Shuffle pills share the width with the Loved and
    // Add-to-playlist circles; at large text the labels no longer fit, so the
    // pills drop to icon-only and keep their accessible name.
    final iconOnly =
        compact && MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 48 : 50),
      child: CupertinoButton(
        padding: EdgeInsets.symmetric(
          horizontal: iconOnly ? 0 : (compact ? 6 : 16),
          vertical: 12,
        ),
        minimumSize: const Size(48, 48),
        borderRadius: BorderRadius.circular(28),
        color: prominent
            ? scheme.primary
            : scheme.onSurface.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.10 : 0.06,
              ),
        onPressed: onPressed,
        child: iconOnly
            ? Tooltip(
                message: label,
                child: Semantics(
                  label: label,
                  child: Icon(icon, size: 20, color: foreground),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: compact ? 18 : 20, color: foreground),
                  SizedBox(width: compact ? 4 : 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 15 : 17,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "•"-joined row of [HeaderMetaItem]s shown under the header subtitle
/// (track count, duration, quality, ...).
class HeaderMetaRow extends StatelessWidget {
  const HeaderMetaRow({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    final parts = <Widget>[];
    for (final item in items) {
      if (parts.isNotEmpty) {
        parts.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '•',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        );
      }
      parts.add(item);
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: parts,
    );
  }
}

/// Single meta label (optional leading icon) for [HeaderMetaRow].
class HeaderMetaItem extends StatelessWidget {
  const HeaderMetaItem(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    final textStyle = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    if (icon == null) return Text(label, style: textStyle);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurface),
        const SizedBox(width: 4),
        Text(label, style: textStyle),
      ],
    );
  }
}
