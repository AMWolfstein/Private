import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/cover_palette.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/navigation/shell_navigation.dart';
import 'package:sistrum/widgets/glass/sistrum_floating_header.dart';
import 'package:sistrum/widgets/player/sistrum_player_ground.dart';
import 'package:sistrum/widgets/glass/sistrum_artwork_glass.dart';
import 'package:sistrum/theme/sistrum_glass_levels.dart';
import 'package:sistrum/widgets/header/header_controls.dart';
import 'package:sistrum/providers/cover_palette_provider.dart';

/// Share the same artwork-derived dark surface while loading and after the
/// artist metadata arrives, including when the app itself uses light mode.
class SistrumArtistSurface extends StatefulWidget {
  const SistrumArtistSurface({
    super.key,
    required this.imageSource,
    required this.child,

    this.neutralActions = false,
  });

  final String? imageSource;

  final Widget child;

  /// Album and playlist actions use white controls over the artwork tint.
  final bool neutralActions;

  @override
  State<SistrumArtistSurface> createState() => _SistrumArtistSurfaceState();
}

class _SistrumArtistSurfaceState extends State<SistrumArtistSurface> {
  @override
  void dispose() {
    ShellNavigationService.clearChromeBrightness(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final darkTheme = SistrumTheme.fromContext(
      context,
      brightness: Brightness.dark,
    );
    return Theme(
      data: darkTheme.copyWith(
        colorScheme: darkTheme.colorScheme.copyWith(primary: Colors.grey),
      ),
      child: CoverPaletteBuilder(
        palette: paletteOf(context),
        imageSource: widget.imageSource,
        builder: (context, _) {
          // Album and artist pages share the cover's base colour; only the
          // accent differs (white controls on albums and neutral covers).
          final colors = paletteOf(context).colors(widget.imageSource);
          final surface = colors.surface;
          final route = ModalRoute.of(context);
          if (route != null) {
            ShellNavigationService.setChromeBrightness(
              owner: this,
              route: route,
              brightness: Brightness.dark,
              surface: surface,
            );
          }
          return Builder(
            builder: (context) {
              final accent = !widget.neutralActions && colors.hasAccent;
              final primary = accent ? colors.accent : Colors.white;
              final onPrimary = accent ? colors.onAccent : Colors.black;
              final scheme = darkTheme.colorScheme.copyWith(
                primary: primary,
                onPrimary: onPrimary,
                onSurface: colors.onTone(colors.surfaceTone),
                onSurfaceVariant: colors.onToneVariant(colors.surfaceTone),
                surface: surface,
                surfaceContainer: Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.08),
                  surface,
                ),
                surfaceContainerHigh: Color.alphaBlend(
                  Colors.white.withValues(alpha: 0.12),
                  surface,
                ),
              );
              return Theme(
                data: darkTheme.copyWith(
                  scaffoldBackgroundColor: surface,
                  colorScheme: scheme,
                ),
                child: HeaderPalette(
                  scheme: scheme,
                  // The header controls draw from the page's artwork.
                  // Surfaces shown without Riverpod (previews) have no glass
                  // settings, and so no ground.
                  child:
                      context
                              .findAncestorWidgetOfExactType<
                                UncontrolledProviderScope
                              >() ==
                          null
                      ? widget.child
                      : Consumer(
                          builder: (context, ref, child) => SistrumPageGround(
                            source: widget.imageSource,
                            surface: surface,
                            sigma: sistrumGlassClarity(
                              ref.watch(sistrumGlassClarityLevelProvider),
                            ).blurSigma,
                            enabled: sistrumGroundNeeded(context, ref),
                            cover: sistrumCoverProvider(widget.imageSource),
                            child: child!,
                          ),
                          child: widget.child,
                        ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Portrait and centered identity from Sistrum's MobileArtistView. Actions stay
/// supplied by the screen so remote artists retain download/favorite behavior.
class SistrumArtistHeader extends StatelessWidget {
  const SistrumArtistHeader({
    super.key,
    required this.name,
    required this.artwork,
    required this.actions,
    required this.showTitle,
  });

  final String name;
  final Widget artwork;
  final List<Widget> actions;
  final bool showTitle;

  // A SliverMainAxisGroup clamps negative overlap, preventing this header from
  // receiving the overscroll used for its stretch animation.
  @override
  Widget build(BuildContext context) => buildSlivers(context).single;

  List<Widget> buildSlivers(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return [
      // Keep safe-area dependencies inside this sliver: folding the shell
      // navigation must not rebuild the artist's entire discography.
      SliverLayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.crossAxisExtent;
          final textWidth = (width - 48).clamp(0.0, double.infinity);
          final textScaler = MediaQuery.textScalerOf(context);
          double textHeight(String text, TextStyle style) {
            final painter = TextPainter(
              text: TextSpan(
                text: text,
                style: DefaultTextStyle.of(context).style.merge(style),
              ),
              textDirection: Directionality.of(context),
              textScaler: textScaler,
              textAlign: TextAlign.center,
            )..layout(maxWidth: textWidth);
            final height = painter.height;
            painter.dispose();
            return height;
          }

          final nameHeight = textHeight(
            name,
            const TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          );
          final identityHeight = nameHeight;
          const listenersHeight = 0.0;
          final photoHeight = (width * 0.76).clamp(240.0, 340.0);
          final expandedHeight =
              photoHeight +
              identityHeight +
              listenersHeight +
              (actions.isEmpty ? 0 : 94) +
              32;
          return Consumer(
            builder: (context, ref, flexibleSpace) {
              final opaque =
                  sistrumHeaderMaterial(context, ref) ==
                  SistrumHeaderMaterial.opaque;
              return _toolbar(
                context,
                expandedHeight: expandedHeight,
                backgroundColor: opaque ? surface : Colors.transparent,
                flexibleSpace: opaque
                    ? flexibleSpace!
                    : Stack(
                        fit: StackFit.expand,
                        children: [
                          flexibleSpace!,
                          SistrumHeaderBacking(color: surface),
                        ],
                      ),
              );
            },
            child: _flexibleSpace(
              surface: surface,
              identityHeight: identityHeight,
              context: context,
            ),
          );
        },
      ),
    ];
  }

  Widget _toolbar(
    BuildContext context, {
    required double expandedHeight,
    required Color backgroundColor,
    required Widget flexibleSpace,
  }) => SliverAppBar(
    pinned: true,
    stretch: !MediaQuery.disableAnimationsOf(context),
    expandedHeight: expandedHeight - MediaQuery.paddingOf(context).top,
    backgroundColor: backgroundColor,
    surfaceTintColor: Colors.transparent,
    scrolledUnderElevation: 0,
    systemOverlayStyle: sistrumHeaderOverlayStyle(Theme.of(context).brightness),
    leadingWidth: kToolbarHeight,
    leading: SistrumHeaderControls(
      child: HeaderCircleButton(
        icon: CupertinoIcons.back,
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        onPressed: () => Navigator.pop(context),
      ),
    ),
    title: AnimatedOpacity(
      opacity: showTitle ? 1 : 0,
      duration: const Duration(milliseconds: 180),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
      ),
    ),
    actionsPadding: EdgeInsetsDirectional.only(end: kSistrumHeaderEdgeGap),
    actions: const [SistrumHeaderActions()],
    flexibleSpace: flexibleSpace,
  );

  Widget _flexibleSpace({
    required BuildContext context,
    required Color surface,
    required double identityHeight,
  }) => FlexibleSpaceBar(
    collapseMode: CollapseMode.pin,
    stretchModes: const [StretchMode.zoomBackground],
    background: Stack(
      fit: StackFit.expand,
      children: [
        _ArtistCollapsingArtwork(surface: surface, child: artwork),
        Align(
          alignment: Alignment.bottomCenter,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ...[],
                ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: identityHeight),
                  child: _buildIdentity(context),
                ),
                ...[],
                if (actions.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    height: 74,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      spacing: 24,
                      children: actions,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    ),
  );

  Widget _buildIdentity(BuildContext context) {
    final fallback = Text(
      name,
      textAlign: TextAlign.center,
      style: const TextStyle(
        fontSize: 30,
        fontWeight: FontWeight.bold,
        color: Colors.white,
      ),
    );
    return fallback;
  }
}

/// Follow the sliver's actual collapse extent so scrolling back restores the
/// same artwork immediately, without a timer or rebuilding the discography.
class _ArtistCollapsingArtwork extends ConsumerWidget {
  const _ArtistCollapsingArtwork({required this.surface, required this.child});

  final Color surface;
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = context
        .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
    final range = settings == null
        ? 0.0
        : settings.maxExtent - settings.minExtent;
    final collapse = range <= 0
        ? 0.0
        : ((settings!.maxExtent - settings.currentExtent) / range).clamp(
            0.0,
            1.0,
          );
    final fade = const Interval(
      0.30,
      0.88,
      curve: Curves.easeInOut,
    ).transform(collapse);
    // The photo softens by dissolving into the page's pre-blurred ground,
    // never by re-blurring it on every scroll frame.
    final soften = Curves.easeOut.transform(collapse);
    final softenEnabled =
        !MediaQuery.disableAnimationsOf(context) &&
        ref.watch(sistrumLiquidGlassProvider);

    // The header controls' ground: this artwork under the same gradient,
    // fading to the surface as the header collapses.
    return SistrumGroundAnchor(
      layout: SistrumGroundLayout(
        alignment: Alignment.topCenter,
        stops: const [0, 0.48, 0.82, 1],
        colors: [
          Colors.black.withValues(alpha: 0.15),
          surface.withValues(alpha: 0),
          surface.withValues(alpha: 0.55),
          surface,
        ],
      ),
      fade: fade,
      child: ClipRect(
        child: Stack(
          fit: StackFit.expand,
          children: [
            TickerMode(
              enabled: fade < 1,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height = settings?.maxExtent ?? constraints.maxHeight;
                  final zoom = height > 0
                      ? (constraints.maxHeight / height).clamp(
                          1.0,
                          double.infinity,
                        )
                      : 1.0;
                  // Stretch the photograph uniformly around its top edge.
                  // Identity and actions remain outside this transform, moving
                  // down with the sliver without growing along with the image.
                  return OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: height,
                    maxHeight: height,
                    child: Transform.scale(
                      scale: zoom,
                      alignment: Alignment.topCenter,
                      child: RepaintBoundary(child: child),
                    ),
                  );
                },
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: const [0, 0.48, 0.82, 1],
                  colors: [
                    Colors.black.withValues(alpha: 0.15),
                    surface.withValues(alpha: 0),
                    surface.withValues(alpha: 0.55),
                    surface,
                  ],
                ),
              ),
            ),
            if (softenEnabled && fade < 1)
              Positioned.fill(child: SistrumGroundVeil(opacity: soften)),
            ColoredBox(
              key: const ValueKey('artist-artwork-fade'),
              color: surface.withValues(alpha: fade),
            ),
          ],
        ),
      ),
    );
  }
}
