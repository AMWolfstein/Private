import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart'
    show
        GlassDropMotion,
        GlassDropStretch,
        GlassDropStretchDriver,
        GlassSurface,
        GlassTravel;
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart'
    show kAppLiquidGlassFinish;
import 'package:sistrum/providers/runtime_profile_provider.dart';

/// Marks the held glass of every [AppGlassThumb], for tests and diagnostics.
const kAppGlassThumbKey = ValueKey<String>('sistrum-glass-thumb');

/// How long a thumb takes to lift into glass or settle back: g1455's
/// `kGlassDropDuration`, eased with `Curves.easeOut` both ways, as the
/// package's switch and slider drops are.
const kAppGlassThumbLiftDuration = Duration(milliseconds: 180);

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
/// The motion is g1455's switch and slider drop: holding lifts it over
/// [kAppGlassThumbLiftDuration] (the pill grows to [activeSize] while the
/// glass materializes and the painted pill fades), and while lifted it
/// stretches as it speeds up and squashes as it brakes
/// (`GlassDropStretchDriver`, off under reduced motion). The drop moves inside
/// its own `GlassTravel` region, so moving it takes no new capture.
///
/// At rest there is no backdrop read: the glass is not in the tree at all.
class AppGlassThumb extends StatefulWidget {
  const AppGlassThumb({
    super.key,
    required this.center,
    required this.held,
    required this.restSize,
    required this.activeSize,
    this.color = Colors.white,
    this.shadow = false,
    this.placing = false,
  });

  final Offset center;
  final bool held;
  final Size restSize;
  final Size activeSize;
  final Color color;

  /// Whether the thumb casts its contact shadow, at rest and while held.
  final bool shadow;

  /// Whether a change of [center] in this build is a tap placing the thumb,
  /// not a drag moving it: the drop arrives there without having travelled,
  /// so it does not stretch.
  final bool placing;

  @override
  State<AppGlassThumb> createState() => _AppGlassThumbState();
}

class _AppGlassThumbState extends State<AppGlassThumb>
    with TickerProviderStateMixin {
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: kAppGlassThumbLiftDuration,
    value: widget.held ? 1 : 0,
  );

  late final GlassDropStretchDriver _stretch = GlassDropStretchDriver(
    vsync: this,
    position: () => widget.center.dx,
  );

  GlassDropMotion _motion = GlassDropMotion.none;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stretch.motion = _motion = GlassDropMotion.resolve(context, null);
  }

  @override
  void didUpdateWidget(AppGlassThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _stretch.motion = _motion = GlassDropMotion.resolve(context, null);
    if (widget.held != oldWidget.held) {
      if (MediaQuery.disableAnimationsOf(context)) {
        _lift.value = widget.held ? 1 : 0;
      } else if (widget.held) {
        _lift.forward();
      } else {
        _lift.reverse();
      }
    }
    if (widget.center.dx != oldWidget.center.dx) {
      if (widget.placing) {
        _stretch.jump();
      } else if (_lift.value > 0) {
        _stretch.wake();
      }
    }
  }

  @override
  void dispose() {
    _stretch.dispose();
    _lift.dispose();
    super.dispose();
  }

  /// How far past the parent's box the drop can reach, per side: its growth
  /// over the rest pill, the most it can stretch, and 4 for the rounding.
  double get _margin {
    final rest = widget.restSize;
    final active = widget.activeSize;
    final reach = _motion.reach(active);
    final grow =
        ((active.width - rest.width).abs() / 2) >
            ((active.height - rest.height).abs() / 2)
        ? (active.width - rest.width).abs() / 2
        : (active.height - rest.height).abs() / 2;
    return grow + (reach.width > reach.height ? reach.width : reach.height) + 4;
  }

  @override
  Widget build(BuildContext context) {
    final margin = _margin;
    return IgnorePointer(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -margin,
            top: -margin,
            right: -margin,
            bottom: -margin,
            // A region of its own, behind a boundary of its own: moving the
            // drop repaints a layer that holds nothing but the drop, so no
            // picture under the glass is re-minted and the host has nothing
            // to recapture.
            child: GlassTravel(
              child: RepaintBoundary(
                child: AnimatedBuilder(
                  animation: Listenable.merge([_lift, _stretch]),
                  builder: (context, _) => _drop(margin),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _drop(double margin) {
    final raw = _lift.value;
    final lift = Curves.easeOut.transform(raw);
    final size = GlassDropStretch.apply(
      Size.lerp(widget.restSize, widget.activeSize, lift)!,
      _stretch.value * raw,
    );
    final left = widget.center.dx + margin - size.width / 2;
    final top = widget.center.dy + margin - size.height / 2;
    final radius = BorderRadius.circular(size.height / 2);
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (widget.shadow)
          Positioned(
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
        if (raw > 0)
          Positioned(
            left: left,
            top: top,
            width: size.width,
            height: size.height,
            child: _HeldGlassPill(
              key: kAppGlassThumbKey,
              color: widget.color,
              radius: radius,
              lift: lift,
            ),
          ),
        // The painted pill rides inside the drop and fades as it lifts, as
        // g1455's knob does.
        if (lift < 1)
          Positioned(
            left: left,
            top: top,
            width: size.width,
            height: size.height,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: widget.color.withValues(
                  alpha: widget.color.a * (1 - lift),
                ),
                borderRadius: radius,
              ),
              child: const SizedBox.expand(),
            ),
          ),
      ],
    );
  }
}

/// The held thumb: refracts what lies under it (LIQUID), a light veil and a
/// rim. It arrives by its optics ([GlassSurface.materialize]), not by fading,
/// and is absent from the tree while the thumb rests.
class _HeldGlassPill extends StatelessWidget {
  const _HeldGlassPill({
    super.key,
    required this.color,
    required this.radius,
    required this.lift,
  });

  final Color color;
  final BorderRadius radius;
  final double lift;

  @override
  Widget build(BuildContext context) {
    final amount = lift.clamp(0.0, 1.0);
    return ClipRRect(
      borderRadius: radius,
      child: GlassSurface(
        borderRadius: radius,
        finish: kAppLiquidGlassFinish,
        materialize: amount,
        labelled: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.6 * amount),
            borderRadius: radius,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.6 * amount),
              width: 0.75,
            ),
          ),
          child: const SizedBox.expand(),
        ),
      ),
    );
  }
}
