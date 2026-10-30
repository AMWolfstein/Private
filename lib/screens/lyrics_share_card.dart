import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/widgets/player/player_artwork.dart';

/// Story-sized lyric cards stay short, like quoting a song rather than
/// reproducing its lyrics.
const lyricsShareMaxLines = 5;

/// The logical size of the shared card; captured at 3× for 1080×1920.
const lyricsShareCardSize = Size(360, 640);

/// One selectable lyric line.
typedef LyricsShareLine = ({String text, bool background});

enum LyricsCardBackground { artwork, color, dark, light }

/// The shared image: quoted lines over a background derived from the cover.
/// It has a fixed logical size so the export never depends on the device.
class LyricsShareCard extends StatelessWidget {
  const LyricsShareCard({
    super.key,
    required this.title,
    required this.artist,
    required this.artUri,
    required this.lines,
    required this.background,
    this.coverColors,
    this.placeholder,
  });

  final String title;
  final String artist;
  final String? artUri;
  final List<LyricsShareLine> lines;
  final LyricsCardBackground background;

  /// Average cover color for [LyricsCardBackground.color].
  final CoverColors? coverColors;

  /// Shown faintly in the preview while no line is selected.
  final String? placeholder;

  /// Larger type for short quotes, smaller for long ones, so every selection
  /// fills the card comfortably.
  static double fontSizeFor(List<LyricsShareLine> lines) {
    final length = lines.fold<int>(0, (sum, line) => sum + line.text.length);
    if (length <= 40) return 36;
    if (length <= 90) return 31;
    if (length <= 160) return 26;
    return 22;
  }

  @override
  Widget build(BuildContext context) {
    final light = background == LyricsCardBackground.light;
    final foreground = light ? const Color(0xFF111111) : Colors.white;
    final secondary = foreground.withValues(alpha: 0.7);
    final fontSize = fontSizeFor(lines);
    final scheme = Theme.of(context).colorScheme;
    return MediaQuery.withNoTextScaling(
      child: SizedBox.fromSize(
        size: lyricsShareCardSize,
        child: Stack(
          fit: StackFit.expand,
          children: [
            _background(scheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 40, 28, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Spacer(),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(22),
                    decoration: BoxDecoration(
                      color: foreground.withValues(alpha: light ? 0.06 : 0.12),
                      borderRadius: BorderRadius.circular(28),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(10),
                              child: SizedBox.square(
                                dimension: 52,
                                child: PlayerArtwork(
                                  artUri: artUri,
                                  colorScheme: scheme,
                                  iconSize: 24,
                                  cacheWidth: 156,
                                ),
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: foreground,
                                      fontSize: 16,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                  if (artist.isNotEmpty)
                                    Text(
                                      artist,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        color: secondary,
                                        fontSize: 13,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 22),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 380),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: AlignmentDirectional.topStart,
                            child: SizedBox(
                              width: lyricsShareCardSize.width - 100,
                              child: lines.isEmpty
                                  ? Text(
                                      placeholder ?? '',
                                      style: TextStyle(
                                        color: foreground.withValues(
                                          alpha: 0.4,
                                        ),
                                        fontSize: 20,
                                        fontWeight: FontWeight.w500,
                                      ),
                                    )
                                  : Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        for (final line in lines)
                                          Padding(
                                            padding: const EdgeInsets.only(
                                              bottom: 6,
                                            ),
                                            child: Text(
                                              line.text,
                                              style: TextStyle(
                                                color: line.background
                                                    ? secondary
                                                    : foreground,
                                                fontSize: line.background
                                                    ? fontSize * 0.72
                                                    : fontSize,
                                                height: 1.2,
                                                fontWeight: line.background
                                                    ? FontWeight.w400
                                                    : FontWeight.w500,
                                                letterSpacing: -0.2,
                                              ),
                                            ),
                                          ),
                                      ],
                                    ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  Center(
                    child: Container(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                        6,
                        6,
                        14,
                        6,
                      ),
                      decoration: ShapeDecoration(
                        color: foreground.withValues(
                          alpha: light ? 0.06 : 0.14,
                        ),
                        shape: const StadiumBorder(),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/logo-transparent.png',
                            width: 26,
                            height: 26,
                            errorBuilder: (_, _, _) => const SizedBox.shrink(),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Sistrum',
                            style: TextStyle(
                              color: foreground,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 0.1,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _background(ColorScheme scheme) {
    switch (background) {
      case LyricsCardBackground.artwork:
        return Stack(
          fit: StackFit.expand,
          children: [
            const ColoredBox(color: Color(0xFF1B1B1F)),
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 36,
                sigmaY: 36,
                tileMode: TileMode.mirror,
              ),
              child: Transform.scale(
                scale: 1.3,
                child: PlayerArtwork(
                  artUri: artUri,
                  colorScheme: scheme,
                  cacheWidth: 360,
                ),
              ),
            ),
            const ColoredBox(color: Color(0x47000000)),
          ],
        );
      case LyricsCardBackground.color:
        final colors = coverColors ?? appCoverColors(null);
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.tone(44), colors.tone(20)],
            ),
          ),
        );
      case LyricsCardBackground.dark:
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF26262B), Color(0xFF0B0B0D)],
            ),
          ),
        );
      case LyricsCardBackground.light:
        return const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFFFFFFFF), Color(0xFFEDE9E1)],
            ),
          ),
        );
    }
  }
}
