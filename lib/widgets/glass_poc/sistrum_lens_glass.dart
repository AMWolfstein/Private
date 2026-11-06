import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_telemetry.dart';

/// Asset key of the first-party lens shader, as declared in `pubspec.yaml`.
const String kSistrumLensShaderAsset = 'shaders/sistrum_lens.frag';

/// Strength of the lens refraction, passed to the shader (0..1).
const double kSistrumLensRefraction = 1.0;

/// Width of the refracting rim in logical pixels, before the device scale.
const double kSistrumLensBandLogical = 16;

/// Uniform values for [kSistrumLensShaderAsset], in declaration order.
///
/// The shader samples physical pixels, so the logical [size], [borderRadius]
/// and rim width are scaled by [devicePixelRatio]. A `vec2` takes two float
/// slots, so the list is: width, height, radius, band, refraction, dispersion.
/// The band is capped at half the shorter side so a small surface still has
/// a valid rim.
List<double> sistrumLensUniforms({
  required Size size,
  required double borderRadius,
  required double devicePixelRatio,
  required double refraction,
  required bool chromatic,
}) {
  final width = size.width * devicePixelRatio;
  final height = size.height * devicePixelRatio;
  final band = math.min(
    kSistrumLensBandLogical * devicePixelRatio,
    math.min(width, height) / 2,
  );
  return [
    width,
    height,
    borderRadius * devicePixelRatio,
    band,
    refraction,
    chromatic ? 1.0 : 0.0,
  ];
}

/// Loads the first-party lens program once and keeps it for the app's life.
///
/// A failed load resolves to null, which makes [SistrumLensGlass] draw its
/// blur-only fallback. Null is also returned without a load when the engine
/// does not support shader filters (Skia, or a platform without Impeller).
/// [state] records which of these happened, for the telemetry.
abstract final class SistrumLensProgram {
  static Future<FragmentProgram?>? _future;
  static SistrumLensProgramState _state = (
    status: SistrumLensProgramStatus.notRequested,
    error: null,
    loadMs: null,
  );

  /// The last recorded load state.
  static SistrumLensProgramState get state => _state;

  static Future<FragmentProgram?> load() {
    if (!ImageFilter.isShaderFilterSupported) {
      _state = (
        status: SistrumLensProgramStatus.unsupported,
        error: null,
        loadMs: null,
      );
      return Future.value(null);
    }
    final existing = _future;
    if (existing != null) return existing;
    final watch = Stopwatch()..start();
    _state = (
      status: SistrumLensProgramStatus.loading,
      error: null,
      loadMs: null,
    );
    return _future = FragmentProgram.fromAsset(kSistrumLensShaderAsset)
        .then<FragmentProgram?>((program) {
          _state = (
            status: SistrumLensProgramStatus.loaded,
            error: null,
            loadMs: watch.elapsedMilliseconds,
          );
          return program;
        })
        .catchError((Object error) {
          _state = (
            status: SistrumLensProgramStatus.failed,
            error: error.toString().split('\n').first,
            loadMs: watch.elapsedMilliseconds,
          );
          return null;
        });
  }
}

/// Sistrum-owned Full-tier glass: a blur, then the first-party lens shader.
///
/// The filter is `ImageFilter.compose(outer: lens, inner: blur)`, which is
/// `lens(blur(backdrop))`: the backdrop is blurred first and the lens then
/// refracts the blurred image.
///
/// Without [refraction], or until the program is loaded, or where the engine
/// has no shader filters, it draws the plain blur (Frosted). No third-party
/// renderer is used on any path. Each build reports what it handed to the
/// engine, and why, through [onDecision].
class SistrumLensGlass extends StatefulWidget {
  const SistrumLensGlass({
    required this.blurSigma,
    required this.refraction,
    required this.chromatic,
    required this.borderRadius,
    required this.child,
    this.backdropKey,
    this.onDecision,
    super.key,
  });

  final double blurSigma;
  final bool refraction;

  /// Colour split at the rim, when [refraction] is on.
  final bool chromatic;

  /// Logical corner radius; the shader receives it in physical pixels.
  final double borderRadius;

  /// Shared backdrop read (`BackdropFilter.backdropGroupKey`), or null for an
  /// independent read.
  final BackdropKey? backdropKey;

  /// Receives the decision every time the filter is built.
  final ValueChanged<SistrumHybridDecision>? onDecision;

  /// Drawn above the glass; the backdrop filter does not touch it.
  final Widget child;

  @override
  State<SistrumLensGlass> createState() => _SistrumLensGlassState();
}

class _SistrumLensGlassState extends State<SistrumLensGlass> {
  FragmentProgram? _program;

  @override
  void initState() {
    super.initState();
    if (widget.refraction) _loadProgram();
  }

  @override
  void didUpdateWidget(SistrumLensGlass oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.refraction && _program == null) _loadProgram();
  }

  void _loadProgram() {
    SistrumLensProgram.load().then((program) {
      if (!mounted || program == null) return;
      setState(() => _program = program);
    });
  }

  /// Why the blur is drawn instead of the lens, or none for the lens.
  SistrumHybridFallback _fallbackFor(Size size) {
    if (!widget.refraction) return SistrumHybridFallback.refractionOff;
    if (!ImageFilter.isShaderFilterSupported) {
      return SistrumHybridFallback.shaderFiltersUnsupported;
    }
    if (_program == null) {
      return SistrumLensProgram.state.status == SistrumLensProgramStatus.failed
          ? SistrumHybridFallback.programFailed
          : SistrumHybridFallback.programLoading;
    }
    if (!size.isFinite || size.isEmpty) {
      return SistrumHybridFallback.invalidSize;
    }
    return SistrumHybridFallback.none;
  }

  /// The filter for this build, or null when nothing reads the backdrop
  /// (blur 0 without the lens: a true bypass, no `BackdropFilter`).
  ImageFilter? _filterFor(Size size, double devicePixelRatio) {
    final fallback = _fallbackFor(size);
    final program = _program;
    final lens = fallback == SistrumHybridFallback.none && program != null;
    final blurs = widget.blurSigma > 0;
    final bypass = !lens && !blurs;
    widget.onDecision?.call(
      SistrumHybridDecision(
        requestedTier: SistrumHybridTier.full,
        path: lens
            ? SistrumHybridEffectivePath.lens
            : bypass
            ? SistrumHybridEffectivePath.tint
            : SistrumHybridEffectivePath.blur,
        fallback: bypass && fallback == SistrumHybridFallback.refractionOff
            ? SistrumHybridFallback.zeroBlurBypass
            : fallback,
        backdropKey: bypass ? null : widget.backdropKey,
      ),
    );
    final blur = blurs
        ? ImageFilter.blur(sigmaX: widget.blurSigma, sigmaY: widget.blurSigma)
        : null;
    if (!lens) return blur;
    final values = sistrumLensUniforms(
      size: size,
      borderRadius: widget.borderRadius,
      devicePixelRatio: devicePixelRatio,
      refraction: kSistrumLensRefraction,
      chromatic: widget.chromatic,
    );
    final shader = program.fragmentShader();
    for (var i = 0; i < values.length; i++) {
      shader.setFloat(i, values[i]);
    }
    final lensFilter = ImageFilter.shader(shader);
    // Blur 0: the lens alone, without a composed (no-op) blur pass.
    return blur == null
        ? lensFilter
        : ImageFilter.compose(outer: lensFilter, inner: blur);
  }

  @override
  Widget build(BuildContext context) {
    final devicePixelRatio = View.of(context).devicePixelRatio;
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final filter = _filterFor(constraints.biggest, devicePixelRatio);
          if (filter == null) return widget.child;
          return BackdropFilter(
            filter: filter,
            backdropGroupKey: widget.backdropKey,
            child: widget.child,
          );
        },
      ),
    );
  }
}
