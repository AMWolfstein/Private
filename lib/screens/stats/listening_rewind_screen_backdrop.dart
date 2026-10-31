part of 'listening_rewind_screen.dart';

class _RewindBackdrop extends StatefulWidget {
  const _RewindBackdrop({
    required this.pages,
    required this.palettes,
    required this.artworks,
  });

  final PageController pages;
  final List<_RewindPalette> palettes;
  final List<String?> artworks;

  @override
  State<_RewindBackdrop> createState() => _RewindBackdropState();
}

class _RewindBackdropState extends State<_RewindBackdrop>
    with SingleTickerProviderStateMixin {
  late final _ambient = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _ambient.stop();
    } else if (!_ambient.isAnimating) {
      _ambient.repeat();
    }
  }

  @override
  void dispose() {
    _ambient.dispose();
    super.dispose();
  }

  double get _page {
    final pages = widget.pages;
    if (pages.hasClients && pages.position.haveDimensions) {
      return pages.page ?? 0;
    }
    return pages.initialPage.toDouble();
  }

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: AnimatedBuilder(
        animation: Listenable.merge([widget.pages, _ambient]),
        builder: (context, _) {
          final last = widget.palettes.length - 1;
          final page = _page.clamp(0.0, last.toDouble());
          final from = page.floor();
          final to = math.min(from + 1, last);
          final blend = page - from;
          final t = _ambient.value * 2 * math.pi;
          return _sistrum(from, to, blend, t);
        },
      ),
    ),
  );

  Widget _sistrum(int from, int to, double blend, double t) {
    Widget artwork(String? uri, double opacity) => uri == null || opacity <= 0
        ? const SizedBox.shrink()
        : Opacity(
            opacity: opacity,
            child: Transform.scale(
              // A slow Ken Burns drift.
              scale: 1.15 + 0.06 * math.sin(t),
              child: ImageFiltered(
                imageFilter: ImageFilter.blur(sigmaX: 48, sigmaY: 48),
                child: PlayerArtwork(
                  artUri: uri,
                  colorScheme: Theme.of(context).colorScheme,
                  cacheWidth: 200,
                ),
              ),
            ),
          );
    final current = widget.artworks[from];
    final next = widget.artworks[to];
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (current == next)
            artwork(current, 1)
          else ...[
            artwork(current, 1 - blend),
            artwork(next, blend),
          ],
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.45),
                  Colors.black.withValues(alpha: 0.8),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Slide content with a staggered spring entrance.
class _Column extends StatelessWidget {
  const _Column({required this.children, this.center = false});

  final List<Widget> children;
  final bool center;

  @override
  Widget build(BuildContext context) => DefaultTextStyle.merge(
    textAlign: center ? TextAlign.center : TextAlign.start,
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: center
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.stretch,
      children: [
        for (final (index, child) in children.indexed)
          _Reveal(
            order: index,
            child: Padding(
              padding: EdgeInsets.only(top: index == 0 ? 0 : 16),
              child: child,
            ),
          ),
      ],
    ),
  );
}

class _Reveal extends StatelessWidget {
  const _Reveal({required this.order, required this.child});

  final int order;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    final motion = (
      duration: reduced ? Duration.zero : const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
    if (motion.duration == Duration.zero) return child;
    const stagger = Duration(milliseconds: 90);
    final total = motion.duration + stagger * order;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: total,
      curve: Interval(
        stagger.inMicroseconds * order / total.inMicroseconds,
        1,
        curve: motion.curve,
      ),
      builder: (context, t, child) => Opacity(
        opacity: t.clamp(0.0, 1.0),
        child: Transform.translate(
          offset: Offset(0, 28 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

class _CountUp extends StatelessWidget {
  const _CountUp({required this.value, required this.format, this.fontSize});

  final int value;
  final String Function(num) format;
  final double? fontSize;

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(
        begin: reduced ? value.toDouble() : 0,
        end: value.toDouble(),
      ),
      duration: reduced ? Duration.zero : const Duration(milliseconds: 1400),
      curve: Curves.easeOutCubic,
      builder: (context, current, _) => FittedBox(
        fit: BoxFit.scaleDown,
        child: Text(
          format(current.round()),
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: fontSize ?? 96,
            height: 1,
            fontWeight: FontWeight.w800,
            color: DefaultTextStyle.of(context).style.color,
          ),
        ),
      ),
    );
  }
}

enum _Size { regular, large, huge }

class _Headline extends StatelessWidget {
  const _Headline(this.text, {this.size = _Size.regular});

  final String text;
  final _Size size;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final style = switch (size) {
      _Size.regular => textTheme.headlineMedium,
      _Size.large => textTheme.headlineLarge,
      _Size.huge => textTheme.displayMedium,
    };
    return Text(
      text,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: style?.copyWith(
        fontWeight: FontWeight.w800,
        color: DefaultTextStyle.of(context).style.color,
      ),
    );
  }
}

class _Eyebrow extends StatelessWidget {
  const _Eyebrow(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.8),
    ),
  );
}

class _Body extends StatelessWidget {
  const _Body(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
      color: DefaultTextStyle.of(context).style.color?.withValues(alpha: 0.85),
    ),
  );
}

/// A short highlighted statement. A tinted pill rather than a card.
class _Pill extends StatelessWidget {
  const _Pill(this.text, {required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: ShapeDecoration(
      color: color.withValues(alpha: 0.14),
      shape: const StadiumBorder(),
    ),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w600,
          color: DefaultTextStyle.of(context).style.color,
        ),
      ),
    ),
  );
}
