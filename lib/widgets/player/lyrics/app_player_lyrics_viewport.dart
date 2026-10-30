import 'package:flutter/material.dart';
import 'package:sistrum/widgets/player/lyrics/player_lyrics.dart';

/// Masks the lyrics viewport above its visible height and reveals it as the
/// lyric controls hide. Used by the compact lyrics stage of the player layout.
Widget appLyricsViewport(
  BuildContext context,
  Widget child, {
  required double visibleHeight,
  required bool lyricsControlsHidden,
}) => TweenAnimationBuilder<double>(
  tween: Tween(begin: 0, end: lyricsControlsHidden ? 1 : 0),
  duration: MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : const Duration(milliseconds: 220),
  curve: Curves.easeOutCubic,
  builder: (context, reveal, child) => ShaderMask(
    blendMode: BlendMode.dstIn,
    shaderCallback: (bounds) {
      final height = bounds.height.clamp(1.0, double.infinity);
      final end = visibleHeight.clamp(0.0, height);
      final start = (end - 24).clamp(0.0, end);
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0, start / height, end / height, 1],
        colors: [
          Colors.white,
          Colors.white,
          Colors.white.withValues(alpha: reveal),
          Colors.white.withValues(alpha: reveal),
        ],
      ).createShader(bounds);
    },
    child: LayoutBuilder(
      builder: (context, constraints) => LyricsCoveredBottom(
        height: constraints.hasBoundedHeight
            ? (constraints.maxHeight - visibleHeight).clamp(
                    0.0,
                    double.infinity,
                  ) *
                  (1 - reveal)
            : 0,
        child: child!,
      ),
    ),
  ),
  child: child,
);
