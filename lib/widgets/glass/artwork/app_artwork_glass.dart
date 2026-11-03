import 'package:flutter/material.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_glass_render.dart';

/// A glass surface drawn from an artwork ground: the blurred ground under
/// [fill], below [child]. The caller clips it and paints its rim.
class AppArtworkGlassSurface extends StatefulWidget {
  const AppArtworkGlassSurface({
    super.key,
    required this.controller,
    required this.fill,
    required this.opaqueFill,
    required this.child,
  });

  final AppGroundController controller;
  final Color fill;

  /// Shown for an overlay's lifetime when it opened before its ground.
  final Color opaqueFill;

  final Widget child;

  @override
  State<AppArtworkGlassSurface> createState() => _AppArtworkGlassSurfaceState();
}

class _AppArtworkGlassSurfaceState extends State<AppArtworkGlassSurface> {
  bool? _overlayReady;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (AppArtworkGroundScope.inOverlay(context)) {
      _overlayReady ??= widget.controller.hasGround;
    }
  }

  @override
  Widget build(BuildContext context) {
    // An overlay that opened before its ground stays opaque for its lifetime,
    // so its material never changes mid-open.
    final opaque = _overlayReady == false;
    return AppArtworkGlassRender(
      controller: widget.controller,
      opaque: opaque,
      fill: opaque ? widget.opaqueFill : widget.fill,
      scroll: Scrollable.maybeOf(context)?.position,
      child: widget.child,
    );
  }
}
