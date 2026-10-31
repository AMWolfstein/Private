import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';

/// Seconds for one full drift; slow enough to read as ambient.
const kAlbumKenBurnsPeriod = Duration(seconds: 28);

/// A slow zoom and pan of an album header's cover, and of the immersive
/// player's artwork. The cover stays on its own layer, so only a transform
/// changes per frame. It stands still with the setting off, with reduced
/// motion, without glass (off or low-end devices), while [active] is false
/// (for example, the player shows lyrics), while its route is covered, and
/// once the page is scrolled past the cover.
class AlbumKenBurns extends ConsumerStatefulWidget {
  const AlbumKenBurns({super.key, required this.child, this.active = true});

  final Widget child;
  final bool active;

  @override
  ConsumerState<AlbumKenBurns> createState() => _AlbumKenBurnsState();
}

class _AlbumKenBurnsState extends ConsumerState<AlbumKenBurns>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: kAlbumKenBurnsPeriod,
  );
  ScrollPosition? _position;
  double _height = 0;
  bool _allowed = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.removeListener(_sync);
      _position = position?..addListener(_sync);
    }
    _sync();
  }

  @override
  void dispose() {
    _position?.removeListener(_sync);
    _controller.dispose();
    super.dispose();
  }

  void _sync() {
    final position = _position;
    final scrolledAway =
        position != null &&
        position.hasPixels &&
        _height > 0 &&
        position.pixels > _height;
    final run = _allowed && !scrolledAway;
    if (run && !_controller.isAnimating) {
      _controller.repeat();
    } else if (!run && _controller.isAnimating) {
      _controller.stop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(
      settingsProvider.select((s) => s.animatedAlbumArtwork),
    );
    final glass = ref.watch(appGlassLevelProvider) != AppGlassLevel.flat;
    _allowed =
        enabled &&
        glass &&
        widget.active &&
        !MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync();
        });
        final child = RepaintBoundary(child: widget.child);
        if (!_allowed) return child;
        // The zoom stays inside the cover's box; unclipped, the enlarged
        // cover paints over the title below it.
        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            child: child,
            builder: (context, child) {
              final turn = _controller.value * 2 * math.pi;
              return Transform(
                alignment: Alignment.center,
                transform: kenBurnsMatrix(turn, constraints.biggest),
                child: child,
              );
            },
          ),
        );
      },
    );
  }
}

/// Starts at the natural size (scale 1.00) and zooms slowly to 1.06. The pan
/// is limited to the extra cover the zoom reveals on each side, so the edges
/// never show; at 1.00 there is no extra cover, so there is no pan either.
Matrix4 kenBurnsMatrix(double turn, Size size) {
  final scale = 1.03 - 0.03 * math.cos(turn);
  final slack = (scale - 1) / 2;
  return Matrix4.identity()
    ..translateByDouble(
      size.width * slack * 0.8 * math.sin(turn * 0.5 + 1),
      size.height * slack * 0.8 * math.cos(turn * 0.5),
      0,
      1,
    )
    ..scaleByDouble(scale, scale, 1, 1);
}
