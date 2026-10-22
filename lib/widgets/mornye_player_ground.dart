import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/theme/cover_palette.dart';
import 'package:spotiflac_android/theme/mornye_glass_levels.dart';
import 'package:spotiflac_android/widgets/cached_cover_image.dart';
import 'package:spotiflac_android/widgets/mornye_artwork_glass.dart';
import 'package:spotiflac_android/widgets/mornye_player_background.dart';

/// The cover at [source] (a file path or URL) as an image provider.
ImageProvider? mornyeCoverProvider(String? source) {
  if (source == null || source.isEmpty) return null;
  return source.startsWith('http://') || source.startsWith('https://')
      ? cachedCoverImageProvider(source)
      : FileImage(File(source));
}

/// Whether glass at [context] is translucent at all: off, high contrast
/// and disabled blur keep it opaque, and then no ground is built.
bool mornyeGroundNeeded(BuildContext context, WidgetRef ref) =>
    ref.watch(mornyeBlurEnabledProvider) &&
    ref.watch(mornyeGlassLevelProvider) != MornyeGlassLevel.flat &&
    !ref.watch(
      mornyeGlassContrastBlockedProvider(MediaQuery.highContrastOf(context)),
    );

/// Builds the player's ground, the same picture MornyePlayerBackground
/// paints plus the inset cover, and provides it to the player's overlays.
class MornyePlayerGround extends ConsumerStatefulWidget {
  const MornyePlayerGround({
    super.key,
    required this.source,
    required this.immersive,
    required this.showArtwork,
    required this.artworkAspectRatio,
    required this.fadeStart,
    required this.insetArtworkKey,
    required this.child,
  });

  /// The cover's path or URL.
  final String? source;
  final bool immersive;

  /// The player page (not lyrics or the queue) is showing.
  final bool showArtwork;
  final double? artworkAspectRatio;
  final double fadeStart;

  /// The normal view's inset cover; its box is drawn into the ground.
  final GlobalKey insetArtworkKey;
  final Widget child;

  @override
  ConsumerState<MornyePlayerGround> createState() => _MornyePlayerGroundState();
}

class _MornyePlayerGroundState extends ConsumerState<MornyePlayerGround>
    with SingleTickerProviderStateMixin {
  late final MornyeGroundController _controller = MornyeGroundController(
    vsync: this,
    persistent: true,
    rectOf: () {
      final box = context.findRenderObject();
      return box is RenderBox && box.attached && box.hasSize
          ? MatrixUtils.transformRect(
              box.getTransformTo(null),
              Offset.zero & box.size,
            )
          : null;
    },
  );
  Object? _built;
  String? _builtSource;
  int _generation = 0;
  bool _scheduled = false;

  @visibleForTesting
  MornyeGroundController get controller => _controller;

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  void _schedule() {
    if (_scheduled) return;
    _scheduled = true;
    // After layout: the inset cover's box decides where it is drawn.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_build());
    });
  }

  Rect? _insetRect() {
    final inset = widget.insetArtworkKey.currentContext?.findRenderObject();
    final host = context.findRenderObject();
    if (inset is! RenderBox ||
        host is! RenderBox ||
        !inset.attached ||
        !inset.hasSize) {
      return null;
    }
    return MatrixUtils.transformRect(
      inset.getTransformTo(host),
      Offset.zero & inset.size,
    );
  }

  Future<void> _build() async {
    final host = context.findRenderObject();
    if (host is! RenderBox || !host.hasSize) return;
    final size = host.size;
    final source = widget.source;
    final immersive = widget.immersive;
    final showArtwork = widget.showArtwork;
    final ratio = widget.artworkAspectRatio;
    final fadeStart = widget.fadeStart;
    final inset = !immersive && showArtwork ? _insetRect() : null;
    final sigma = mornyeGlassClarity(
      ref.read(mornyeGlassClarityLevelProvider),
    ).blurSigma;
    final key = (
      source,
      immersive,
      showArtwork,
      ratio,
      fadeStart,
      size,
      inset,
      sigma,
    );
    if (key == _built) return;
    final trackChanged = _built != null && _builtSource != source;
    _built = key;
    _builtSource = source;
    final generation = ++_generation;
    // The background's own colours, from the one cover analysis.
    final colors = await CoverPalette.resolveColors(source);
    if (!mounted || generation != _generation) return;
    final screen = MediaQuery.sizeOf(context);
    final image = await MornyeGroundBuilder.build(
      label: 'player',
      size: size,
      cover: showArtwork ? mornyeCoverProvider(source) : null,
      sigma: sigma,
      timing: MornyeGroundBuilder.lastPlayer,
      paint: (canvas, size, cover) {
        final rect = Offset.zero & size;
        canvas.drawRect(
          rect,
          Paint()
            ..shader = LinearGradient(
              begin: immersive ? Alignment.topCenter : Alignment.topLeft,
              end: immersive ? Alignment.bottomCenter : Alignment.bottomRight,
              stops: immersive ? const [0, 0.5, 1] : null,
              colors: immersive ? colors.playerStops : colors.playerPlainStops,
            ).createShader(rect),
        );
        if (cover == null) return;
        if (immersive) {
          final art = Rect.fromLTWH(
            0,
            0,
            size.width,
            mornyePlayerArtworkHeight(
              screen,
              square: !immersive,
              aspectRatio: ratio,
            ),
          );
          // The background's fade mask: opaque, then transparent at the end.
          canvas.saveLayer(art, Paint());
          MornyeGroundBuilder.paintCover(canvas, cover, art);
          canvas.drawRect(
            art,
            Paint()
              ..blendMode = BlendMode.dstIn
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0, fadeStart, 1],
                colors: const [Colors.white, Colors.white, Colors.transparent],
              ).createShader(art),
          );
          canvas.restore();
        } else if (inset != null) {
          canvas
            ..save()
            ..clipRRect(
              RRect.fromRectAndRadius(inset, const Radius.circular(12)),
            );
          MornyeGroundBuilder.paintCover(canvas, cover, inset);
          canvas.restore();
        }
      },
    );
    if (image == null) return;
    if (!mounted || generation != _generation) {
      image.dispose();
      return;
    }
    _controller.show(
      MornyeGround(
        image,
        edge: (immersive ? colors.playerStops : colors.playerPlainStops).last,
      ),
      crossfade: trackChanged && !MediaQuery.disableAnimationsOf(context),
    );
  }

  @override
  Widget build(BuildContext context) {
    final needed = mornyeGroundNeeded(context, ref);
    // Read here so a level or quality change rebuilds the ground.
    ref.watch(mornyeGlassClarityLevelProvider);
    MediaQuery.sizeOf(context);
    if (needed) {
      _schedule();
    } else if (_controller.hasGround) {
      _built = null;
      _controller.release();
    }
    return MornyeArtworkGroundScope(
      controller: _controller,
      overlays: true,
      child: widget.child,
    );
  }
}
