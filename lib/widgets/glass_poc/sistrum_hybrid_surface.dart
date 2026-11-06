import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_atlas.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_config.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_hybrid_telemetry.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_lens_glass.dart';

/// Sistrum Hybrid surface for one tier. The geometry (box and corner) is set
/// by the caller; this widget supplies only the material.
///
/// Foreground content is drawn above the material, so it stays sharp in every
/// tier: a `BackdropFilter` blurs only what is painted beneath it.
///
/// Every tier has the same structure around the child (a rounded clip, then
/// the material), so the tiers differ only in what the matrix compares.
/// The decision is reported to the nearest [SistrumHybridTelemetryScope].
class SistrumHybridSurface extends StatefulWidget {
  const SistrumHybridSurface({
    required this.config,
    required this.dark,
    required this.borderRadius,
    required this.child,
    this.backdropKey,
    this.atlasEligible = true,
    super.key,
  });

  final SistrumHybridConfig config;
  final bool dark;
  final double borderRadius;
  final Widget child;

  /// Shared backdrop read for the tiers that read the backdrop, or null for an
  /// independent read. The page assigns it only when sharing is requested and
  /// safe for this surface.
  final BackdropKey? backdropKey;

  /// Whether this surface may sample the shared atlas. False when its blur
  /// reaches glass painted before it, which a single-level atlas lacks.
  final bool atlasEligible;

  @override
  State<SistrumHybridSurface> createState() => _SistrumHybridSurfaceState();
}

class _SistrumHybridSurfaceState extends State<SistrumHybridSurface> {
  SistrumHybridTelemetry? _telemetry;
  SistrumHybridAtlas? _atlas;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final next = SistrumHybridTelemetryScope.maybeOf(context);
    if (!identical(next, _telemetry)) {
      _telemetry?.remove(this);
      _telemetry = next;
    }
    final atlas = SistrumHybridAtlasScope.maybeOf(context);
    if (!identical(atlas, _atlas)) {
      _atlas?.removeListener(_onAtlas);
      _atlas = atlas;
      atlas?.addListener(_onAtlas);
    }
  }

  /// The atlas failed or recovered: rebuild with the matching path.
  void _onAtlas() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _telemetry?.remove(this);
    _atlas?.removeListener(_onAtlas);
    super.dispose();
  }

  /// The existing Frosted filter, used where the atlas cannot serve.
  Widget _blurFilter() => ClipRRect(
    borderRadius: _radius,
    child: BackdropFilter(
      filter: ImageFilter.blur(
        sigmaX: _config.blurSigma,
        sigmaY: _config.blurSigma,
      ),
      child: _material(widget.child),
    ),
  );

  /// The atlas branch, or null when the atlas is not requested and supported.
  Widget? _atlasSurface() {
    final atlas = _atlas;
    if (!_config.usesAtlas || atlas == null) return null;
    final reason = !widget.atlasEligible
        ? SistrumHybridFallback.atlasExcludedOverlap
        : !atlas.active
        ? SistrumHybridFallback.atlasCaptureFailed
        : null;
    if (reason != null) {
      _report(
        SistrumHybridDecision(
          requestedTier: _config.tier,
          path: SistrumHybridEffectivePath.blur,
          fallback: reason,
        ),
      );
      return _blurFilter();
    }
    _report(
      SistrumHybridDecision(
        requestedTier: _config.tier,
        path: SistrumHybridEffectivePath.atlas,
      ),
    );
    // Same clip and material as Frosted; only the backdrop source differs.
    return ClipRRect(
      borderRadius: _radius,
      child: SistrumAtlasSlot(
        atlas: atlas,
        borderRadius: widget.borderRadius,
        child: _material(widget.child),
      ),
    );
  }

  void _report(SistrumHybridDecision decision) =>
      _telemetry?.report(this, decision);

  SistrumHybridConfig get _config => widget.config;
  bool get _dark => widget.dark;

  BorderRadius get _radius => BorderRadius.circular(widget.borderRadius);

  /// Tint colour per theme: near-black in dark, near-white in light, at the
  /// configured opacity.
  Color get _tint => (_dark ? const Color(0xFF121212) : const Color(0xFFFAFAFA))
      .withValues(alpha: _config.tintOpacity);

  /// Opaque surface colour of variant A: no transparency at all.
  Color get _opaque =>
      _dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);

  /// Hairline edge, a little brighter in dark theme.
  Color get _edge => _dark
      ? Colors.white.withValues(alpha: 0.10)
      : Colors.black.withValues(alpha: 0.08);

  /// Directional light from the top-left edge. It is only a gradient, not a
  /// refraction, and it sits above the tint.
  Gradient get _highlight => LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.center,
    colors: [
      Colors.white.withValues(alpha: _dark ? 0.14 : 0.45),
      Colors.white.withValues(alpha: 0),
    ],
  );

  /// Tint, then highlight and hairline, then the child. The tint and the
  /// gradient are separate fills: a `BoxDecoration` with a gradient ignores
  /// its `color`, so a single decoration would never paint the tint.
  Widget _material(Widget child) => DecoratedBox(
    decoration: BoxDecoration(color: _tint, borderRadius: _radius),
    child: DecoratedBox(
      decoration: BoxDecoration(
        gradient: _highlight,
        borderRadius: _radius,
        border: Border.all(color: _edge, width: 0.5),
      ),
      child: child,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final atlasSurface = _atlasSurface();
    if (atlasSurface != null) return atlasSurface;
    final tier = _config.tier;
    switch (tier) {
      case SistrumHybridTier.opaque:
        // Variant A: no glass at all, the same shape and hairline.
        _report(
          const SistrumHybridDecision(
            requestedTier: SistrumHybridTier.opaque,
            path: SistrumHybridEffectivePath.opaque,
          ),
        );
        return ClipRRect(
          borderRadius: _radius,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _opaque,
              borderRadius: _radius,
              border: Border.all(color: _edge, width: 0.5),
            ),
            child: widget.child,
          ),
        );
      case SistrumHybridTier.lightweight:
        // No backdrop read at all: only the material is drawn.
        _report(
          const SistrumHybridDecision(
            requestedTier: SistrumHybridTier.lightweight,
            path: SistrumHybridEffectivePath.tint,
          ),
        );
        return ClipRRect(borderRadius: _radius, child: _material(widget.child));
      case SistrumHybridTier.frosted when _config.blurSigma <= 0:
        // True zero-blur bypass: no BackdropFilter, so no backdrop read and
        // no layer. Engine-side a 0-sigma blur is dropped too, but this keeps
        // the tree and the telemetry honest about it.
        _report(
          const SistrumHybridDecision(
            requestedTier: SistrumHybridTier.frosted,
            path: SistrumHybridEffectivePath.tint,
            fallback: SistrumHybridFallback.zeroBlurBypass,
          ),
        );
        return ClipRRect(borderRadius: _radius, child: _material(widget.child));
      case SistrumHybridTier.frosted:
        _report(
          SistrumHybridDecision(
            requestedTier: SistrumHybridTier.frosted,
            path: SistrumHybridEffectivePath.blur,
            backdropKey: widget.backdropKey,
          ),
        );
        return ClipRRect(
          borderRadius: _radius,
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: _config.blurSigma,
              sigmaY: _config.blurSigma,
            ),
            backdropGroupKey: widget.backdropKey,
            child: _material(widget.child),
          ),
        );
      case SistrumHybridTier.full:
        // First-party lens: blur, then the Sistrum shader (no package). The
        // lens reports its own decision, because only it knows whether the
        // program is loaded.
        return SistrumLensGlass(
          blurSigma: _config.blurSigma,
          refraction: _config.refraction,
          chromatic: _config.chromaticAberration,
          borderRadius: widget.borderRadius,
          backdropKey: widget.backdropKey,
          onDecision: _report,
          child: _material(widget.child),
        );
    }
  }
}
