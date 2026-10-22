import 'package:flutter/material.dart';

/// Wraps a child in a staggered fade-in + slide-up animation.
///
/// [index] adds 40ms of stagger delay for each item.
/// Set [animate] to false to skip the animation (e.g. when scrolling back).
class StaggeredListItem extends StatelessWidget {
  static const int _maxAnimatedItems = 10;

  final int index;
  final Widget child;

  final bool animate;

  const StaggeredListItem({
    super.key,
    required this.index,
    required this.child,

    this.animate = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!animate ||
        index >= _maxAnimatedItems ||
        MediaQuery.disableAnimationsOf(context)) {
      return child;
    }
    final cappedIndex = index.clamp(0, _maxAnimatedItems - 1);
    final delay = const Duration(milliseconds: 40) * cappedIndex;
    final totalDuration = const Duration(milliseconds: 250) + delay;

    return TweenAnimationBuilder<double>(
      duration: totalDuration,
      key: ValueKey('stagger_$index'),
      tween: Tween(begin: 0.0, end: 1.0),

      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        final delayFraction = totalDuration.inMilliseconds > 0
            ? delay.inMilliseconds / totalDuration.inMilliseconds
            : 0.0;
        final progress = value <= delayFraction
            ? 0.0
            : ((value - delayFraction) / (1.0 - delayFraction)).clamp(0.0, 1.0);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, 12 * (1 - progress)),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}

/// Creates a platform-aware material route.
///
/// This intentionally defers route transitions to Flutter's material route and
/// theme so Android predictive back and platform-default animations remain
/// intact.
Route<T> slidePageRoute<T>({required Widget page}) {
  return MaterialPageRoute<T>(builder: (context) => page);
}

/// A shimmer effect widget that can wrap skeleton placeholders.
class ShimmerLoading extends StatefulWidget {
  final Widget child;

  const ShimmerLoading({super.key, required this.child});

  @override
  State<ShimmerLoading> createState() => _ShimmerLoadingState();
}

class _ShimmerLoadingState extends State<ShimmerLoading>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return widget.child;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final baseColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.10),
            colorScheme.surface,
          );
    final highlightColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.14),
            colorScheme.surface,
          )
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.01),
            colorScheme.surface,
          );

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          shaderCallback: (bounds) {
            return LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [baseColor, highlightColor, baseColor],
              stops: [
                (_controller.value - 0.3).clamp(0.0, 1.0),
                _controller.value,
                (_controller.value + 0.3).clamp(0.0, 1.0),
              ],
              tileMode: TileMode.clamp,
            ).createShader(bounds);
          },
          blendMode: BlendMode.srcATop,
          child: child,
        );
      },
      // The mask moves every frame; the skeleton beneath it does not.
      child: RepaintBoundary(child: widget.child),
    );
  }
}

/// A skeleton placeholder box used inside [ShimmerLoading].
class SkeletonBox extends StatelessWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : Color.alphaBlend(
            Colors.black.withValues(alpha: 0.06),
            colorScheme.surface,
          );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
    );
  }
}

/// Album track list skeleton – mimics the album screen track list layout
/// (track number + title + artist + trailing icon, no cover art thumbnail).
class TrackListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showCoverHeader;

  const TrackListSkeleton({
    super.key,
    this.itemCount = 8,
    this.showCoverHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    {
      return ShimmerLoading(
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (showCoverHeader)
                const _CollectionHeaderSkeleton(showSubtitle: false),
              for (var index = 0; index < itemCount; index++)
                _MornyeTrackSkeleton(
                  numbered: false,
                  index: index,
                  showPreview: true,
                ),
            ],
          ),
        ),
      );
    }
  }
}

/// Album track list skeleton – mimics the album screen track list layout
/// (track number + title + artist + trailing icon, no cover art thumbnail).
class AlbumTrackListSkeleton extends StatelessWidget {
  final int itemCount;
  final bool showCoverHeader;

  const AlbumTrackListSkeleton({
    super.key,
    this.itemCount = 10,
    this.showCoverHeader = false,
  });

  @override
  Widget build(BuildContext context) {
    {
      return ShimmerLoading(
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (showCoverHeader) const _CollectionHeaderSkeleton(),
              for (var index = 0; index < itemCount; index++)
                _MornyeTrackSkeleton(
                  numbered: true,
                  index: index,
                  showPreview: true,
                ),
            ],
          ),
        ),
      );
    }
  }
}

/// Mirrors each theme's collection header, including Mornye's full-width
/// square artwork and compact primary action between two circular controls.
class _CollectionHeaderSkeleton extends StatelessWidget {
  const _CollectionHeaderSkeleton({this.showSubtitle = true});

  final bool showSubtitle;

  @override
  Widget build(BuildContext context) {
    {
      return LayoutBuilder(
        builder: (context, constraints) {
          final coverSize = constraints.maxWidth.clamp(0.0, 440.0);
          return Stack(
            children: [
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Center(
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (bounds) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0, 0.48, 1],
                      colors: [Colors.white, Colors.white, Colors.transparent],
                    ).createShader(bounds),
                    child: SkeletonBox(
                      width: coverSize,
                      height: coverSize,
                      borderRadius: 0,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsetsDirectional.fromSTEB(
                  20,
                  (coverSize - 20).clamp(0.0, double.infinity),
                  20,
                  28,
                ),
                child: Column(
                  children: [
                    const FractionallySizedBox(
                      widthFactor: 0.75,
                      child: SkeletonBox(
                        width: double.infinity,
                        height: 28,
                        borderRadius: 6,
                      ),
                    ),
                    if (showSubtitle) ...[
                      const SizedBox(height: 5),
                      const FractionallySizedBox(
                        widthFactor: 0.5,
                        child: SkeletonBox(
                          width: double.infinity,
                          height: 24,
                          borderRadius: 5,
                        ),
                      ),
                    ],
                    const SizedBox(height: 5),
                    const SkeletonBox(width: 140, height: 16, borderRadius: 4),
                    const SizedBox(height: 16),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 460),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        spacing: 16,
                        children: [
                          SkeletonBox(width: 44, height: 44, borderRadius: 22),
                          Flexible(
                            child: SkeletonBox(
                              width: 172,
                              height: 50,
                              borderRadius: 25,
                            ),
                          ),
                          SkeletonBox(width: 44, height: 44, borderRadius: 22),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }
  }
}

class _MornyeTrackSkeleton extends StatelessWidget {
  const _MornyeTrackSkeleton({
    required this.numbered,
    required this.index,
    this.showPreview = false,
  });

  final bool numbered;
  final int index;
  final bool showPreview;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              if (numbered)
                const SizedBox(
                  width: 32,
                  child: Center(
                    child: SkeletonBox(width: 14, height: 16, borderRadius: 4),
                  ),
                )
              else
                const SkeletonBox(width: 48, height: 48, borderRadius: 4),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    FractionallySizedBox(
                      widthFactor: 0.7 + (index % 3) * 0.1,
                      child: const SkeletonBox(
                        width: double.infinity,
                        height: 18,
                        borderRadius: 4,
                      ),
                    ),
                    const SizedBox(height: 6),
                    const FractionallySizedBox(
                      widthFactor: 0.5,
                      child: SkeletonBox(
                        width: double.infinity,
                        height: 14,
                        borderRadius: 4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 20),
              if (showPreview) ...[
                const SkeletonBox(width: 20, height: 20, borderRadius: 10),
                const SizedBox(width: 24),
              ],
              const SkeletonBox(width: 20, height: 6, borderRadius: 3),
            ],
          ),
        ),
        Padding(
          padding: EdgeInsetsDirectional.only(
            start: numbered ? 64 : 80,
            end: 20,
          ),
          child: const Divider(height: 1, thickness: 0.5),
        ),
      ],
    );
  }
}

/// An animated selection indicator that scales in/out and crossfades the
/// checked/unchecked state.
class AnimatedSelectionCheckbox extends StatelessWidget {
  final bool visible;
  final bool selected;
  final ColorScheme colorScheme;
  final double size;

  /// Background color when not selected. Defaults to `Colors.transparent`.
  final Color? unselectedColor;

  const AnimatedSelectionCheckbox({
    super.key,
    required this.visible,
    required this.selected,
    required this.colorScheme,
    this.size = 20,
    this.unselectedColor,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedScale(
      scale: visible ? 1.0 : 0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutBack,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary
              : unselectedColor ?? Colors.transparent,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outline,
            width: 2,
          ),
        ),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: selected
              ? Icon(
                  Icons.check,
                  key: const ValueKey('checked'),
                  size: size - 6,
                  color: colorScheme.onPrimary,
                )
              : SizedBox(
                  key: const ValueKey('unchecked'),
                  width: size - 6,
                  height: size - 6,
                ),
        ),
      ),
    );
  }
}

/// Wraps a [Badge] child and plays a brief scale-bump whenever [count] changes.
class AnimatedBadge extends StatefulWidget {
  final int count;
  final Widget child;

  const AnimatedBadge({super.key, required this.count, required this.child});

  @override
  State<AnimatedBadge> createState() => _AnimatedBadgeState();
}

class _AnimatedBadgeState extends State<AnimatedBadge>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  int _previousCount = 0;

  @override
  void initState() {
    super.initState();
    _previousCount = widget.count;
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 1.0), weight: 60),
    ]).animate(_controller);
  }

  @override
  void didUpdateWidget(AnimatedBadge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.count != _previousCount && widget.count > _previousCount) {
      _controller.forward(from: 0);
    }
    _previousCount = widget.count;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(scale: _scaleAnimation, child: widget.child);
  }
}
