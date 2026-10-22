import 'dart:async';
import 'dart:developer' show TimelineTask;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:spotiflac_android/utils/logger.dart';

final _log = AppLogger('MornyeArtworkGlass');

/// The artwork glass shader, loaded once at app start.
abstract final class MornyeArtworkGlassProgram {
  static const asset = 'assets/shaders/mornye_artwork_glass.frag';

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
      final task = TimelineTask()..start('Mornye artwork glass: prepare');
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
        MornyeArtworkGlassRender.configure(
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
enum MornyeArtworkGlassMode {
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
MornyeArtworkGlassMode mornyeArtworkGlassMode({
  required bool translucent,
  required bool lens,
  required bool programReady,
}) => !translucent
    ? MornyeArtworkGlassMode.opaque
    : lens && programReady
    ? MornyeArtworkGlassMode.refracted
    : MornyeArtworkGlassMode.lite;

/// A pre-blurred ground image and the colour around it.
@immutable
class MornyeGround {
  const MornyeGround(this.image, {required this.edge});

  final ui.Image image;
  final Color edge;

  int get bytes => image.width * image.height * 4;
}

/// Width of every ground image. Blurred by at least sigma 6, about 0.9 px
/// per logical pixel on a phone is enough.
const kMornyeGroundWidth = 384;

/// Height cap of a ground image (about 1.5 MB at full width).
const kMornyeGroundMaxHeight = 1024;

/// Paints a ground in logical pixels of [size]; [cover] is the decoded
/// artwork, or null without one.
typedef MornyeGroundPainter =
    void Function(Canvas canvas, Size size, ui.Image? cover);

/// How long the last ground took, for logs and the performance HUD.
@immutable
class MornyeGroundTiming {
  const MornyeGroundTiming({
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
abstract final class MornyeGroundBuilder {
  /// The last player ground's timing.
  static final lastPlayer = ValueNotifier<MornyeGroundTiming?>(null);

  static Future<ui.Image?> build({
    required String label,
    required Size size,
    required ImageProvider? cover,
    required MornyeGroundPainter paint,
    required double sigma,
    ValueNotifier<MornyeGroundTiming?>? timing,
  }) async {
    if (size.isEmpty) return null;
    final watch = Stopwatch()..start();
    final task = TimelineTask()..start('Mornye ground: $label');
    try {
      final image = cover == null ? null : await _decode(cover);
      final decoded = watch.elapsed;
      try {
        final scale = math.min(
          kMornyeGroundWidth / size.width,
          kMornyeGroundMaxHeight / size.height,
        );
        final width = (size.width * scale).round().clamp(1, kMornyeGroundWidth);
        final height = (size.height * scale).round().clamp(
          1,
          kMornyeGroundMaxHeight,
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
        final result = MornyeGroundTiming(
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
      width: kMornyeGroundWidth,
      height: kMornyeGroundWidth,
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
class MornyeGroundController extends ChangeNotifier {
  MornyeGroundController({
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

  MornyeGround? _current;
  MornyeGround? _previous;
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
  MornyeGround? get from => _previous ?? _current;
  MornyeGround? get to => _current;
  double get mix => _previous == null ? 1 : _mix.value;
  bool get hasGround => _current != null;
  Color? get edge => _current?.edge;

  int get bytes => (_current?.bytes ?? 0) + (_previous?.bytes ?? 0);

  void show(MornyeGround ground, {bool crossfade = false}) {
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
    MornyeGroundBudget.admit(this);
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
    MornyeGroundBudget.remove(this);
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
    MornyeGroundBudget.remove(this);
    super.dispose();
  }
}

/// The memory budget for every ground image held at once.
abstract final class MornyeGroundBudget {
  static const maxBytes = 6 * 1024 * 1024;
  static final _owners = <MornyeGroundController>{};

  static int get bytes => _owners.fold(0, (sum, owner) => sum + owner.bytes);

  @visibleForTesting
  static int get owners => _owners.length;

  /// Registers [owner]'s images, releasing the least recently painted page
  /// grounds beyond [maxBytes].
  static void admit(MornyeGroundController owner) {
    _owners.add(owner);
    while (bytes > maxBytes) {
      MornyeGroundController? oldest;
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

  static void remove(MornyeGroundController owner) => _owners.remove(owner);
}

/// Provides a ground to the glass below.
///
/// The player's scope also reaches its overlays ([overlays]); a page's
/// scope ([page]) reaches only the header controls that opt in, through
/// [MornyeArtworkGroundScope.pageOf].
class MornyeArtworkGroundScope extends InheritedWidget {
  const MornyeArtworkGroundScope({
    super.key,
    required this.controller,
    this.overlays = false,
    this.page = false,
    this.overlay = false,
    required super.child,
  });

  final MornyeGroundController controller;

  /// Overlays opened from here (menus, sheets) draw from this ground too.
  final bool overlays;

  /// A page's ground, active only below [MornyeHeaderControls].
  final bool page;

  /// Provided again inside an overlay route: its glass is decided once.
  final bool overlay;

  static MornyeArtworkGroundScope? _of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MornyeArtworkGroundScope>();

  /// The ground glass at [context] draws from, if any.
  static MornyeGroundController? maybeOf(BuildContext context) {
    final scope = _of(context);
    return scope == null || scope.page ? null : scope.controller;
  }

  /// Whether glass at [context] sits in an overlay route.
  static bool inOverlay(BuildContext context) => _of(context)?.overlay ?? false;

  /// The page's ground, for header controls to opt in.
  static MornyeGroundController? pageOf(BuildContext context) {
    final scope = _of(context);
    return scope != null && scope.page ? scope.controller : null;
  }

  /// The ground an overlay opened from [context] takes, if any.
  static MornyeGroundController? forOverlays(BuildContext context) {
    final scope = context
        .getInheritedWidgetOfExactType<MornyeArtworkGroundScope>();
    return scope != null && (scope.overlays || scope.overlay)
        ? scope.controller
        : null;
  }

  /// Wraps an overlay route's content with [controller], if any.
  static Widget wrapOverlay(MornyeGroundController? controller, Widget child) =>
      controller == null
      ? child
      : MornyeArtworkGroundScope(
          controller: controller,
          overlay: true,
          child: child,
        );

  @override
  bool updateShouldNotify(MornyeArtworkGroundScope oldWidget) =>
      controller != oldWidget.controller ||
      overlays != oldWidget.overlays ||
      page != oldWidget.page ||
      overlay != oldWidget.overlay;
}

/// A glass surface drawn from a ground: [fill] over the (refracted) ground,
/// below [child]. The caller clips it and paints its rim.
class MornyeArtworkGlassSurface extends StatefulWidget {
  const MornyeArtworkGlassSurface({
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

  final MornyeGroundController controller;

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
  State<MornyeArtworkGlassSurface> createState() =>
      _MornyeArtworkGlassSurfaceState();
}

class _MornyeArtworkGlassSurfaceState extends State<MornyeArtworkGlassSurface> {
  // Decided when the surface appears; never switched mid-animation.
  final ui.FragmentProgram? _program = MornyeArtworkGlassProgram.loaded;
  bool? _overlayReady;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MornyeArtworkGroundScope.inOverlay(context)) {
      _overlayReady ??= widget.controller.hasGround;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = _overlayReady == false
        ? MornyeArtworkGlassMode.opaque
        : mornyeArtworkGlassMode(
            translucent: true,
            lens: widget.lens,
            programReady: _program != null,
          );
    return MornyeArtworkGlassRender(
      controller: widget.controller,
      program: mode == MornyeArtworkGlassMode.refracted ? _program : null,
      opaque: mode == MornyeArtworkGlassMode.opaque,
      fill: mode == MornyeArtworkGlassMode.opaque
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

/// The render side of [MornyeArtworkGlassSurface].
class MornyeArtworkGlassRender extends SingleChildRenderObjectWidget {
  const MornyeArtworkGlassRender({
    super.key,
    required this.controller,
    required this.program,
    required this.opaque,
    required this.fill,
    required this.radius,
    required this.squircle,
    required this.band,
    required this.bend,
    required this.dispersion,
    required this.scroll,
    super.child,
  });

  final MornyeGroundController controller;

  /// Null draws the ground without refraction.
  final ui.FragmentProgram? program;
  final bool opaque;
  final Color fill;
  final double radius;
  final bool squircle;
  final double band;
  final double bend;
  final double dispersion;

  /// Pages repaint while scrolling: the ground moves under fixed controls.
  final Listenable? scroll;

  /// Sets the shader's uniforms; the order matches the .frag file.
  static void configure(
    ui.FragmentShader shader, {
    required Size size,
    required Rect panel,
    required Rect ground,
    required ui.Image image,
    required ui.Image next,
    required double mix,
    required double radius,
    required bool squircle,
    required double band,
    required double bend,
    required double dispersion,
    required Color edge,
  }) {
    var index = 0;
    void put(double value) => shader.setFloat(index++, value);
    put(size.width);
    put(size.height);
    for (final rect in [panel, ground]) {
      put(rect.left);
      put(rect.top);
      put(rect.width);
      put(rect.height);
    }
    put(radius);
    put(squircle ? 1 : 0);
    put(band);
    put(bend);
    put(dispersion);
    put(edge.r * edge.a);
    put(edge.g * edge.a);
    put(edge.b * edge.a);
    put(edge.a);
    put(mix);
    shader
      ..setImageSampler(0, image)
      ..setImageSampler(1, next);
  }

  @override
  RenderMornyeArtworkGlass createRenderObject(BuildContext context) =>
      RenderMornyeArtworkGlass(
        controller: controller,
        program: program,
        opaque: opaque,
        fill: fill,
        radius: radius,
        squircle: squircle,
        band: band,
        bend: bend,
        dispersion: dispersion,
        scroll: scroll,
      );

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as RenderMornyeArtworkGlass)
      ..controller = controller
      ..program = program
      ..opaque = opaque
      ..fill = fill
      ..radius = radius
      ..squircle = squircle
      ..band = band
      ..bend = bend
      ..dispersion = dispersion
      ..scroll = scroll;
  }
}

class RenderMornyeArtworkGlass extends RenderProxyBox {
  RenderMornyeArtworkGlass({
    required MornyeGroundController controller,
    required ui.FragmentProgram? program,
    required bool opaque,
    required Color fill,
    required this.radius,
    required this.squircle,
    required this.band,
    required this.bend,
    required this.dispersion,
    Listenable? scroll,
  }) : _controller = controller,
       _program = program,
       _opaque = opaque,
       _fill = fill,
       _scroll = scroll;

  MornyeGroundController _controller;
  MornyeGroundController get controller => _controller;
  set controller(MornyeGroundController value) {
    if (identical(value, _controller)) return;
    if (attached) _controller.removeListener(markNeedsPaint);
    _controller = value;
    if (attached) _controller.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  ui.FragmentProgram? _program;
  ui.FragmentShader? _shader;

  /// Whether the shader draws this surface (for tests and diagnostics).
  bool get refracts => _program != null && !_opaque;
  set program(ui.FragmentProgram? value) {
    if (identical(value, _program)) return;
    _program = value;
    _shader?.dispose();
    _shader = null;
    markNeedsPaint();
  }

  bool _opaque;
  bool get opaque => _opaque;
  set opaque(bool value) {
    if (value == _opaque) return;
    _opaque = value;
    markNeedsPaint();
  }

  Color _fill;
  set fill(Color value) {
    if (value == _fill) return;
    _fill = value;
    markNeedsPaint();
  }

  double radius;
  bool squircle;
  double band;
  double bend;
  double dispersion;

  Listenable? _scroll;
  set scroll(Listenable? value) {
    if (identical(value, _scroll)) return;
    if (attached) _scroll?.removeListener(markNeedsPaint);
    _scroll = value;
    if (attached) _scroll?.addListener(markNeedsPaint);
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _controller.addListener(markNeedsPaint);
    _scroll?.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _controller.removeListener(markNeedsPaint);
    _scroll?.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _shader?.dispose();
    super.dispose();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final local = offset & size;
    if (!_opaque) _paintGround(canvas, offset);
    canvas.drawRect(local, Paint()..color = _fill);
    super.paint(context, offset);
  }

  void _paintGround(Canvas canvas, Offset offset) {
    final controller = _controller..markPainted();
    final local = offset & size;
    final from = controller.from;
    final to = controller.to;
    final groundRect = controller.rect;
    final edge = controller.edge ?? _fill.withValues(alpha: 1);
    if (from == null ||
        to == null ||
        groundRect == null ||
        groundRect.isEmpty) {
      canvas.drawRect(local, Paint()..color = edge);
    } else {
      final panel = MatrixUtils.transformRect(
        getTransformTo(null),
        Offset.zero & size,
      );
      final program = _program;
      if (program != null) {
        final shader = _shader ??= program.fragmentShader();
        configure(
          shader,
          panel: panel,
          ground: groundRect,
          from: from,
          to: to,
          edge: edge,
        );
        canvas
          ..save()
          ..translate(offset.dx, offset.dy)
          ..drawRect(Offset.zero & size, Paint()..shader = shader)
          ..restore();
      } else {
        canvas.drawRect(local, Paint()..color = edge);
        _drawPlain(canvas, offset, panel, groundRect, from.image, 1);
        if (!identical(from, to)) {
          _drawPlain(
            canvas,
            offset,
            panel,
            groundRect,
            to.image,
            controller.mix,
          );
        }
      }
    }
    if (controller.fade > 0) {
      canvas.drawRect(
        local,
        Paint()
          ..color = controller.fadeColor.withValues(
            alpha: controller.fadeColor.a * controller.fade,
          ),
      );
    }
  }

  /// Sets the shader for this paint.
  void configure(
    ui.FragmentShader shader, {
    required Rect panel,
    required Rect ground,
    required MornyeGround from,
    required MornyeGround to,
    required Color edge,
  }) => MornyeArtworkGlassRender.configure(
    shader,
    size: size,
    panel: panel,
    ground: ground,
    image: from.image,
    next: to.image,
    mix: identical(from, to) ? 0 : _controller.mix,
    radius: radius,
    squircle: squircle,
    band: band,
    bend: bend,
    dispersion: dispersion,
    edge: edge,
  );

  void _drawPlain(
    Canvas canvas,
    Offset offset,
    Rect panel,
    Rect ground,
    ui.Image image,
    double opacity,
  ) {
    final mapping = mornyeGroundMapping(
      panel: panel,
      ground: ground,
      image: Size(image.width.toDouble(), image.height.toDouble()),
      local: size,
    );
    if (mapping == null || opacity <= 0) return;
    canvas.drawImageRect(
      image,
      mapping.source,
      mapping.target.shift(offset),
      Paint()
        ..filterQuality = FilterQuality.low
        ..color = Color.fromRGBO(0, 0, 0, opacity),
    );
  }
}

/// Where a panel at [panel] (on screen) meets a ground at [ground]: the
/// [image] pixels under it and where they land in the panel's [local] size.
/// Null when the panel is off the ground.
({Rect source, Rect target})? mornyeGroundMapping({
  required Rect panel,
  required Rect ground,
  required Size image,
  required Size local,
}) {
  final shared = panel.intersect(ground);
  if (shared.width <= 0 || shared.height <= 0) return null;
  final sx = image.width / ground.width;
  final sy = image.height / ground.height;
  final px = local.width / panel.width;
  final py = local.height / panel.height;
  return (
    source: Rect.fromLTRB(
      (shared.left - ground.left) * sx,
      (shared.top - ground.top) * sy,
      (shared.right - ground.left) * sx,
      (shared.bottom - ground.top) * sy,
    ),
    target: Rect.fromLTRB(
      (shared.left - panel.left) * px,
      (shared.top - panel.top) * py,
      (shared.right - panel.left) * px,
      (shared.bottom - panel.top) * py,
    ),
  );
}

/// How an anchored artwork is painted into its page's ground: cover-fit,
/// optionally rounded, under [gradient] (stops and colours top to bottom).
@immutable
class MornyeGroundLayout {
  const MornyeGroundLayout({
    this.alignment = Alignment.center,
    this.radius = 0,
    this.stops = const [],
    this.colors = const [],
  });

  final Alignment alignment;
  final double radius;
  final List<double> stops;
  final List<Color> colors;

  @override
  bool operator ==(Object other) =>
      other is MornyeGroundLayout &&
      other.alignment == alignment &&
      other.radius == radius &&
      listEquals(other.stops, stops) &&
      listEquals(other.colors, colors);

  @override
  int get hashCode => Object.hash(
    alignment,
    radius,
    Object.hashAll(stops),
    Object.hashAll(colors),
  );
}

/// Marks the artwork a page's header glass draws from. Its box is the
/// ground's rect on screen; [fade] follows an artist header's collapse.
class MornyeGroundAnchor extends SingleChildRenderObjectWidget {
  const MornyeGroundAnchor({
    super.key,
    required this.layout,
    this.fade = 0,
    super.child,
  });

  final MornyeGroundLayout layout;
  final double fade;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderGroundAnchor(_MornyePageGroundState.of(context), layout, fade);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderGroundAnchor)
      ..host = _MornyePageGroundState.of(context)
      ..groundLayout = layout
      ..fade = fade;
  }
}

class _RenderGroundAnchor extends RenderProxyBox {
  _RenderGroundAnchor(this._host, this._layout, this._fade);

  _MornyePageGroundState? _host;
  set host(_MornyePageGroundState? value) {
    if (identical(value, _host)) return;
    _host?._release(this);
    _host = value;
    if (attached) _host?._claim(this);
  }

  MornyeGroundLayout _layout;
  MornyeGroundLayout get groundLayout => _layout;
  set groundLayout(MornyeGroundLayout value) {
    if (value == _layout) return;
    _layout = value;
    _host?._changed(this);
  }

  double _fade;
  set fade(double value) {
    if (value == _fade) return;
    _fade = value;
    _host?._fade(this, value);
  }

  Rect? get globalRect => attached && hasSize
      ? MatrixUtils.transformRect(getTransformTo(null), Offset.zero & size)
      : null;

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _host?._claim(this);
  }

  @override
  void detach() {
    _host?._release(this);
    super.detach();
  }

  @override
  void performLayout() {
    final previous = hasSize ? size : null;
    super.performLayout();
    if (size != previous) _host?._changed(this);
  }
}

/// Lays the page's pre-blurred ground over its anchored artwork at
/// [opacity], so a header softens as it scrolls without a live blur. Place it
/// to fill the [MornyeGroundAnchor]'s box, above the artwork and its gradient
/// (the ground already holds both). Paints nothing without a ground.
class MornyeGroundVeil extends StatelessWidget {
  const MornyeGroundVeil({super.key, required this.opacity});

  final double opacity;

  @override
  Widget build(BuildContext context) {
    final controller = MornyeArtworkGroundScope.pageOf(context);
    if (controller == null || opacity <= 0) return const SizedBox.shrink();
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _GroundVeilPainter(controller, opacity.clamp(0.0, 1.0)),
      ),
    );
  }
}

class _GroundVeilPainter extends CustomPainter {
  _GroundVeilPainter(this.controller, this.opacity)
    : super(repaint: controller);

  final MornyeGroundController controller;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    controller.markPainted();
    final image = controller.to?.image;
    if (image == null || size.isEmpty) return;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Offset.zero & size,
      Paint()
        ..color = Color.fromRGBO(0, 0, 0, opacity)
        ..filterQuality = FilterQuality.medium,
    );
  }

  @override
  bool shouldRepaint(_GroundVeilPainter oldDelegate) =>
      !identical(controller, oldDelegate.controller) ||
      opacity != oldDelegate.opacity;
}

/// Builds the ground for a detail page (album or artist) from [source] and
/// the page's [MornyeGroundAnchor]; header controls draw from it.
class MornyePageGround extends StatefulWidget {
  const MornyePageGround({
    super.key,
    required this.source,
    required this.surface,
    required this.sigma,
    required this.enabled,
    required this.cover,
    required this.child,
  });

  /// The cover's path or URL; identifies the artwork.
  final String? source;

  /// The page colour around the artwork.
  final Color surface;
  final double sigma;

  /// False while glass is off: no ground is built.
  final bool enabled;
  final ImageProvider? cover;
  final Widget child;

  @override
  State<MornyePageGround> createState() => _MornyePageGroundState();
}

class _MornyePageGroundState extends State<MornyePageGround>
    with SingleTickerProviderStateMixin {
  late final MornyeGroundController _controller = MornyeGroundController(
    vsync: this,
    rectOf: () => _anchor?.globalRect,
  )..onNeeded = _rebuildReleased;
  _RenderGroundAnchor? _anchor;
  Object? _built;
  int _generation = 0;
  bool _scheduled = false;

  static _MornyePageGroundState? of(BuildContext context) =>
      context.findAncestorStateOfType<_MornyePageGroundState>();

  void _rebuildReleased() {
    _built = null;
    _schedule();
  }

  void _claim(_RenderGroundAnchor anchor) {
    _anchor = anchor;
    _controller.setFade(anchor._fade, widget.surface);
    _schedule();
  }

  void _release(_RenderGroundAnchor anchor) {
    if (identical(_anchor, anchor)) _anchor = null;
  }

  void _changed(_RenderGroundAnchor anchor) {
    if (identical(_anchor, anchor)) _schedule();
  }

  void _fade(_RenderGroundAnchor anchor, double fade) {
    if (identical(_anchor, anchor)) _controller.setFade(fade, widget.surface);
  }

  @override
  void didUpdateWidget(MornyePageGround oldWidget) {
    super.didUpdateWidget(oldWidget);
    _schedule();
  }

  void _schedule() {
    if (_scheduled || !mounted) return;
    _scheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _scheduled = false;
      if (mounted) unawaited(_build());
    });
  }

  Future<void> _build() async {
    final anchor = _anchor;
    if (!widget.enabled || anchor == null || !anchor.hasSize) {
      if (!widget.enabled && _controller.hasGround) _controller.release();
      if (!widget.enabled) _built = null;
      return;
    }
    final size = anchor.size;
    final layout = anchor.groundLayout;
    final key = (widget.source, size, layout, widget.sigma, widget.surface);
    // Built, or being built: a ground is made once per input.
    if (key == _built) return;
    _built = key;
    final generation = ++_generation;
    final surface = widget.surface;
    final image = await MornyeGroundBuilder.build(
      label: 'page',
      size: size,
      cover: widget.cover,
      sigma: widget.sigma,
      paint: (canvas, size, cover) {
        final rect = Offset.zero & size;
        canvas.drawRect(rect, Paint()..color = surface);
        if (cover != null) {
          canvas.save();
          if (layout.radius > 0) {
            canvas.clipRRect(
              RRect.fromRectAndRadius(rect, Radius.circular(layout.radius)),
            );
          }
          MornyeGroundBuilder.paintCover(
            canvas,
            cover,
            rect,
            alignment: layout.alignment,
          );
          canvas.restore();
        }
        if (layout.colors.length >= 2) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: layout.stops.length == layout.colors.length
                    ? layout.stops
                    : null,
                colors: layout.colors,
              ).createShader(rect),
          );
        }
      },
    );
    if (image == null) return;
    if (!mounted || generation != _generation) {
      image.dispose();
      return;
    }
    _controller.show(MornyeGround(image, edge: surface));
  }

  @override
  void dispose() {
    _generation++;
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MornyeArtworkGroundScope(
    controller: _controller,
    page: true,
    child: widget.child,
  );
}
