import 'package:flutter/cupertino.dart';
import 'package:sistrum/widgets/album_detail_header.dart'
    show HeaderCircleButton;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/utils/app_bar_layout.dart';
import 'package:sistrum/widgets/glass/sistrum_floating_header.dart';

/// The collapsing header used by every top-level tab and every settings-style
/// sub-page.
///
/// Expanded titles use [AppTokens.headerExpandedTitleSize]. Unless the glass
/// level is flat (or contrast blocks glass) the toolbar is transparent: the
/// back button and actions float as glass, and a backing band fades in once
/// content scrolls under the collapsed title.
class AppSliverHeader extends ConsumerWidget {
  /// Root of a navigation tab: no back button, and the title stays aligned with
  /// the content margin at every collapse ratio.
  const AppSliverHeader.tabRoot({
    super.key,
    required this.title,
    this.actions,
    this.alignToContent = false,
  }) : leading = null,
       _showLeading = false;

  /// A pushed page: shows [leading] (a back button by default) and slides the
  /// title clear of it as the header collapses.
  const AppSliverHeader.page({
    super.key,
    required this.title,
    this.actions,
    this.leading,
    this.alignToContent = true,
  }) : _showLeading = true;

  final String title;
  final List<Widget>? actions;

  /// Overrides the default back button. Only used by the page variant.
  final Widget? leading;

  /// Lines the expanded title up with content centered by [wideListInset] on
  /// tablets. Full-bleed pages (carousels, grids) keep it at the screen edge.
  final bool alignToContent;

  final bool _showLeading;

  /// Left inset of the collapsed title when a leading button is present: enough
  /// to clear a 48dp icon button plus the 8dp toolbar margin.
  static const double _leadingClearance = 56;

  /// Content margin the expanded title aligns to.
  static const double _contentMargin = 24;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tokens = context.tokens;
    final colorScheme = Theme.of(context).colorScheme;
    final topPadding = normalizedHeaderTopPadding(context);
    // Short landscape windows give the large title less headroom so content
    // starts higher. Portrait phones, even small ones, keep the full header.
    final screenSize = MediaQuery.sizeOf(context);
    final expandedHeight =
        screenSize.height < screenSize.width && screenSize.height < 720
        ? tokens.headerExpandedHeight - 24
        : tokens.headerExpandedHeight;
    final maxHeight = expandedHeight + topPadding;

    final opaque =
        sistrumHeaderMaterial(context, ref) == SistrumHeaderMaterial.opaque;
    final leading = this.leading;

    return SliverAppBar(
      expandedHeight: maxHeight,
      collapsedHeight: kToolbarHeight,
      floating: false,
      pinned: true,
      backgroundColor: opaque ? colorScheme.surface : Colors.transparent,
      surfaceTintColor: Colors.transparent,
      scrolledUnderElevation: 0,
      systemOverlayStyle: sistrumHeaderOverlayStyle(colorScheme.brightness),
      automaticallyImplyLeading: false,
      leadingWidth: _showLeading ? kToolbarHeight : null,
      leading: _showLeading
          ? (leading is IconButton
                ? SistrumHeaderCircle(child: leading)
                : SistrumHeaderControls(
                    child:
                        leading ??
                        HeaderCircleButton(
                          icon: CupertinoIcons.back,
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).backButtonTooltip,
                          onPressed: () => Navigator.pop(context),
                        ),
                  ))
          : null,
      actionsPadding: EdgeInsetsDirectional.only(end: kSistrumHeaderEdgeGap),
      actions: [SistrumHeaderActions(actions: actions ?? const [])],
      flexibleSpace: LayoutBuilder(
        builder: (context, constraints) {
          // SliverAppBar adds the platform's actual top safe-area inset to its
          // extents. Deriving the collapse ratio from our requested heights
          // left notched iPhones looking almost fully expanded even after the
          // toolbar had collapsed, so the large title occupied the back
          // button's space. Read the resolved sliver geometry instead.
          final settings = context
              .dependOnInheritedWidgetOfExactType<FlexibleSpaceBarSettings>();
          final minExtent = settings?.minExtent ?? kToolbarHeight;
          final maxExtent = settings?.maxExtent ?? maxHeight;
          final currentExtent =
              settings?.currentExtent ?? constraints.maxHeight;
          final extentDelta = maxExtent - minExtent;
          final expandRatio = extentDelta > 0
              ? ((currentExtent - minExtent) / extentDelta).clamp(0.0, 1.0)
              : 0.0;
          final contentMargin =
              _contentMargin + (alignToContent ? wideListInset(context) : 0);
          final leftPadding = _showLeading
              ? _leadingClearance -
                    ((_leadingClearance - contentMargin) * expandRatio)
              : contentMargin;
          final fontSize =
              tokens.headerCollapsedTitleSize +
              (tokens.headerExpandedTitleSize -
                      tokens.headerCollapsedTitleSize) *
                  expandRatio;

          final bar = FlexibleSpaceBar(
            centerTitle: false,
            expandedTitleScale: 1.0,
            titlePadding: EdgeInsetsDirectional.only(
              start: leftPadding,
              end: tokens.gapLg,
              bottom: tokens.gapLg,
            ),
            title: Text(
              title,
              // The title grows as the header expands; without a cap a long
              // localized title overflowed instead of ellipsizing.
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: FontWeight.bold,
                letterSpacing: -0.7 * expandRatio,
                color: colorScheme.onSurface,
              ),
            ),
          );
          if (opaque) return bar;
          return Stack(
            fit: StackFit.expand,
            children: [const SistrumHeaderBacking(), bar],
          );
        },
      ),
    );
  }
}
