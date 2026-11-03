import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/core/theme/app_glass_levels.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';

/// Marks the held glass of every [AppGlassThumb], for tests and diagnostics.
const kAppGlassThumbKey = ValueKey<String>('sistrum-glass-thumb');

/// Whether touch-driven glass thumbs may render: glass on, motion on, and
/// no high-contrast request. Hosts also require an enabled control and latch
/// the answer at touch-down, so glass never appears or vanishes mid-gesture.
bool appGlassThumbsEnabled(BuildContext context, WidgetRef ref) =>
    ref.watch(appBlurEnabledProvider) &&
    !MediaQuery.disableAnimationsOf(context) &&
    !ref.watch(
      appGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );

/// A thumb that is a painted pill at rest and a Tinted Lite glass pill while
/// [held]. It fills its parent; [center] is in that box's coordinates.
///
/// At rest there is no backdrop read: the glass layer is not painted at all
/// while it is hidden. Holding fades the glass in over the rest pill and
/// grows it to [activeSize]; releasing reverses both.
class AppGlassThumb extends StatelessWidget {
  const AppGlassThumb({
    super.key,
    required this.center,
    required this.held,
    required this.restSize,
    required this.activeSize,
    this.color = Colors.white,
    this.shadow = false,
  });

  final Offset center;
  final bool held;
  final Size restSize;
  final Size activeSize;
  final Color color;

  /// Whether the thumb casts its contact shadow, at rest and while held.
  final bool shadow;

  static const _duration = Duration(milliseconds: 220);
  static const _curve = Curves.easeOutCubic;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final duration = reduced ? Duration.zero : _duration;
    final size = held ? activeSize : restSize;
    final left = center.dx - size.width / 2;
    final top = center.dy - size.height / 2;
    final restLeft = center.dx - restSize.width / 2;
    final restTop = center.dy - restSize.height / 2;
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          if (shadow)
            AnimatedPositioned(
              duration: duration,
              curve: _curve,
              left: left,
              top: top,
              width: size.width,
              height: size.height,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: const SizedBox.expand(),
              ),
            ),
          AnimatedPositioned(
            duration: duration,
            curve: _curve,
            left: restLeft,
            top: restTop,
            width: restSize.width,
            height: restSize.height,
            child: AnimatedOpacity(
              opacity: held ? 0 : 1,
              duration: duration,
              curve: _curve,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(restSize.height / 2),
                ),
                child: const SizedBox.expand(),
              ),
            ),
          ),
          AnimatedPositioned(
            duration: duration,
            curve: _curve,
            left: left,
            top: top,
            width: size.width,
            height: size.height,
            child: AnimatedOpacity(
              opacity: held ? 1 : 0,
              duration: duration,
              curve: _curve,
              child: _HeldGlassPill(
                key: kAppGlassThumbKey,
                color: color,
                radius: size.height / 2,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The held thumb: a blur of what lies under it, a light veil and a rim.
/// Nothing is painted (or read) while its opacity is zero.
class _HeldGlassPill extends StatelessWidget {
  const _HeldGlassPill({super.key, required this.color, required this.radius});

  final Color color;
  final double radius;

  // One shared filter: never rebuilt per frame.
  static final _blur = ui.ImageFilter.blur(
    sigmaX: kAppGlassStyle.blurSigma,
    sigmaY: kAppGlassStyle.blurSigma,
  );

  @override
  Widget build(BuildContext context) {
    final shape = BorderRadius.circular(radius);
    return ClipRRect(
      borderRadius: shape,
      child: BackdropFilter(
        filter: _blur,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6),
            borderRadius: shape,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6),
              width: 0.75,
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
