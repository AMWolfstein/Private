/// Repeatable developer-only scenes for the Glass POC comparison. A scene
/// fixes the surface count, the background animation and the list scrolling,
/// so every renderer runs the same workload.
enum SistrumGlassScene {
  /// Scene A: one glass surface (the mini player) over a static background.
  oneSurface(
    'A · One surface, static',
    surfaces: 1,
    animated: false,
    scrolling: false,
  ),

  /// Scene B: four surfaces over a static background.
  fourSurfaces(
    'B · Four surfaces, static',
    surfaces: 4,
    animated: false,
    scrolling: false,
  ),

  /// Scene C: four surfaces over an animated background.
  animatedBackground(
    'C · Four surfaces, animated',
    surfaces: 4,
    animated: true,
    scrolling: false,
  ),

  /// Scene D: four surfaces over content that scrolls at a fixed pace.
  scrollingContent(
    'D · Four surfaces, scrolling',
    surfaces: 4,
    animated: false,
    scrolling: true,
  );

  const SistrumGlassScene(
    this.label, {
    required this.surfaces,
    required this.animated,
    required this.scrolling,
  });

  final String label;

  /// Number of glass surfaces shown: 1 (scene A) or 4.
  final int surfaces;

  /// Whether the background animates.
  final bool animated;

  /// Whether the list scrolls on its own.
  final bool scrolling;
}
