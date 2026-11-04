import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/widgets/glass/artwork/app_artwork_ground.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_look.dart';

final _log = AppLogger('AppScreenGround');

/// The boundary around the app's content (below the navigator's routes and
/// above nothing else of ours), which a sheet captures once as it opens.
final GlobalKey kAppScreenCaptureKey = GlobalKey(
  debugLabel: 'app-screen-capture',
);

/// Wraps the app's content so sheets can capture what lies under them.
class AppScreenCapture extends StatelessWidget {
  const AppScreenCapture({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      RepaintBoundary(key: kAppScreenCaptureKey, child: child);
}

/// A sheet's ground: the screen under it, captured and blurred once as it
/// opens, so its glass draws a still image instead of copying and blurring
/// the page on every frame (Impeller re-runs a `BackdropFilter` each frame,
/// over the whole sheet, whenever anything on screen moves).
///
/// The page under a modal sheet sits below its barrier and the sheet's 0.78
/// tint; what still moves there (a video, a progress bar) stops moving under
/// the glass. Owner decision, 2026-11-04.
abstract final class AppScreenGround {
  /// Captures and blurs the screen for a sheet opened from [context], or
  /// null when its glass would not read a backdrop or the capture fails (the
  /// sheet then keeps its live FROSTED read). Call before pushing the route:
  /// the capture is the last frame drawn. [barrier] is the sheet's barrier
  /// colour, which the live read would have blurred too.
  static AppGround? capture(BuildContext context, {required Color barrier}) {
    final container = ProviderScope.containerOf(context, listen: false);
    if (!container.read(appBlurEnabledProvider) ||
        container.read(appGlassLevelProvider) == AppGlassLevel.flat) {
      return null;
    }
    final boundary = kAppScreenCaptureKey.currentContext?.findRenderObject();
    if (boundary is! RenderRepaintBoundary || !boundary.hasSize) return null;
    final size = boundary.size;
    if (size.isEmpty) return null;
    final look = container.read(appGlassLookProvider);
    final scale = kAppGroundWidth / size.width;
    final width = kAppGroundWidth;
    final height = (size.height * scale).round().clamp(1, kAppGroundMaxHeight);
    final edge = Color.alphaBlend(
      barrier,
      Theme.of(context).scaffoldBackgroundColor,
    );
    ui.Image? screen;
    try {
      screen = boundary.toImageSync(pixelRatio: scale);
      final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
      final recorder = ui.PictureRecorder();
      Canvas(recorder, bounds)
        ..saveLayer(
          bounds,
          Paint()..imageFilter = appFrostImageFilter(look, scale),
        )
        ..drawImageRect(
          screen,
          Rect.fromLTWH(
            0,
            0,
            screen.width.toDouble(),
            screen.height.toDouble(),
          ),
          bounds,
          Paint()..filterQuality = FilterQuality.low,
        )
        ..restore()
        // The barrier is one flat colour, so it can go over the blur.
        ..drawRect(bounds, Paint()..color = barrier);
      final picture = recorder.endRecording();
      final image = picture.toImageSync(width, height);
      picture.dispose();
      return AppGround(image, edge: edge);
    } catch (error) {
      // Debug builds refuse a boundary that has not painted yet.
      _log.w('Screen ground skipped: $error');
      return null;
    } finally {
      screen?.dispose();
    }
  }

  /// [child] with [ground] as the ground its glass draws from, for the
  /// lifetime of the route it is built in; [child] alone without one.
  static Widget wrap(AppGround? ground, Widget child) => ground == null
      ? child
      : _AppScreenGroundScope(ground: ground, child: child);
}

class _AppScreenGroundScope extends StatefulWidget {
  const _AppScreenGroundScope({required this.ground, required this.child});

  /// Owned by the caller, which disposes it when the route is gone; the
  /// scope's controller holds a clone.
  final AppGround ground;
  final Widget child;

  @override
  State<_AppScreenGroundScope> createState() => _AppScreenGroundScopeState();
}

class _AppScreenGroundScopeState extends State<_AppScreenGroundScope>
    with SingleTickerProviderStateMixin {
  late final AppGroundController _controller = AppGroundController(
    vsync: this,
    // The capture covers the app's content, which starts at the origin.
    rectOf: _screenRect,
    persistent: true,
  )..show(AppGround(widget.ground.image.clone(), edge: widget.ground.edge));

  static Rect? _screenRect() {
    final box = kAppScreenCaptureKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  // Not an overlay ground: a menu opened from the sheet sits over the sheet,
  // which this capture does not hold, so it keeps its own material.
  Widget build(BuildContext context) =>
      AppArtworkGroundScope(controller: _controller, child: widget.child);
}
