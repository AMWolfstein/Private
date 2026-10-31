part of 'listening_rewind_screen.dart';

class _Artwork extends StatelessWidget {
  const _Artwork({required this.uri, required this.size, this.artist = false});

  final String? uri;
  final double size;
  final bool artist;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final image = SizedBox.square(
      dimension: size,
      child: uri == null
          ? ColoredBox(
              color: colors.surfaceContainerHighest,
              child: Icon(
                artist ? Icons.person : Icons.music_note,
                size: size * 0.4,
                color: colors.onSurfaceVariant,
              ),
            )
          : PlayerArtwork(
              artUri: uri,
              colorScheme: colors,
              cacheWidth: (size * MediaQuery.devicePixelRatioOf(context))
                  .ceil(),
              iconSize: size * 0.4,
            ),
    );
    if (artist) return ClipOval(child: image);
    final radius = size * 0.06;
    return ClipRRect(borderRadius: BorderRadius.circular(radius), child: image);
  }
}

class _RankedRow extends StatelessWidget {
  const _RankedRow({
    required this.artwork,
    required this.title,
    required this.subtitle,
    this.rank,
  });

  final int? rank;
  final Widget artwork;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = DefaultTextStyle.of(context).style.color;
    return Row(
      children: [
        if (rank case final rank?)
          SizedBox(
            width: 40,
            child: Text(
              '$rank',
              style: textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.w800,
                color: color?.withValues(alpha: 0.55),
              ),
            ),
          ),
        artwork,
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
              Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodyMedium?.copyWith(
                  color: color?.withValues(alpha: 0.8),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Big counted-up figures in a two-column grid.
class _StatGrid extends StatelessWidget {
  const _StatGrid({required this.stats, required this.format});

  final List<(int, String)> stats;
  final String Function(num) format;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = DefaultTextStyle.of(context).style.color;
    Widget stat((int, String) entry) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _CountUp(value: entry.$1, format: format, fontSize: 56),
        Text(
          entry.$2,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: color?.withValues(alpha: 0.8),
          ),
        ),
      ],
    );
    return Column(
      children: [
        for (var i = 0; i < stats.length; i += 2) ...[
          if (i > 0) const SizedBox(height: 20),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: stat(stats[i])),
              const SizedBox(width: 16),
              Expanded(
                child: i + 1 < stats.length
                    ? stat(stats[i + 1])
                    : const SizedBox.shrink(),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// Twelve bars of monthly listening; [highlight] stands out at full color.
class _MonthChart extends StatelessWidget {
  const _MonthChart({
    required this.milliseconds,
    required this.highlight,
    required this.year,
    required this.accent,
  });

  final Map<int, int> milliseconds;
  final int highlight;
  final int year;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.localeOf(context).toLanguageTag();
    // Stand-alone narrow month names (J, F, M...).
    final narrow = DateFormat('LLLLL', locale);
    final peak = milliseconds.values.fold(0, math.max);
    final labelStyle = Theme.of(context).textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: accent.withValues(alpha: 0.8),
    );
    final reduced = MediaQuery.disableAnimationsOf(context);
    return ExcludeSemantics(
      child: SizedBox(
        height: 180,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var month = 1; month <= 12; month++) ...[
              if (month > 1) const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Align(
                        alignment: Alignment.bottomCenter,
                        // Bars grow from the baseline, the peak month last.
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: reduced ? 1 : 0, end: 1),
                          duration: reduced
                              ? Duration.zero
                              : Duration(milliseconds: 600 + month * 60),
                          curve: Curves.easeOutCubic,
                          builder: (context, t, _) => FractionallySizedBox(
                            heightFactor:
                                peak <= 0 || (milliseconds[month] ?? 0) <= 0
                                ? 0
                                : math.max(
                                        0.04,
                                        (milliseconds[month] ?? 0) / peak,
                                      ) *
                                      t,
                            child: DecoratedBox(
                              decoration: ShapeDecoration(
                                color: month == highlight
                                    ? accent
                                    : accent.withValues(alpha: 0.3),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              child: const SizedBox(width: double.infinity),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      narrow.format(DateTime(year, month)),
                      style: labelStyle,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Each month beside the artist heard longest that month, in two columns.
class _MonthArtists extends StatelessWidget {
  const _MonthArtists({required this.months, required this.artwork});

  /// Short month name and artist, in calendar order.
  final List<(String, String)> months;
  final Map<String, String> artwork;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = DefaultTextStyle.of(context).style.color;
    Widget row((String, String) entry) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          _Artwork(uri: artwork[entry.$2], size: 36, artist: true),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.$1,
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color?.withValues(alpha: 0.7),
                  ),
                ),
                Text(
                  entry.$2,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: color,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
    final half = (months.length / 2).ceil();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(children: [for (final e in months.take(half)) row(e)]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(children: [for (final e in months.skip(half)) row(e)]),
        ),
      ],
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.label, required this.value, this.detail});

  final String label;
  final String value;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final color = DefaultTextStyle.of(context).style.color;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: textTheme.labelLarge?.copyWith(
            color: color?.withValues(alpha: 0.75),
          ),
        ),
        Text(
          detail == null ? value : '$value · $detail',
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }
}

/// A neutral Sistrum tile replaces upstream Expressive decorative shapes.
class _RewindBadge extends StatelessWidget {
  const _RewindBadge({
    required this.size,
    required this.color,
    required this.child,
  });
  final double size;
  final Color color;
  final Widget child;
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(size * 0.3),
    ),
    alignment: Alignment.center,
    child: child,
  );
}
