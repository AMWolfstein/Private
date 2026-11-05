import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/performance/glass_poc_mode_provider.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_surface.dart';

/// Developer-only Glass POC. Shows the same header, scrolling list, mini
/// player and tab bar in each [SistrumGlassMode], over a background that is
/// either static or animated. Nothing here is wired into production screens.
class GlassPocPage extends ConsumerStatefulWidget {
  const GlassPocPage({super.key});

  @override
  ConsumerState<GlassPocPage> createState() => _GlassPocPageState();
}

class _GlassPocPageState extends ConsumerState<GlassPocPage>
    with SingleTickerProviderStateMixin {
  static const double _sideInset = 16;

  late final AnimationController _background = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 12),
  );
  bool _animated = false;
  bool _outlines = false;

  @override
  void dispose() {
    // Disposing the controller also stops its ticker, so nothing keeps
    // animating after the page leaves the tree.
    _background.dispose();
    super.dispose();
  }

  void _setAnimated(bool value) {
    setState(() => _animated = value);
    if (value) {
      _background.repeat();
    } else {
      _background
        ..stop()
        ..value = 0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mode = ref.watch(glassPocModeProvider);
    final notifier = ref.read(glassPocModeProvider.notifier);
    final sharedBackdrop = ref.watch(glassPocSharedBackdropProvider);
    final width = MediaQuery.sizeOf(context).width;
    final barWidth = width - 2 * _sideInset;

    return Scaffold(
      appBar: AppBar(title: const Text('Glass POC')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(_sideInset, 8, _sideInset, 0),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final m in SistrumGlassMode.values)
                  ChoiceChip(
                    label: Text(m.label),
                    selected: mode == m,
                    onSelected: (_) => notifier.select(m),
                  ),
              ],
            ),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Animated background'),
            value: _animated,
            onChanged: _setAnimated,
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Shared backdrop group (Reference Glass only)'),
            subtitle: const Text(
              'Comparison: one shared backdrop read for the Reference surfaces',
            ),
            value: sharedBackdrop,
            onChanged: (v) =>
                ref.read(glassPocSharedBackdropProvider.notifier).set(v),
          ),
          SwitchListTile(
            dense: true,
            title: const Text('Show layout outlines (diagnostic only)'),
            value: _outlines,
            onChanged: (v) => setState(() => _outlines = v),
          ),
          Expanded(
            child: ClipRect(
              child: SistrumGlassScope(
                mode: mode,
                sharedBackdrop: sharedBackdrop,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: AnimatedBuilder(
                        animation: _background,
                        builder: (context, _) => CustomPaint(
                          painter: _PocBackgroundPainter(
                            progress: _animated ? _background.value : 0,
                            dark:
                                Theme.of(context).brightness == Brightness.dark,
                          ),
                        ),
                      ),
                    ),
                    Positioned.fill(
                      child: ListView.builder(
                        padding: const EdgeInsets.only(
                          top: _GlassPocPageConstants.headerHeight + 24,
                          bottom: 2 * _GlassPocPageConstants.barHeight + 40,
                        ),
                        itemCount: 60,
                        itemBuilder: (context, i) => Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: _sideInset,
                            vertical: 10,
                          ),
                          child: Text(
                            'Track ${i + 1} — scrolling content under glass',
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: _sideInset,
                      right: _sideInset,
                      child: _PocHeader(mode: mode, outline: _outlines),
                    ),
                    Positioned(
                      left: _sideInset,
                      bottom: 12,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _PocMiniPlayer(
                            mode: mode,
                            width: barWidth,
                            outline: _outlines,
                          ),
                          const SizedBox(height: 10),
                          _PocTabBar(
                            mode: mode,
                            width: barWidth,
                            outline: _outlines,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PocHeader extends StatelessWidget {
  const _PocHeader({required this.mode, required this.outline});

  final SistrumGlassMode mode;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    const size = _GlassPocPageConstants.headerHeight;
    return Row(
      children: [
        SistrumGlassSurface(
          mode: mode,
          width: size,
          height: size,
          borderRadius: size / 2,
          diagnosticOutline: outline,
          child: _PocTap(icon: Icons.arrow_back, onTap: () {}),
        ),
        const Spacer(),
        // One capsule for the trailing group, as in the production header.
        SistrumGlassSurface(
          mode: mode,
          width: size * 2.2,
          height: size,
          borderRadius: size / 2,
          diagnosticOutline: outline,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _PocTap(icon: Icons.search, onTap: () {}),
              _PocTap(icon: Icons.more_horiz, onTap: () {}),
            ],
          ),
        ),
      ],
    );
  }
}

class _PocMiniPlayer extends StatelessWidget {
  const _PocMiniPlayer({
    required this.mode,
    required this.width,
    required this.outline,
  });

  final SistrumGlassMode mode;
  final double width;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    return SistrumGlassSurface(
      mode: mode,
      width: width,
      height: _GlassPocPageConstants.barHeight,
      borderRadius: _GlassPocPageConstants.barHeight / 2,
      diagnosticOutline: outline,
      child: Row(
        children: [
          const SizedBox(width: 16),
          const Icon(Icons.music_note, size: 20),
          const SizedBox(width: 12),
          const Expanded(
            child: Text('Mini player', overflow: TextOverflow.ellipsis),
          ),
          _PocTap(icon: Icons.play_arrow, onTap: () {}),
        ],
      ),
    );
  }
}

class _PocTabBar extends StatelessWidget {
  const _PocTabBar({
    required this.mode,
    required this.width,
    required this.outline,
  });

  final SistrumGlassMode mode;
  final double width;
  final bool outline;

  @override
  Widget build(BuildContext context) {
    const icons = [
      Icons.home,
      Icons.library_music,
      Icons.search,
      Icons.bar_chart,
    ];
    return SistrumGlassSurface(
      mode: mode,
      width: width,
      height: _GlassPocPageConstants.barHeight,
      borderRadius: _GlassPocPageConstants.barHeight / 2,
      diagnosticOutline: outline,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < icons.length; i++)
            _PocTap(icon: icons[i], onTap: () {}, selected: i == 0),
        ],
      ),
    );
  }
}

/// A fixed-size tappable icon with ink feedback. Surfaces in every mode keep
/// the page's Material ancestor, so the ink still paints.
class _PocTap extends StatelessWidget {
  const _PocTap({
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.onSurface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox.square(
          dimension: _GlassPocPageConstants.tapSize,
          child: Icon(icon, color: color, size: 22),
        ),
      ),
    );
  }
}

/// Shared geometry constants, kept in one place so every mode lays out the
/// same surfaces.
abstract final class _GlassPocPageConstants {
  static const double headerHeight = 48;
  static const double barHeight = 56;
  static const double tapSize = 48;
}

/// Simulated artwork: a vertical gradient, drifting discs and fine stripes.
/// The stripes give refraction and blur something visible to act on. With
/// [progress] at 0 the frame is fixed, so static runs are repeatable.
class _PocBackgroundPainter extends CustomPainter {
  const _PocBackgroundPainter({required this.progress, required this.dark});

  final double progress;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final colors = dark
        ? const [Color(0xFF2B1B3D), Color(0xFF0B1A2E)]
        : const [Color(0xFFFFD8A8), Color(0xFFA8D8FF)];
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: colors,
        ).createShader(rect),
    );

    final disc = Paint()
      ..color = (dark ? const Color(0xFFE94B6E) : const Color(0xFFCC2E33))
          .withValues(alpha: 0.85);
    final discs = <(double, double, double)>[
      (0.25, 0.20, 90),
      (0.80, 0.45, 70),
      (0.35, 0.70, 120),
    ];
    for (var i = 0; i < discs.length; i++) {
      final (fx, fy, r) = discs[i];
      final angle = progress * 2 * math.pi + i * 1.7;
      final center = Offset(
        size.width * fx + math.cos(angle) * 24,
        size.height * fy + math.sin(angle) * 18,
      );
      canvas.drawCircle(center, r, disc);
    }

    final stripe = Paint()
      ..color = (dark ? Colors.white : Colors.black).withValues(alpha: 0.08);
    for (double y = 0; y < size.height; y += 12) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 2), stripe);
    }
  }

  @override
  bool shouldRepaint(_PocBackgroundPainter old) =>
      old.progress != progress || old.dark != dark;
}
