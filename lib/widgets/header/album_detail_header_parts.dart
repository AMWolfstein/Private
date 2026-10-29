part of 'album_detail_header.dart';

/// Softens the cover as it scrolls under the toolbar by dissolving into the
/// page's pre-blurred ground (no live blur), fully soft once the cover's
/// [artworkBottom] reaches the toolbar.
class _AlbumScrollVeil extends ConsumerWidget {
  const _AlbumScrollVeil({required this.artworkBottom});

  final double artworkBottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (MediaQuery.disableAnimationsOf(context) ||
        !ref.watch(appLiquidGlassProvider)) {
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
        return AppGroundVeil(opacity: Curves.easeOut.transform(progress));
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
      _lightness = paletteOf(context).topLightness(source);
    }
    return FutureBuilder<double?>(
      future: _lightness,
      initialData: paletteOf(context).peekTopLightness(source),
      builder: (context, snapshot) =>
          widget.builder(context, appArtworkBrightness(snapshot.data)),
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
