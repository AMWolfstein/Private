import 'dart:developer' show TimelineTask;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_glass_render.dart';

final _log = AppLogger('AppArtworkGlass');

/// The artwork glass shader, loaded once at app start.
abstract final class AppArtworkGlassProgram {
  static const asset = 'assets/shaders/app_artwork_glass.frag';

  /// The loaded program, or null while loading or where unsupported.
  static ui.FragmentProgram? loaded;
  static Future<ui.FragmentProgram?>? _loading;
  static Future<void>? _prepared;

  static Future<ui.FragmentProgram?> load() => _loading ??= () async {
    try {
      return loaded = await ui.FragmentProgram.fromAsset(asset);
    } catch (error) {
      _log.w('Artwork glass shader unavailable: $error');
      return null;
    }
  }();

  /// Draws the shader once offscreen, so its pipeline exists before the
  /// first menu opens.
  static Future<void> prepare() => _prepared ??= () async {
    final program = await load();
    if (program == null) return;
    await SchedulerBinding.instance.scheduleTask(() async {
      final task = TimelineTask()..start('Sistrum artwork glass: prepare');
      ui.Image? ground;
      ui.Image? output;
      final shader = program.fragmentShader();
      try {
        final seed = ui.PictureRecorder();
        Canvas(seed).drawRect(
          const Rect.fromLTWH(0, 0, 2, 2),
          Paint()..color = const Color(0xff808080),
        );
        final seedPicture = seed.endRecording();
        ground = await seedPicture.toImage(2, 2);
        seedPicture.dispose();
        const size = Size(24, 24);
        AppArtworkGlassRender.configure(
          shader,
          size: size,
          panel: Offset.zero & size,
          ground: Offset.zero & size,
          image: ground,
          next: ground,
          mix: 0,
          radius: 8,
          squircle: true,
          band: 6,
          bend: 2,
          dispersion: 1,
          edge: const Color(0xff808080),
        );
        final recorder = ui.PictureRecorder();
        Canvas(recorder).drawRect(Offset.zero & size, Paint()..shader = shader);
        final picture = recorder.endRecording();
        output = await picture.toImage(24, 24);
        picture.dispose();
      } catch (error) {
        _log.w('Artwork glass preparation failed: $error');
      } finally {
        shader.dispose();
        ground?.dispose();
        output?.dispose();
        task.finish();
      }
    }, Priority.idle);
  }();
}

/// How artwork glass draws, from the glass settings.
enum AppArtworkGlassMode {
  /// No glass: the surface's opaque fill.
  opaque,

  /// The blurred ground through the clip, plus tint and rim. No shader.
  lite,

  /// The shader: refraction and dispersion over the blurred ground.
  refracted,
}

/// [translucent] is the surface's glass state (quality, high contrast, blur);
/// [lens] is whether a lens would be allowed there (full glass above Level
/// 1, Impeller, animations); [programReady] whether the shader was loaded
/// when the surface appeared.
AppArtworkGlassMode appArtworkGlassMode({
  required bool translucent,
  required bool lens,
  required bool programReady,
}) => !translucent
    ? AppArtworkGlassMode.opaque
    : lens && programReady
    ? AppArtworkGlassMode.refracted
    : AppArtworkGlassMode.lite;

/// A glass surface drawn from a ground: [fill] over the (refracted) ground,
/// below [child]. The caller clips it and paints its rim.
class AppArtworkGlassSurface extends StatefulWidget {
  const AppArtworkGlassSurface({
    super.key,
    required this.controller,
    required this.lens,
    required this.fill,
    required this.opaqueFill,
    required this.radius,
    required this.squircle,
    required this.refractionDepth,
    required this.refractionWidth,
    required this.dispersion,
    required this.child,
  });

  final AppGroundController controller;

  /// Refraction allowed (full glass above Level 1, Impeller, animations).
  final bool lens;
  final Color fill;

  /// Shown for an overlay's lifetime when it opened before its ground.
  final Color opaqueFill;
  final double radius;
  final bool squircle;
  final double refractionDepth;
  final double refractionWidth;
  final double dispersion;
  final Widget child;

  @override
  State<AppArtworkGlassSurface> createState() => _AppArtworkGlassSurfaceState();
}

class _AppArtworkGlassSurfaceState extends State<AppArtworkGlassSurface> {
  // Decided when the surface appears; never switched mid-animation.
  final ui.FragmentProgram? _program = AppArtworkGlassProgram.loaded;
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
    final mode = _overlayReady == false
        ? AppArtworkGlassMode.opaque
        : appArtworkGlassMode(
            translucent: true,
            lens: widget.lens,
            programReady: _program != null,
          );
    return AppArtworkGlassRender(
      controller: widget.controller,
      program: mode == AppArtworkGlassMode.refracted ? _program : null,
      opaque: mode == AppArtworkGlassMode.opaque,
      fill: mode == AppArtworkGlassMode.opaque
          ? widget.opaqueFill
          : widget.fill,
      radius: widget.radius,
      squircle: widget.squircle,
      band: widget.refractionWidth,
      bend: widget.refractionWidth * widget.refractionDepth,
      dispersion: widget.dispersion,
      scroll: Scrollable.maybeOf(context)?.position,
      child: widget.child,
    );
  }
}
