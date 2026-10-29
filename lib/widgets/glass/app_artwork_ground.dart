import 'dart:async';
import 'dart:developer' show TimelineTask;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:sistrum/utils/logger.dart';

final _log = AppLogger('AppArtworkGlass');

/// A pre-blurred ground image and the colour around it.
@immutable
class AppGround {
  const AppGround(this.image, {required this.edge});

  final ui.Image image;
  final Color edge;

  int get bytes => image.width * image.height * 4;
}

/// Width of every ground image. Blurred by at least sigma 6, about 0.9 px
/// per logical pixel on a phone is enough.
const kAppGroundWidth = 384;

/// Height cap of a ground image (about 1.5 MB at full width).
const kAppGroundMaxHeight = 1024;

/// Paints a ground in logical pixels of [size]; [cover] is the decoded
/// artwork, or null without one.
typedef AppGroundPainter =
    void Function(Canvas canvas, Size size, ui.Image? cover);

/// How long the last ground took, for logs and the performance HUD.
@immutable
class AppGroundTiming {
  const AppGroundTiming({
    required this.label,
    required this.decode,
    required this.compose,
  });

  final String label;
  final Duration decode;

  /// Composing and blurring on the raster thread, until the image is ready.
  final Duration compose;

  Duration get total => decode + compose;
}

/// Builds ground images with dart:ui only: no widget capture, no read of the
/// screen.
abstract final class AppGroundBuilder {
  /// The last player ground's timing.
  static final lastPlayer = ValueNotifier<AppGroundTiming?>(null);

  /// Count of started ground builds; tests assert rebuild frequency
  /// (PERF-605) and nothing else reads it.
  static int debugBuildCount = 0;

  static Future<ui.Image?> build({
    required String label,
    required Size size,
    required ImageProvider? cover,
    required AppGroundPainter paint,
    required double sigma,
    ValueNotifier<AppGroundTiming?>? timing,
  }) async {
    debugBuildCount++;
    if (size.isEmpty) return null;
    final watch = Stopwatch()..start();
    final task = TimelineTask()..start('Sistrum ground: $label');
    try {
      final image = cover == null ? null : await _decode(cover);
      final decoded = watch.elapsed;
      try {
        final scale = math.min(
          kAppGroundWidth / size.width,
          kAppGroundMaxHeight / size.height,
        );
        final width = (size.width * scale).round().clamp(1, kAppGroundWidth);
        final height = (size.height * scale).round().clamp(
          1,
          kAppGroundMaxHeight,
        );
        final bounds = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder, bounds);
        canvas.saveLayer(
          bounds,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: sigma * scale,
              sigmaY: sigma * scale,
              tileMode: TileMode.clamp,
            ),
        );
        canvas.scale(scale);
        paint(canvas, size, image);
        canvas.restore();
        final picture = recorder.endRecording();
        final ground = await picture.toImage(width, height);
        picture.dispose();
        final result = AppGroundTiming(
          label: label,
          decode: decoded,
          compose: watch.elapsed - decoded,
        );
        timing?.value = result;
        _log.d(
          'Ground $label ready in ${result.total.inMilliseconds} ms '
          '(decode ${result.decode.inMilliseconds} ms)',
        );
        return ground;
      } finally {
        image?.dispose();
      }
    } catch (error) {
      _log.w('Ground $label failed: $error');
      return null;
    } finally {
      task.finish();
    }
  }

  static Future<ui.Image?> _decode(ImageProvider cover) {
    final provider = ResizeImage(
      cover,
      width: kAppGroundWidth,
      height: kAppGroundWidth,
      policy: ResizeImagePolicy.fit,
    );
    final result = Completer<ui.Image?>();
    final stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    void finish(ui.Image? image) {
      stream.removeListener(listener);
      if (!result.isCompleted) result.complete(image);
      // The ground keeps only its blurred copy; drop the decoded sample.
      unawaited(provider.evict());
    }

    listener = ImageStreamListener(
      (info, _) {
        final image = info.image.clone();
        info.dispose();
        finish(image);
      },
      // Unreadable covers report here; no timer outlives the request.
      onError: (_, _) => finish(null),
    );
    stream.addListener(listener);
    return result.future;
  }

  /// Paints [cover] into [rect] like an Image with BoxFit.cover.
  static void paintCover(
    Canvas canvas,
    ui.Image cover,
    Rect rect, {
    Alignment alignment = Alignment.center,
  }) => paintImage(
    canvas: canvas,
    rect: rect,
    image: cover,
    fit: BoxFit.cover,
    alignment: alignment,
    filterQuality: FilterQuality.medium,
  );
}

/// Holds one screen's ground, where it sits on screen and its crossfade.
/// Listeners repaint; nothing rebuilds.
class AppGroundController extends ChangeNotifier {
  AppGroundController({
    required TickerProvider vsync,
    required Rect? Function() rectOf,
    this.persistent = false,
  }) : _rectOf = rectOf,
       _mix = AnimationController(
         vsync: vsync,
         duration: const Duration(milliseconds: 380),
       ) {
    _mix.addListener(notifyListeners);
    _mix.addStatusListener((status) {
      if (status == AnimationStatus.completed) _dropPrevious();
    });
  }

  Rect? Function() _rectOf;
  final AnimationController _mix;

  /// The player's ground is never evicted for a page's.
  final bool persistent;

  AppGround? _current;
  AppGround? _previous;
  bool _disposed = false;
  bool _released = false;
  int _lastPainted = 0;
  static int _paintClock = 0;

  /// Called when the ground is needed again after the budget released it.
  VoidCallback? onNeeded;

  /// The ground's rect on screen, read at paint.
  Rect? get rect => _rectOf();
  set rectOf(Rect? Function() value) => _rectOf = value;

  /// Artist pages fade their artwork to the surface while collapsing.
  double _fade = 0;
  Color _fadeColor = const Color(0x00000000);
  double get fade => _fade;
  Color get fadeColor => _fadeColor;
  void setFade(double fade, Color color) {
    if (fade == _fade && color == _fadeColor) return;
    _fade = fade;
    _fadeColor = color;
    notifyListeners();
  }

  /// The image fading out (during a crossfade) and the one shown.
  AppGround? get from => _previous ?? _current;
  AppGround? get to => _current;
  double get mix => _previous == null ? 1 : _mix.value;
  bool get hasGround => _current != null;
  Color? get edge => _current?.edge;

  int get bytes => (_current?.bytes ?? 0) + (_previous?.bytes ?? 0);

  void show(AppGround ground, {bool crossfade = false}) {
    if (_disposed) {
      ground.image.dispose();
      return;
    }
    _dropPrevious();
    if (crossfade && _current != null) {
      _previous = _current;
      _mix.forward(from: 0);
    } else {
      _current?.image.dispose();
    }
    _current = ground;
    _released = false;
    AppGroundBudget.admit(this);
    notifyListeners();
  }

  void _dropPrevious() {
    _previous?.image.dispose();
    _previous = null;
  }

  /// Frees the images; the glass shows the edge colour until [onNeeded]
  /// rebuilds them.
  void release() {
    _mix.stop();
    _dropPrevious();
    _current?.image.dispose();
    _current = null;
    _released = true;
    AppGroundBudget.remove(this);
    notifyListeners();
  }

  void markPainted() {
    _lastPainted = ++_paintClock;
    final needed = onNeeded;
    if (_released && needed != null) {
      _released = false;
      scheduleMicrotask(() {
        if (!_disposed) needed();
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _mix.dispose();
    _dropPrevious();
    _current?.image.dispose();
    _current = null;
    AppGroundBudget.remove(this);
    super.dispose();
  }
}

/// The memory budget for every ground image held at once.
abstract final class AppGroundBudget {
  static const maxBytes = 6 * 1024 * 1024;
  static final _owners = <AppGroundController>{};

  static int get bytes => _owners.fold(0, (sum, owner) => sum + owner.bytes);

  @visibleForTesting
  static int get owners => _owners.length;

  /// Registers [owner]'s images, releasing the least recently painted page
  /// grounds beyond [maxBytes].
  static void admit(AppGroundController owner) {
    _owners.add(owner);
    while (bytes > maxBytes) {
      AppGroundController? oldest;
      for (final candidate in _owners) {
        if (identical(candidate, owner) || candidate.persistent) continue;
        if (oldest == null || candidate._lastPainted < oldest._lastPainted) {
          oldest = candidate;
        }
      }
      if (oldest == null) break;
      oldest.release();
    }
  }

  static void remove(AppGroundController owner) => _owners.remove(owner);
}

/// Provides a ground to the glass below.
///
/// The player's scope also reaches its overlays ([overlays]); a page's
/// scope ([page]) reaches only the header controls that opt in, through
/// [AppArtworkGroundScope.pageOf].
class AppArtworkGroundScope extends InheritedWidget {
  const AppArtworkGroundScope({
    super.key,
    required this.controller,
    this.overlays = false,
    this.page = false,
    this.overlay = false,
    required super.child,
  });

  final AppGroundController controller;

  /// Overlays opened from here (menus, sheets) draw from this ground too.
  final bool overlays;

  /// A page's ground, active only below [AppHeaderControls].
  final bool page;

  /// Provided again inside an overlay route: its glass is decided once.
  final bool overlay;

  static AppArtworkGroundScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppArtworkGroundScope>();

  /// The ground glass at [context] draws from, if any.
  static AppGroundController? maybeOf(BuildContext context) {
    final scope = _of(context);
    return scope == null || scope.page ? null : scope.controller;
  }

  /// Whether glass at [context] sits in an overlay route.
  static bool inOverlay(BuildContext context) => _of(context)?.overlay ?? false;

  /// The page's ground, for header controls to opt in.
  static AppGroundController? pageOf(BuildContext context) {
    final scope = _of(context);
    return scope != null && scope.page ? scope.controller : null;
  }

  /// The ground an overlay opened from [context] takes, if any.
  static AppGroundController? forOverlays(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<AppArtworkGroundScope>();
    return scope != null && (scope.overlays || scope.overlay)
        ? scope.controller
        : null;
  }

  /// Wraps an overlay route's content with [controller], if any.
  static Widget wrapOverlay(AppGroundController? controller, Widget child) =>
      controller == null
      ? child
      : AppArtworkGroundScope(
          controller: controller,
          overlay: true,
          child: child,
        );

  @override
  bool updateShouldNotify(AppArtworkGroundScope oldWidget) =>
      controller != oldWidget.controller ||
      overlays != oldWidget.overlays ||
      page != oldWidget.page ||
      overlay != oldWidget.overlay;
}
