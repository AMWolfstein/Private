import 'package:flutter/material.dart';

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
                _AppTrackSkeleton(
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
                _AppTrackSkeleton(
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

/// Mirrors each theme's collection header, including Sistrum's full-width
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

class _AppTrackSkeleton extends StatelessWidget {
  const _AppTrackSkeleton({
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
