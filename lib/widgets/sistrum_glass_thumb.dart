import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:sistrum/theme/sistrum_glass_levels.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';

/// Whether touch-driven glass thumbs may render. Uses the selection pill's
/// gate: the liquid tier, clarity above 0.2, shader filters, motion and the
/// contrast policy. Hosts also require an enabled control and latch the
/// answer at touch-down, so glass never appears or vanishes mid-gesture.
bool sistrumGlassThumbsEnabled(BuildContext context, WidgetRef ref) =>
    ref.watch(sistrumShaderFiltersSupportedProvider) &&
    // Touch-only lenses stay real under lite too; never on Level 1.
    ref.watch(sistrumBlurEnabledProvider) &&
    !sistrumGlassClarity(ref.watch(sistrumGlassClarityLevelProvider)).plainBlur &&
    !MediaQuery.disableAnimationsOf(context) &&
    !ref.watch(
      sistrumGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );

/// The package's tuned clear thumb glass (LiquidGlassSwitch / Slider
/// defaults) with a circular capsule so the white cover matches our pills.
LiquidGlassStyle sistrumGlassThumbStyle({
  required bool outlines,
  double dispersion = 0,
}) => LiquidGlassStyle(
  specular: outlines
      ? const LiquidGlassLight.specular()
      : const LiquidGlassLight.specular(thickness: 0),
  color: const Color(0x00FFFFFF),
  refractionIndex: 1.03,
  refractionWidth: 8,
  dispersion: dispersion,
);

/// A thumb that is a painted pill at rest and a liquid-glass pill while
/// [held]. It fills its parent; [center] is in that box's coordinates.
///
/// At rest there is no lens, ticker or backdrop read. Touching mounts one
/// [LiquidGlassMotionPill] whose white cover is pixel-identical to the rest
/// pill; it is removed again once the contraction has hidden the glass.
class SistrumGlassThumb extends StatefulWidget {
  const SistrumGlassThumb({
    super.key,
    required this.center,
    required this.held,
    required this.restSize,
    required this.activeSize,
    required this.style,
    this.color = Colors.white,
    this.shadow,
  });

  final Offset center;
  final bool held;
  final Size restSize;
  final Size activeSize;
  final LiquidGlassStyle style;
  final Color color;

  /// Contact shadow shared by the rest pill and the glass.
  final LiquidGlassShadow? shadow;

  @override
  State<SistrumGlassThumb> createState() => _SistrumGlassThumbState();
}

class _SistrumGlassThumbState extends State<SistrumGlassThumb> {
  late bool _glass = widget.held;
  bool _shown = false;

  @override
  void didUpdateWidget(SistrumGlassThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.held) {
      _glass = true;
    } else if (!_shown) {
      // Released before the glass ever left rest: nothing to contract.
      _glass = false;
    }
  }

  void _visibility(bool visible) {
    if (visible) {
      _shown = true;
    } else if (!widget.held && mounted) {
      setState(() {
        _shown = false;
        _glass = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
    child: _glass
        ? LiquidGlassBatch.exclude(
            // Its own backdrop read: a batch's shared copy is taken before
            // the track under the thumb has painted.
            child: LiquidGlassMotionPill(
              center: widget.center,
              active: widget.held,
              restSize: widget.restSize,
              activeSize: widget.activeSize,
              style: widget.style,
              shadow: widget.shadow,
              cover: ColoredBox(color: widget.color),
              onGlassVisibilityChanged: _visibility,
            ),
          )
        : _RestPill(
            center: widget.center,
            size: widget.restSize,
            color: widget.color,
            shadow: widget.shadow,
          ),
  );
}

/// [LiquidGlassMotionPill] at rest, without its lens: the same shadow and
/// the same half-pixel cover outset, so mounting the glass does not move a
/// pixel.
class _RestPill extends StatelessWidget {
  const _RestPill({
    required this.center,
    required this.size,
    required this.color,
    required this.shadow,
  });

  final Offset center;
  final Size size;
  final Color color;
  final LiquidGlassShadow? shadow;

  static const _outset = 0.5;

  @override
  Widget build(BuildContext context) {
    final left = center.dx - size.width / 2;
    final top = center.dy - size.height / 2;
    final shadow = this.shadow;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        if (shadow != null)
          Positioned(
            left: left,
            top: top,
            width: size.width,
            height: size.height,
            child: LiquidGlassShadow(
              blur: shadow.blur,
              opacity: shadow.opacity,
              color: shadow.color,
              offset: shadow.offset,
              cornerRadius: shadow.cornerRadius ?? size.height / 2,
              inset: shadow.inset,
              visible: shadow.visible,
              insideGlass: shadow.insideGlass,
              child: const SizedBox.expand(),
            ),
          ),
        Positioned(
          left: left - _outset,
          top: top - _outset,
          width: size.width + 2 * _outset,
          height: size.height + 2 * _outset,
          child: liquidGlassClip(
            shape: LiquidGlassShape.roundedRectangle(
              cornerRadius: size.height / 2 + _outset,
              clipQuality: LiquidGlassClipQuality.exact,
            ),
            child: ColoredBox(color: color),
          ),
        ),
      ],
    );
  }
}
