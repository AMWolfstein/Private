import 'package:flutter/material.dart';
import 'package:sistrum/widgets/header/album_ken_burns.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/providers/cover_palette_provider.dart';

/// Height of the player's full-bleed artwork on a [screen]: [aspectRatio]
/// (immersive) up to 0.75 of the height, else square or 0.66 of the height.
double appPlayerArtworkHeight(
  Size screen, {
  required bool square,
  double? aspectRatio,
}) => aspectRatio != null && aspectRatio > 0
    ? (screen.width / aspectRatio).clamp(0.0, screen.height * 0.75)
    : square
    ? screen.width
    : screen.height * 0.66;

/// Where the full-bleed artwork is fully faded out. The Ken Burns drift
/// zooms to 1.06 and pans up to 80% of the extra cover, moving the bottom
/// edge at most 5.4% of the height, so 0.94 keeps the box edge clear.
const kAppPlayerFadeEnd = 0.94;

/// Opaque cover-derived surface, with full-bleed artwork on the player page
/// and a muted two-tone gradient behind lyrics and the queue.
class AppPlayerBackground extends StatelessWidget {
  const AppPlayerBackground({
    super.key,
    required this.artUri,
    this.artwork,
    this.squareArtwork = true,
    this.showArtwork = true,
    this.artworkAspectRatio,
    this.fadeStart = .58,
  });

  final Uri? artUri;
  final Widget? artwork;
  final bool squareArtwork;
  final bool showArtwork;
  final double? artworkAspectRatio;
  final double fadeStart;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final source = artUri?.scheme == 'file'
        ? artUri!.toFilePath()
        : artUri?.toString();

    return Theme(
      // Missing or unreadable covers use neutral gray, not the app's accent.
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          brightness: Brightness.dark,
          primary: const Color(0xff808080),
        ),
      ),
      child: CoverPaletteBuilder(
        palette: paletteOf(context),
        imageSource: source,
        builder: (context, _) {
          // Continue the artwork's bottom edge; lyrics and the queue use a
          // deeper two-tone gradient of the same colour.
          final colors = paletteOf(context).colors(source);
          final motion = MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 380);
          return AnimatedContainer(
            duration: motion,
            curve: Curves.easeInOutCubic,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: artwork == null
                    ? Alignment.topLeft
                    : Alignment.topCenter,
                end: artwork == null
                    ? Alignment.bottomRight
                    : Alignment.bottomCenter,
                stops: artwork == null ? null : const [0, 0.5, 1],
                colors: artwork == null
                    ? colors.playerPlainStops
                    : colors.playerStops,
              ),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: appPlayerArtworkHeight(
                    MediaQuery.sizeOf(context),
                    square: squareArtwork,
                    aspectRatio: artworkAspectRatio,
                  ),
                  child: IgnorePointer(
                    ignoring: !showArtwork,
                    child: ExcludeSemantics(
                      excluding: !showArtwork,
                      child: AnimatedOpacity(
                        opacity: showArtwork ? 1 : 0,
                        duration: motion,
                        // The fade is applied to the still cover and the
                        // drift moves the faded result; a mask over moving
                        // content left a hard edge at the bottom on device.
                        child: AlbumKenBurns(
                          active: showArtwork,
                          child: ShaderMask(
                            blendMode: BlendMode.dstIn,
                            shaderCallback: (bounds) => LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              // Fully clear before the bottom, so the drift's
                              // zoom and pan never bring a visible edge in.
                              stops: [0, fadeStart, kAppPlayerFadeEnd, 1],
                              colors: const [
                                Colors.white,
                                Colors.white,
                                Colors.transparent,
                                Colors.transparent,
                              ],
                            ).createShader(bounds),
                            child: HeroMode(
                              // The compact header owns the route hero while the
                              // full cover is fading out behind the lyrics.
                              enabled: artwork != null && showArtwork,
                              // Opacity above owns panel fades. Do not retain an
                              // outgoing globally keyed artwork during rotation
                              // or rapid Normal/Immersive preference changes.
                              child: artwork == null
                                  ? const SizedBox.shrink()
                                  : KeyedSubtree(
                                      key: const ValueKey(
                                        'full-player-artwork',
                                      ),
                                      child: artwork!,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
