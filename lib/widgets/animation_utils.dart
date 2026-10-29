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
