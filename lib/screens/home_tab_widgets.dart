part of 'home_tab.dart';

/// Indexed local artwork first; extract only when the scanned thumbnail expires.
class _LocalFeedCover extends StatelessWidget {
  const _LocalFeedCover({
    required this.coverPath,
    required this.filePath,
    required this.width,
    required this.height,
    required this.borderRadius,
    required this.fallbackIcon,
    required this.colorScheme,
    this.fallbackIconSize = 24,
  });
  final String? coverPath, filePath;
  final double width, height, fallbackIconSize;
  final BorderRadius borderRadius;
  final IconData fallbackIcon;
  final ColorScheme colorScheme;
  Widget _fallback(BuildContext context) => Container(
    width: width,
    height: height,
    color: colorScheme.surfaceContainerHighest,
    child: Icon(
      fallbackIcon,
      color: colorScheme.onSurfaceVariant,
      size: fallbackIconSize,
    ),
  );
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: borderRadius,
    child: LocalLibraryArtworkBuilder(
      coverPath: coverPath,
      filePath: filePath,
      builder: (context, cover) => cover == null
          ? _fallback(context)
          : LocalCoverImage(
              url: cover,
              width: width,
              height: height,
              fit: BoxFit.cover,
              localCacheWidth: (width * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              placeholder: _fallback,
            ),
    ),
  );
}
