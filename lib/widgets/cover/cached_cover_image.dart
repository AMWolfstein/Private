import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

class CachedCoverImage extends StatelessWidget {
  static const int _defaultMinCacheExtent = 64;
  static const int _defaultMaxCacheExtent = 512;

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;
  final Alignment alignment;
  final int? memCacheWidth;
  final int? memCacheHeight;
  final Widget Function(BuildContext, String, Object)? errorWidget;
  final Widget Function(BuildContext, String)? placeholder;
  final BorderRadius? borderRadius;
  final Duration fadeInDuration;

  const CachedCoverImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.alignment = Alignment.center,
    this.memCacheWidth,
    this.memCacheHeight,
    this.errorWidget,
    this.placeholder,
    this.borderRadius,
    this.fadeInDuration = Duration.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (width != null ||
        height != null ||
        memCacheWidth != null ||
        memCacheHeight != null) {
      return _buildImage(context, const BoxConstraints());
    }
    // Grid cells size their children through constraints rather than explicit
    // width/height. Use those bounds for decoding as well as explicit sizes.
    return LayoutBuilder(
      builder: (context, constraints) => _buildImage(context, constraints),
    );
  }

  Widget _buildImage(BuildContext context, BoxConstraints constraints) {
    var autoMemCacheWidth =
        memCacheWidth ??
        (memCacheHeight == null
            ? _cacheExtentForLogicalSize(context, width)
            : null);
    // ResizeImage stretches the decoded bitmap when both axes are supplied.
    // Keep one decode axis so BoxFit can crop the original proportions.
    var autoMemCacheHeight = autoMemCacheWidth == null
        ? memCacheHeight ?? _cacheExtentForLogicalSize(context, height)
        : null;
    if (autoMemCacheWidth == null && autoMemCacheHeight == null) {
      // Infer one axis to preserve the source aspect ratio and respect any
      // explicit decode override used by large artwork/header consumers.
      autoMemCacheWidth = _cacheExtentForLogicalSize(
        context,
        constraints.maxWidth,
      );
      if (autoMemCacheWidth == null) {
        autoMemCacheHeight = _cacheExtentForLogicalSize(
          context,
          constraints.maxHeight,
        );
      }
    }
    final local = Uri.tryParse(imageUrl);
    if (local == null || (local.hasScheme && local.scheme != 'file')) {
      return errorWidget?.call(
            context,
            imageUrl,
            StateError('Local artwork required'),
          ) ??
          placeholder?.call(context, imageUrl) ??
          const SizedBox.shrink();
    }
    final image = Image.file(
      File(local.scheme == 'file' ? local.toFilePath() : imageUrl),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      cacheWidth: autoMemCacheWidth,
      cacheHeight: autoMemCacheHeight,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      errorBuilder: (context, error, _) =>
          errorWidget?.call(context, imageUrl, error) ??
          placeholder?.call(context, imageUrl) ??
          const SizedBox.shrink(),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }

    return image;
  }

  static int? _cacheExtentForLogicalSize(BuildContext context, double? size) {
    if (size == null || !size.isFinite || size <= 0) return null;
    final dpr = MediaQuery.devicePixelRatioOf(
      context,
    ).clamp(1.0, 3.0).toDouble();
    return (size * dpr)
        .round()
        .clamp(_defaultMinCacheExtent, _defaultMaxCacheExtent)
        .toInt();
  }
}

/// Renders local artwork, with a shared placeholder for missing or remote sources.
class LocalCoverImage extends StatelessWidget {
  final String url;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final int? localCacheWidth;
  final Duration? fadeInDuration;
  final Widget Function(BuildContext) placeholder;

  const LocalCoverImage({
    super.key,
    required this.url,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.localCacheWidth,
    this.fadeInDuration,
    required this.placeholder,
  });

  bool get _isLocal =>
      !url.startsWith('http://') && !url.startsWith('https://');

  @override
  Widget build(BuildContext context) {
    if (_isLocal) {
      if (localCacheWidth != null) {
        return _buildLocalImage(context, const BoxConstraints());
      }
      return LayoutBuilder(builder: _buildLocalImage);
    }

    return placeholder(context);
  }

  Widget _buildLocalImage(BuildContext context, BoxConstraints constraints) {
    final file = File(
      url.startsWith('file://') ? Uri.parse(url).toFilePath() : url,
    );
    final ImageProvider provider;
    if (localCacheWidth != null) {
      provider = ResizeImage(FileImage(file), width: localCacheWidth);
    } else {
      final decodeWidth = _localDecodeExtent(
        context,
        constraints.constrainWidth(width ?? double.infinity),
      );
      final decodeHeight = _localDecodeExtent(
        context,
        constraints.constrainHeight(height ?? double.infinity),
      );
      provider = decodeWidth == null && decodeHeight == null
          ? FileImage(file)
          : _FittedLocalFileImage(
              file,
              width: decodeWidth,
              height: decodeHeight,
              fit: fit,
            );
    }
    final image = Image(
      image: provider,
      width: width,
      height: height,
      fit: fit,
      gaplessPlayback: true,
      filterQuality: FilterQuality.low,
      frameBuilder: fadeInDuration == null
          ? null
          : (context, child, frame, wasSynchronouslyLoaded) {
              final ready = wasSynchronouslyLoaded || frame != null;
              if (fadeInDuration == Duration.zero) {
                return ready ? child : placeholder(context);
              }
              // The image supplies its explicit/intrinsic size in list rows,
              // where both incoming axes may be unbounded. Expanding the
              // placeholder here would give the entire row infinite bounds.
              return Stack(
                fit: StackFit.passthrough,
                children: [
                  Positioned.fill(child: placeholder(context)),
                  AnimatedOpacity(
                    opacity: ready ? 1.0 : 0.0,
                    duration: fadeInDuration!,
                    curve: Curves.easeOutCubic,
                    child: child,
                  ),
                ],
              );
            },
      errorBuilder: (_, _, _) => placeholder(context),
    );
    return borderRadius == null
        ? image
        : ClipRRect(borderRadius: borderRadius!, child: image);
  }

  static int? _localDecodeExtent(BuildContext context, double? size) {
    if (size == null || !size.isFinite || size <= 0) return null;
    return (size * MediaQuery.devicePixelRatioOf(context)).ceil();
  }
}

/// Lets Flutter read intrinsic dimensions before choosing the decode size.
/// FileImage still owns file loading, codec creation and image lifecycle.
class _FittedLocalFileImage extends FileImage {
  final int? width;
  final int? height;
  final BoxFit fit;

  const _FittedLocalFileImage(
    super.file, {
    required this.width,
    required this.height,
    required this.fit,
  });

  @override
  ImageStreamCompleter loadImage(FileImage key, ImageDecoderCallback decode) {
    return super.loadImage(key, (buffer, {getTargetSize}) {
      return decode(
        buffer,
        getTargetSize: (intrinsicWidth, intrinsicHeight) {
          final double ratio;
          if (width != null && height != null) {
            final fitted = applyBoxFit(
              fit,
              Size(intrinsicWidth.toDouble(), intrinsicHeight.toDouble()),
              Size(width!.toDouble(), height!.toDouble()),
            );
            ratio = math.max(
              fitted.destination.width / fitted.source.width,
              fitted.destination.height / fitted.source.height,
            );
          } else if (fit == BoxFit.none) {
            ratio = 1;
          } else {
            ratio = width != null
                ? width! / intrinsicWidth
                : height! / intrinsicHeight;
          }
          // Never enlarge the decoded source. Cover uses the cropped source
          // dimensions above, retaining enough pixels along both display axes.
          final scale = ratio.clamp(0.0, 1.0);
          return ui.TargetImageSize(
            width: (intrinsicWidth * scale).ceil().clamp(1, intrinsicWidth),
            height: (intrinsicHeight * scale).ceil().clamp(1, intrinsicHeight),
          );
        },
      );
    });
  }

  @override
  bool operator ==(Object other) =>
      other is _FittedLocalFileImage &&
      super == other &&
      width == other.width &&
      height == other.height &&
      fit == other.fit;

  @override
  int get hashCode => Object.hash(super.hashCode, width, height, fit);
}
