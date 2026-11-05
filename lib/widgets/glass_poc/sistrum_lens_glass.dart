import 'dart:ui';

import 'package:flutter/widgets.dart';

/// Asset key of the first-party lens shader, as declared in `pubspec.yaml`.
const String kSistrumLensShaderAsset = 'shaders/sistrum_lens.frag';

/// Strength of the lens refraction, passed to the shader (0..1).
const double kSistrumLensRefraction = 1.0;

/// Loads the first-party lens program once and keeps it for the app's life.
///
/// A failed load resolves to null, which makes [SistrumLensGlass] draw its
/// blur-only fallback. Null is also returned without a load when the engine
/// does not support shader filters (Skia, or a platform without Impeller).
abstract final class SistrumLensProgram {
  static Future<FragmentProgram?>? _future;

  static Future<FragmentProgram?> load() {
    if (!ImageFilter.isShaderFilterSupported) return Future.value(null);
    return _future ??= FragmentProgram.fromAsset(kSistrumLensShaderAsset)
        .then<FragmentProgram?>((program) => program)
        .catchError((Object _) => null);
  }
}

/// Sistrum-owned Full-tier glass: a blur, then the first-party lens shader.
///
/// The filter is `ImageFilter.compose(outer: lens, inner: blur)`: the backdrop
/// is blurred first and the lens then refracts the blurred image, so the
/// refraction is real and not a fake overlay.
///
/// Without [refraction], or until the program is loaded, or where the engine
/// has no shader filters, it draws the plain blur (Frosted). No third-party
/// renderer is used on any path.
class SistrumLensGlass extends StatefulWidget {
  const SistrumLensGlass({
    required this.blurSigma,
    required this.refraction,
    required this.chromatic,
    required this.borderRadius,
    required this.child,
    super.key,
  });

  final double blurSigma;
  final bool refraction;

  /// Colour split at the rim, when [refraction] is on.
  final bool chromatic;
  final double borderRadius;

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

  ImageFilter _filterFor(Size size, ImageFilter blur) {
    final program = _program;
    if (!widget.refraction ||
        program == null ||
        !size.isFinite ||
        size.isEmpty) {
      return blur;
    }
    final shader = program.fragmentShader()
      // uSize is a vec2: two floats, then the scalar uniforms in order.
      ..setFloat(0, size.width)
      ..setFloat(1, size.height)
      ..setFloat(2, kSistrumLensRefraction)
      ..setFloat(3, widget.chromatic ? 1.0 : 0.0);
    return ImageFilter.compose(
      outer: ImageFilter.shader(shader),
      inner: blur,
    );
  }

  @override
  Widget build(BuildContext context) {
    final blur = ImageFilter.blur(
      sigmaX: widget.blurSigma,
      sigmaY: widget.blurSigma,
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) => BackdropFilter(
          filter: _filterFor(constraints.biggest, blur),
          child: widget.child,
        ),
      ),
    );
  }
}
