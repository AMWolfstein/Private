import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

class PlayerArtwork extends StatelessWidget {
  /// A local artwork path or file URI.
  final String? artUri;
  final ColorScheme colorScheme;
  final int? cacheWidth;
  final double iconSize;

  const PlayerArtwork({
    super.key,
    required this.artUri,
    required this.colorScheme,
    this.cacheWidth,
    this.iconSize = 40,
  });

  /// Share one full-size decode while artwork moves between player panels.
  static int transitionCacheWidth(BuildContext context) =>
      (MediaQuery.sizeOf(context).width *
              MediaQuery.devicePixelRatioOf(context))
          .round();

  @override
  Widget build(BuildContext context) {
    final placeholder = Container(
      color: colorScheme.surfaceContainerHighest,
      child: Icon(
        Icons.music_note,
        size: iconSize,
        color: colorScheme.onSurfaceVariant,
      ),
    );

    final uri = artUri;
    // Remote artwork is never loaded: legacy rows may still carry an http URL.
    if (uri == null || uri.isEmpty || uri.startsWith('http')) {
      return placeholder;
    }

    if (uri.startsWith('file://') || p.isAbsolute(uri)) {
      final path = uri.startsWith('file://')
          ? Uri.parse(uri).toFilePath()
          : uri;
      return Image.file(
        File(path),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => placeholder,
      );
    }
    return placeholder;
  }
}
