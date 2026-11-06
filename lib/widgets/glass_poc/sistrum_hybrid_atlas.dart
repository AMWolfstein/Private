// Experimental shared backdrop atlas for Sistrum Hybrid (developer POC only).
//
// Inspired by PlugFox/g1455 (MIT): one capture of what is painted under all
// glass surfaces, packed into one texture, blurred once at low resolution and
// sampled by every surface, instead of one `BackdropFilter` (one full-frame
// backdrop flip in Impeller) per surface. No g1455 code is copied.
//
// Two deliberate differences from g1455:
//
// - **Same-frame capture.** g1455 records in a post-frame callback, so its
//   surfaces show the previous frame (its host documents the one-frame delay
//   as structural). Here the first atlas surface to paint in a frame records
//   the backdrop layer tree that was just painted in the same pipeline pass,
//   so the glass never shows a stale background while the list scrolls.
// - **Declared invalidation plus a check.** The page declares what changes the
//   backdrop (scroll position, background animation); those repaint the atlas
//   surfaces. Every capture compares a signature of the backdrop layer tree,
//   and a post-frame check counts any change that arrived undeclared
//   (`late_invalidations`, which then repaints a frame late).
//
// The capture walks the composited layer tree and redraws its pictures into a
// `PictureRecorder` (offset, transform, clip, opacity, colour and image filter
// layers). Any other layer type stops the atlas with a named reason, and the
// surfaces fall back to `BackdropFilter`. `Picture.toImageSync` makes a GPU
// texture: no CPU readback and no wait on the GPU.

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// Largest atlas side, in texture pixels.
const int kSistrumAtlasMaxSide = 2048;

/// Experimental atlas capture resolution (Glass POC only). [baseline] is the
/// existing sigma-based scale and the default. The others capture at a fixed
/// fraction of the device's native pixels (`devicePixelRatio * fraction`), so
/// 1.00 is the native reference. Blur is always applied in atlas pixels as
/// `sigma * scale`, so its radius stays `sigma` logical pixels at every option.
enum SistrumAtlasResolution {
  baseline('baseline', 'Baseline (auto, current)', null),
  quarter('quarter', '0.25×', 0.25),
  third('third', '0.33×', 0.33),
  half('half', '0.50×', 0.5),
  full('full', '1.00× (reference)', 1.0);

  const SistrumAtlasResolution(this.wire, this.label, this.fraction);

  /// The value written to reports and configuration strings.
  final String wire;

  /// The label shown in the controls.
  final String label;

  /// Fraction of native device pixels, or null for [baseline].
  final double? fraction;
}

/// Instrumented atlas counters and state, as recorded by the code below.
typedef SistrumAtlasStats = ({
  bool requested,
  int activeSurfaces,
  int registeredSurfaces,
  String? fallbackReason,
  int captureCount,
  int reuseCount,
  int updateCount,
  int lateInvalidations,
  int layersWalked,
  int picturesDrawn,
  ui.Size? textureSize,
  double? samplingScale,
  SistrumAtlasResolution resolution,
  String? edgeStatus,
  int edgePaints,
});

/// Report lines for [stats]. Counters are counted in code; GPU work is
/// estimated and labelled so.
List<String> sistrumAtlasLines(SistrumAtlasStats? stats) {
  if (stats == null) return const ['hybrid_atlas_requested=false'];
  final size = stats.textureSize;
  return [
    'hybrid_atlas_requested=${stats.requested}',
    'hybrid_atlas_active=${stats.activeSurfaces > 0 ? '${stats.activeSurfaces}/${stats.registeredSurfaces == 0 ? stats.activeSurfaces : stats.registeredSurfaces}' : 'false'}',
    'hybrid_atlas_fallback_reason=${stats.fallbackReason ?? 'none'}',
    'hybrid_atlas_capture_count=${stats.captureCount} (instrumented: toImageSync calls)',
    'hybrid_atlas_reuse_count=${stats.reuseCount} (instrumented: paints that reused the capture)',
    'hybrid_atlas_update_count=${stats.updateCount} (instrumented: declared invalidations)',
    'hybrid_atlas_late_invalidations=${stats.lateInvalidations} (instrumented: undeclared changes caught after the frame)',
    'hybrid_atlas_texture_size=${size == null ? 'none' : '${size.width.round()}x${size.height.round()}'}',
    'hybrid_atlas_resolution=${stats.resolution.wire} (${stats.resolution.label})',
    'hybrid_atlas_refraction=${stats.edgeStatus ?? 'off'} edge_paints=${stats.edgePaints} (instrumented: rim rings drawn; the shader runs only when this is above 0)',
    'hybrid_atlas_sampling_scale=${stats.samplingScale?.toStringAsFixed(3) ?? 'none'} (atlas px per logical px)',
    'hybrid_atlas_layers_walked=${stats.layersWalked} pictures_drawn=${stats.picturesDrawn} (instrumented, last capture)',
    'hybrid_atlas_gpu_passes_per_capture=estimated 2 (atlas raster + its blur layer); not measured',
  ];
}

/// The atlas scale for [sigma]: about two atlas pixels of blur, never above
/// the device scale or 2, never below 1/4.
double sistrumAtlasScale({
  required double sigma,
  required double devicePixelRatio,
  SistrumAtlasResolution resolution = SistrumAtlasResolution.baseline,
}) {
  final fraction = resolution.fraction;
  if (fraction != null) return devicePixelRatio * fraction;
  if (sigma <= 0) return math.min(devicePixelRatio, 2);
  return (2 / sigma).clamp(0.25, math.min(devicePixelRatio, 2.0));
}

/// Rim width of the Edge-only refraction, logical px, before the half-size cap.
const double kSistrumAtlasEdgeBand = 16;

/// Asset key of the Edge-only atlas refraction shader (`pubspec.yaml`).
const String kSistrumAtlasEdgeShaderAsset = 'shaders/sistrum_atlas_edge.frag';

/// Uniform values for [kSistrumAtlasEdgeShaderAsset], in declaration order.
/// A `vec2` takes two float slots: size, radius, band, refraction, dispersion,
/// origin, atlas origin, scale, atlas size (13 values).
List<double> sistrumAtlasEdgeUniforms({
  required Rect surface,
  required double borderRadius,
  required bool chromatic,
  required Rect sourceInAtlas,
  required double scale,
  required ui.Size atlasSize,
}) {
  final band = math.min(
    kSistrumAtlasEdgeBand,
    math.min(surface.width, surface.height) / 2,
  );
  return [
    surface.width,
    surface.height,
    borderRadius,
    band,
    1.0,
    chromatic ? 1.0 : 0.0,
    surface.left,
    surface.top,
    sourceInAtlas.left,
    sourceInAtlas.top,
    scale,
    atlasSize.width,
    atlasSize.height,
  ];
}

class _SlotGeometry {
  _SlotGeometry(this.source, this.surface, this.target);

  /// Region of the backdrop recorded for the slot (surface plus blur reach).
  final Rect source;

  /// The surface's own rectangle in backdrop coordinates.
  final Rect surface;

  /// The slot in the atlas, in texture pixels.
  final Rect target;

  /// The surface's part of the slot, in texture pixels.
  Rect surfaceInAtlas(double scale) => Rect.fromLTWH(
    target.left + (surface.left - source.left) * scale,
    target.top + (surface.top - source.top) * scale,
    surface.width * scale,
    surface.height * scale,
  );
}

/// Owns the backdrop boundary key, the capture and the counters. One per stage.
class SistrumHybridAtlas extends ChangeNotifier {
  /// Key of the `RepaintBoundary` that holds the backdrop (never the glass).
  final GlobalKey backdropKey = GlobalKey(debugLabel: 'hybrid-atlas-backdrop');

  final Set<RenderSistrumAtlasSlot> _slots = {};
  final Map<RenderSistrumAtlasSlot, _SlotGeometry> _geometry = {};

  bool _requested = false;
  String? _configReason;
  double _sigma = 0;
  SistrumAtlasResolution _resolution = SistrumAtlasResolution.baseline;
  Listenable? _invalidations;

  ui.Image? _image;
  double? _scale;
  int? _signature;

  /// The backdrop part of [_signature] alone, for the post-frame check.
  int? _backdropSignature;
  String? _failure;
  bool _postFrameArmed = false;
  bool _disposed = false;

  int _captures = 0;
  int _reuses = 0;
  int _updates = 0;
  int _late = 0;
  int _layers = 0;
  int _pictures = 0;

  // Edge-only refraction (the shader that samples the atlas on the rim).
  bool _edgeWanted = false;
  bool _edgeChromatic = false;
  ui.FragmentProgram? _edgeProgram;
  bool _edgeLoading = false;
  String? _edgeStatus;
  int _edgePaints = 0;

  /// Whether surfaces should use the atlas now.
  bool get active => _requested && _configReason == null && _failure == null;

  /// The capture failure that sent the surfaces back to `BackdropFilter`.
  String? get failure => _failure;

  /// The current atlas texture, for tests and diagnostics only.
  @visibleForTesting
  ui.Image? get debugImage => _image;

  SistrumAtlasStats get stats => (
    requested: _requested,
    activeSurfaces: active ? _geometry.length : 0,
    registeredSurfaces: _slots.length,
    fallbackReason: _configReason ?? _failure,
    captureCount: _captures,
    reuseCount: _reuses,
    updateCount: _updates,
    lateInvalidations: _late,
    layersWalked: _layers,
    picturesDrawn: _pictures,
    textureSize: _image == null
        ? null
        : ui.Size(_image!.width.toDouble(), _image!.height.toDouble()),
    samplingScale: _image == null ? null : _scale,
    resolution: _resolution,
    edgeStatus: _edgeWanted ? (_edgeStatus ?? 'pending') : null,
    edgePaints: _edgePaints,
  );

  /// Called by the page when it builds the stage. [unsupportedReason] is the
  /// configuration's reason, so a requested but unsupported atlas is reported.
  void configure({
    required bool requested,
    required String? unsupportedReason,
    required double sigma,
    required Listenable invalidations,
    SistrumAtlasResolution resolution = SistrumAtlasResolution.baseline,
    bool edgeRefraction = false,
    bool chromatic = false,
  }) {
    final edge = requested && edgeRefraction && unsupportedReason == null;
    final changed =
        requested != _requested ||
        unsupportedReason != _configReason ||
        sigma != _sigma ||
        resolution != _resolution ||
        edge != _edgeWanted ||
        chromatic != _edgeChromatic;
    _resolution = resolution;
    _edgeWanted = edge;
    _edgeChromatic = chromatic;
    if (edge) {
      _requestEdgeProgram();
    } else {
      _edgeStatus = null;
    }
    _requested = requested;
    _configReason = requested ? unsupportedReason : null;
    _sigma = sigma;
    if (!identical(invalidations, _invalidations)) {
      _invalidations?.removeListener(_invalidate);
      _invalidations = invalidations;
      invalidations.addListener(_invalidate);
    }
    if (changed) {
      // A new request starts clean: a past failure is re-tried, counters stay.
      _failure = null;
      _signature = null;
      if (!requested) _dropImage();
      // The surfaces must repaint to recapture at the new settings.
      _invalidate();
    }
  }

  void _invalidate() {
    if (!active || _slots.isEmpty) return;
    _updates++;
    for (final slot in _slots) {
      slot.markNeedsPaint();
    }
  }

  void _register(RenderSistrumAtlasSlot slot) {
    _slots.add(slot);
    _signature = null;
    _armPostFrame();
  }

  void _unregister(RenderSistrumAtlasSlot slot) {
    _slots.remove(slot);
    _geometry.remove(slot);
    _signature = null;
    if (_slots.isEmpty) _dropImage();
  }

  void _dropImage() {
    _image?.dispose();
    _image = null;
    _geometry.clear();
  }

  /// Post-frame check for backdrop changes nobody declared. Re-armed each frame
  /// while atlas surfaces exist; it schedules no frame by itself.
  void _armPostFrame() {
    if (_postFrameArmed || _disposed) return;
    _postFrameArmed = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _postFrameArmed = false;
      if (_disposed || !active || _slots.isEmpty) return;
      final backdrop = _backdrop();
      final signature = backdrop == null ? null : _signatureOf(backdrop);
      if (_backdropSignature != null &&
          signature != null &&
          signature != _backdropSignature) {
        _late++;
        for (final slot in _slots) {
          slot.markNeedsPaint();
        }
      }
      _armPostFrame();
    });
  }

  RenderSistrumAtlasBackdrop? _backdrop() {
    final object = backdropKey.currentContext?.findRenderObject();
    if (object is! RenderSistrumAtlasBackdrop || !object.attached) return null;
    return object;
  }

  /// Loads the Edge refraction program once. Surfaces keep the plain atlas
  /// until it is ready, and the status says so.
  void _requestEdgeProgram() {
    if (_edgeProgram != null || _edgeLoading) return;
    if (!ui.ImageFilter.isShaderFilterSupported) {
      _edgeStatus = 'shader_filters_unsupported';
      return;
    }
    _edgeLoading = true;
    _edgeStatus = 'loading';
    ui.FragmentProgram.fromAsset(kSistrumAtlasEdgeShaderAsset).then(
      (program) {
        _edgeLoading = false;
        if (_disposed) return;
        _edgeProgram = program;
        _edgeStatus = 'active';
        _invalidate();
        notifyListeners();
      },
      onError: (Object _) {
        _edgeLoading = false;
        if (_disposed) return;
        _edgeStatus = 'failed';
        notifyListeners();
      },
    );
  }

  /// The Edge program when the rim should be drawn now, otherwise null.
  ui.FragmentProgram? get _edgeReady => _edgeWanted ? _edgeProgram : null;

  /// Draws the rim ring of one surface, sampling the atlas texture of this
  /// frame. The ring is the surface minus its inset rounded rectangle, so the
  /// centre keeps the plain atlas image drawn beneath it.
  void _drawEdge(
    ui.Canvas canvas,
    Rect rect,
    ({ui.Image image, Rect source}) hit,
    ui.FragmentProgram program,
    double borderRadius,
  ) {
    final scale = _scale ?? 1.0;
    final shader = program.fragmentShader();
    final values = sistrumAtlasEdgeUniforms(
      surface: rect,
      borderRadius: borderRadius,
      chromatic: _edgeChromatic,
      sourceInAtlas: hit.source,
      scale: scale,
      atlasSize: ui.Size(hit.image.width.toDouble(), hit.image.height.toDouble()),
    );
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    shader.setImageSampler(0, hit.image, filterQuality: FilterQuality.low);
    final band = math.min(kSistrumAtlasEdgeBand, math.min(rect.width, rect.height) / 2);
    final radius = math.min(borderRadius, math.min(rect.width, rect.height) / 2);
    final ring = Path.combine(
      PathOperation.difference,
      Path()..addRRect(RRect.fromRectAndRadius(rect, Radius.circular(radius))),
      Path()
        ..addRRect(
          RRect.fromRectAndRadius(
            rect.deflate(band),
            Radius.circular(math.max(0.0, radius - band)),
          ),
        ),
    );
    canvas.drawPath(ring, Paint()..shader = shader);
    _edgePaints++;
  }

  void _fail(String reason) {
    if (_failure == reason) return;
    _failure = reason;
    _dropImage();
    // Surfaces rebuild with BackdropFilter on the next frame; never during paint.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed) notifyListeners();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  /// The atlas image and the surface's part of it, capturing first when the
  /// backdrop or the geometry changed. Null when the atlas cannot serve.
  ({ui.Image image, Rect source})? _slotImage(RenderSistrumAtlasSlot slot) {
    if (!active) return null;
    final backdrop = _backdrop();
    if (backdrop == null || backdrop.atlasLayer == null) {
      _fail('backdrop_not_painted');
      return null;
    }
    final dpr = slot.devicePixelRatio;
    final scale = sistrumAtlasScale(
      sigma: _sigma,
      devicePixelRatio: dpr,
      resolution: _resolution,
    );
    final reach = _sigma * 3 + 1;
    final bounds = Offset.zero & backdrop.size;
    final surfaces = <RenderSistrumAtlasSlot, (Rect, Rect)>{};
    for (final s in _slots) {
      if (!s.attached || !s.hasSize) continue;
      final transform = s.getTransformTo(backdrop);
      // Only translation and positive scale map a slot to a rectangle.
      if (transform.storage[1] != 0 ||
          transform.storage[4] != 0 ||
          transform.storage[0] <= 0 ||
          transform.storage[5] <= 0) {
        _fail('surface_transform_not_axis_aligned');
        return null;
      }
      final rect = MatrixUtils.transformRect(transform, Offset.zero & s.size);
      final source = rect.inflate(reach).intersect(bounds);
      if (source.isEmpty) continue;
      surfaces[s] = (rect, source);
    }
    final backdropSignature = _signatureOf(backdrop);
    final signature = Object.hash(
      backdropSignature,
      scale,
      _sigma,
      Object.hashAllUnordered([
        for (final e in surfaces.entries)
          Object.hash(e.key, e.value.$1, e.value.$2),
      ]),
    );
    if (_image != null && signature == _signature && _geometry[slot] != null) {
      _reuses++;
      return (image: _image!, source: _geometry[slot]!.surfaceInAtlas(scale));
    }
    final failure = _capture(backdrop, surfaces, scale);
    if (failure != null) {
      _fail(failure);
      return null;
    }
    _signature = signature;
    _backdropSignature = backdropSignature;
    _scale = scale;
    final geometry = _geometry[slot];
    if (geometry == null || _image == null) return null;
    return (image: _image!, source: geometry.surfaceInAtlas(scale));
  }

  /// Records the slots into one picture and rasterizes it. Returns the reason
  /// when the backdrop cannot be redrawn faithfully.
  String? _capture(
    RenderSistrumAtlasBackdrop backdrop,
    Map<RenderSistrumAtlasSlot, (Rect, Rect)> surfaces,
    double scale,
  ) {
    final root = backdrop.atlasLayer;
    if (root is! ContainerLayer) return 'backdrop_layer_missing';
    // Shelf packing: one slot per row, 2 px apart.
    final targets = <RenderSistrumAtlasSlot, _SlotGeometry>{};
    var y = 0.0;
    var width = 0.0;
    for (final e in surfaces.entries) {
      final source = e.value.$2;
      final w = (source.width * scale).ceilToDouble();
      final h = (source.height * scale).ceilToDouble();
      targets[e.key] = _SlotGeometry(
        source,
        e.value.$1,
        Rect.fromLTWH(0, y, w, h),
      );
      y += h + 2;
      width = math.max(width, w);
    }
    final height = math.max(0.0, y - 2);
    if (targets.isEmpty || width <= 0 || height <= 0) return 'no_slots';
    if (width > kSistrumAtlasMaxSide || height > kSistrumAtlasMaxSide) {
      return 'atlas_too_large_${width.round()}x${height.round()}';
    }
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    final walk = _LayerWalk(canvas);
    final blurSigma = _sigma * scale;
    for (final g in targets.values) {
      canvas.save();
      canvas.clipRect(g.target);
      if (blurSigma > 0) {
        canvas.saveLayer(
          g.target,
          Paint()
            ..imageFilter = ui.ImageFilter.blur(
              sigmaX: blurSigma,
              sigmaY: blurSigma,
              tileMode: TileMode.clamp,
            ),
        );
      }
      canvas.translate(g.target.left, g.target.top);
      canvas.scale(scale);
      canvas.translate(-g.source.left, -g.source.top);
      final unsupported = walk.children(root);
      if (blurSigma > 0) canvas.restore();
      canvas.restore();
      if (unsupported != null) {
        recorder.endRecording().dispose();
        return unsupported;
      }
    }
    final picture = recorder.endRecording();
    final image = picture.toImageSync(width.round(), height.round());
    picture.dispose();
    _image?.dispose();
    _image = image;
    _geometry
      ..clear()
      ..addAll(targets);
    _captures++;
    _layers = walk.layers ~/ targets.length;
    _pictures = walk.pictures ~/ targets.length;
    return null;
  }

  /// A hash of what the backdrop layer tree would draw: picture identities,
  /// offsets, transforms, clips and opacities.
  static int _signatureOf(RenderSistrumAtlasBackdrop backdrop) {
    final root = backdrop.atlasLayer;
    if (root == null) return 0;
    final parts = <Object?>[];
    void visit(Layer layer) {
      parts.add(layer.runtimeType);
      switch (layer) {
        case PictureLayer():
          parts.add(identityHashCode(layer.picture));
        case TransformLayer():
          parts
            ..add(layer.offset)
            ..add(layer.transform?.storage.join(','));
        case OpacityLayer():
          parts
            ..add(layer.offset)
            ..add(layer.alpha);
        case OffsetLayer():
          parts.add(layer.offset);
        case ClipRectLayer():
          parts.add(layer.clipRect);
        case ClipRRectLayer():
          parts.add(layer.clipRRect);
        default:
          break;
      }
      if (layer is ContainerLayer) {
        for (var c = layer.firstChild; c != null; c = c.nextSibling) {
          visit(c);
        }
      }
    }

    visit(root);
    return Object.hashAll(parts);
  }

  @override
  void dispose() {
    _disposed = true;
    _invalidations?.removeListener(_invalidate);
    _dropImage();
    super.dispose();
  }
}

/// Redraws a layer subtree into a canvas, the way the compositor would.
class _LayerWalk {
  _LayerWalk(this.canvas);

  final Canvas canvas;
  int layers = 0;
  int pictures = 0;

  /// Draws the children of [container]; the reason when one is unsupported.
  String? children(ContainerLayer container) {
    for (var c = container.firstChild; c != null; c = c.nextSibling) {
      final reason = layer(c);
      if (reason != null) return reason;
    }
    return null;
  }

  String? layer(Layer layer) {
    layers++;
    switch (layer) {
      case PictureLayer():
        final picture = layer.picture;
        if (picture != null) {
          canvas.drawPicture(picture);
          pictures++;
        }
        return null;
      // Layers whose effect cannot be redrawn into a picture.
      case BackdropFilterLayer():
      case ShaderMaskLayer():
      case FollowerLayer():
      case PlatformViewLayer():
      case TextureLayer():
      case PerformanceOverlayLayer():
        return 'unsupported_layer:${layer.runtimeType}';
      case TransformLayer():
        canvas.save();
        canvas.translate(layer.offset.dx, layer.offset.dy);
        final t = layer.transform;
        if (t != null) canvas.transform(t.storage);
        final r = children(layer);
        canvas.restore();
        return r;
      case OpacityLayer():
        canvas.save();
        canvas.translate(layer.offset.dx, layer.offset.dy);
        canvas.saveLayer(
          null,
          Paint()..color = Color.fromARGB(layer.alpha ?? 255, 0, 0, 0),
        );
        final r = children(layer);
        canvas.restore();
        canvas.restore();
        return r;
      case ImageFilterLayer():
        canvas.save();
        canvas.translate(layer.offset.dx, layer.offset.dy);
        final filter = layer.imageFilter;
        canvas.saveLayer(null, Paint()..imageFilter = filter);
        final r = children(layer);
        canvas.restore();
        canvas.restore();
        return r;
      case OffsetLayer():
        canvas.save();
        canvas.translate(layer.offset.dx, layer.offset.dy);
        final r = children(layer);
        canvas.restore();
        return r;
      case ColorFilterLayer():
        canvas.saveLayer(null, Paint()..colorFilter = layer.colorFilter);
        final r = children(layer);
        canvas.restore();
        return r;
      case ClipRectLayer():
        final rect = layer.clipRect;
        canvas.save();
        if (rect != null) {
          canvas.clipRect(
            rect,
            doAntiAlias: layer.clipBehavior != Clip.hardEdge,
          );
        }
        final r = children(layer);
        canvas.restore();
        return r;
      case ClipRRectLayer():
        final rrect = layer.clipRRect;
        canvas.save();
        if (rrect != null) {
          canvas.clipRRect(
            rrect,
            doAntiAlias: layer.clipBehavior != Clip.hardEdge,
          );
        }
        final r = children(layer);
        canvas.restore();
        return r;
      case ClipPathLayer():
        final path = layer.clipPath;
        canvas.save();
        if (path != null) {
          canvas.clipPath(
            path,
            doAntiAlias: layer.clipBehavior != Clip.hardEdge,
          );
        }
        final r = children(layer);
        canvas.restore();
        return r;
      case LeaderLayer():
        canvas.save();
        canvas.translate(layer.offset.dx, layer.offset.dy);
        final r = children(layer);
        canvas.restore();
        return r;
      case ContainerLayer():
        return children(layer);
      default:
        return 'unsupported_layer:${layer.runtimeType}';
    }
  }
}

/// The repaint boundary that holds the backdrop the atlas records. Use it
/// around the content under the glass, never around the glass itself.
class SistrumAtlasBackdrop extends SingleChildRenderObjectWidget {
  const SistrumAtlasBackdrop({required super.key, super.child});

  @override
  RenderSistrumAtlasBackdrop createRenderObject(BuildContext context) =>
      RenderSistrumAtlasBackdrop();
}

/// A [RenderRepaintBoundary] that exposes its own layer to the atlas. The
/// layer is the composited tree painted in the current frame.
class RenderSistrumAtlasBackdrop extends RenderRepaintBoundary {
  /// This boundary's layer, or null before it has painted.
  ContainerLayer? get atlasLayer => layer;
}

/// Gives the stage's surfaces the atlas.
class SistrumHybridAtlasScope extends InheritedWidget {
  const SistrumHybridAtlasScope({
    required this.atlas,
    required super.child,
    super.key,
  });

  final SistrumHybridAtlas atlas;

  static SistrumHybridAtlas? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<SistrumHybridAtlasScope>()
      ?.atlas;

  @override
  bool updateShouldNotify(SistrumHybridAtlasScope oldWidget) =>
      !identical(oldWidget.atlas, atlas);
}

/// Draws this surface's slot of the atlas under its child.
class SistrumAtlasSlot extends SingleChildRenderObjectWidget {
  const SistrumAtlasSlot({
    required this.atlas,
    this.borderRadius = 0,
    super.child,
    super.key,
  });

  final SistrumHybridAtlas atlas;

  /// Logical corner radius of the surface, for the Edge refraction ring.
  final double borderRadius;

  @override
  RenderSistrumAtlasSlot createRenderObject(BuildContext context) =>
      RenderSistrumAtlasSlot(atlas, View.of(context).devicePixelRatio)
        ..borderRadius = borderRadius;

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSistrumAtlasSlot renderObject,
  ) {
    renderObject
      ..atlas = atlas
      ..devicePixelRatio = View.of(context).devicePixelRatio
      ..borderRadius = borderRadius;
  }
}

/// The render object of [SistrumAtlasSlot]. It is not a repaint boundary, so
/// it paints with its ancestors, after the backdrop boundary in the same pass.
class RenderSistrumAtlasSlot extends RenderProxyBox {
  RenderSistrumAtlasSlot(this._atlas, this._devicePixelRatio);

  /// Logical corner radius of the surface, for the Edge refraction ring.
  double borderRadius = 0;

  SistrumHybridAtlas _atlas;
  set atlas(SistrumHybridAtlas value) {
    if (identical(value, _atlas)) return;
    if (attached) _atlas._unregister(this);
    _atlas = value;
    if (attached) _atlas._register(this);
    markNeedsPaint();
  }

  double _devicePixelRatio;
  double get devicePixelRatio => _devicePixelRatio;
  set devicePixelRatio(double value) {
    if (value == _devicePixelRatio) return;
    _devicePixelRatio = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _atlas._register(this);
  }

  @override
  void detach() {
    _atlas._unregister(this);
    super.detach();
  }

  @override
  @override
  void paint(PaintingContext context, Offset offset) {
    final hit = _atlas._slotImage(this);
    if (hit != null) {
      context.canvas.drawImageRect(
        hit.image,
        hit.source,
        offset & size,
        Paint()..filterQuality = FilterQuality.low,
      );
      final edge = _atlas._edgeReady;
      if (edge != null) {
        _atlas._drawEdge(context.canvas, offset & size, hit, edge, borderRadius);
      }
    }
    super.paint(context, offset);
  }
}
