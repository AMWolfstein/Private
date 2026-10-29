import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';

/// Seconds for one full drift; slow enough to read as ambient.
const kAlbumKenBurnsPeriod = Duration(seconds: 28);

/// A slow zoom and pan of an album header's cover. The cover stays on its own
/// layer, so only a transform changes per frame. It stands still with the
/// setting off, with reduced motion, without glass (off or low-end devices),
/// while its route is covered, and once the page is scrolled past the cover.
class AlbumKenBurns extends ConsumerStatefulWidget {
  const AlbumKenBurns({super.key, required this.child});

  final Widget child;

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
    final glass =
        ref.watch(sistrumGlassLevelProvider) != SistrumGlassLevel.flat;
    _allowed = enabled && glass && !MediaQuery.disableAnimationsOf(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        _height = constraints.maxHeight;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync();
        });
        final child = RepaintBoundary(child: widget.child);
        if (!_allowed) return child;
        return AnimatedBuilder(
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
        );
      },
    );
  }
}

/// Scale 1.04 to 1.10 with a pan of at most 0.6 % by 0.5 % of the size, so
/// the cover's edges never show (a 1.04 zoom hides 2 % per side).
Matrix4 kenBurnsMatrix(double turn, Size size) {
  final scale = 1.07 + 0.03 * math.sin(turn);
  return Matrix4.identity()
    ..translateByDouble(
      size.width * 0.006 * math.sin(turn * 0.5 + 1),
      size.height * 0.005 * math.cos(turn * 0.5),
      0,
      1,
    )
    ..scaleByDouble(scale, scale, 1, 1);
}
