part of 'listening_rewind_screen.dart';

class ListeningRewindEntry extends StatelessWidget {
  const ListeningRewindEntry({super.key});

  @override
  Widget build(BuildContext context) => SettingsGroup(
    children: [
      SettingsItem(
        icon: Icons.auto_awesome,
        title: context.l10n.listeningRewind,
        subtitle: context.l10n.listeningRewindDescription,
        showDivider: false,
        onTap: () => showListeningRewind(context),
      ),
    ],
  );
}

/// The Library's seasonal Rewind banner. It shows only while
/// [listeningRewindSpotlightProvider] has a Rewind to offer and opens that
/// window directly.
class ListeningRewindBanner extends ConsumerWidget {
  const ListeningRewindBanner({super.key, this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final spotlight = ref.watch(listeningRewindSpotlightProvider).value;
    final child = switch (spotlight) {
      null => null,
      ListeningRewindSpotlight.monthly => _MonthlyRewindBanner(margin: margin),
      ListeningRewindSpotlight.yearly => _YearlyRewindBanner(margin: margin),
    };
    // Grows in rather than shifting the list when the check completes.
    return AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 280),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: child ?? const SizedBox(width: double.infinity),
    );
  }
}

/// The four-weekly invitation: a quiet tonal card.
class _MonthlyRewindBanner extends StatelessWidget {
  const _MonthlyRewindBanner({this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    // Sistrum keeps its neutral control fill and accent tint.
    final foreground = colors.onSurface;
    final accent = colors.primary;
    final onAccent = colors.onPrimary;
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: AppContentCard(
        color: colors.tertiaryContainer,
        shape: RoundedRectangleBorder(
          borderRadius: context.tokens.borderRadiusCard,
        ),
        child: InkWell(
          onTap: () =>
              openListeningRewind(context, ListeningRewindPeriod.weeks),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _RewindBadge(
                  size: 48,
                  color: accent,
                  child: Icon(Icons.auto_awesome, color: onAccent),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.listeningRewind,
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.listeningRewindMonthlyReady,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodyMedium?.copyWith(
                          color: foreground,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: foreground),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The once-a-year invitation: a gradient poster with the year set large
/// behind the title and expressive shapes scattered around it.
class _YearlyRewindBanner extends StatelessWidget {
  const _YearlyRewindBanner({this.margin});

  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final colors = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final year = '${DateTime.now().year}';
    final foreground = colors.onPrimary;
    final radius = BorderRadius.circular(28);
    return Padding(
      padding: margin ?? EdgeInsets.zero,
      child: Material(
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [colors.primary, colors.tertiary],
            ),
          ),
          child: InkWell(
            onTap: () =>
                openListeningRewind(context, ListeningRewindPeriod.year),
            child: Stack(
              children: [
                // The year as a giant, faded watermark.
                PositionedDirectional(
                  end: -8,
                  bottom: -28,
                  child: ExcludeSemantics(
                    child: Text(
                      year,
                      style: textTheme.displayLarge?.copyWith(
                        fontSize: 112,
                        height: 1,
                        fontWeight: FontWeight.w900,
                        color: foreground.withValues(alpha: 0.16),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: 96,
                  top: -18,
                  child: _RewindBadge(
                    size: 64,
                    color: foreground.withValues(alpha: 0.12),
                    child: const SizedBox.shrink(),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.auto_awesome,
                                  size: 18,
                                  color: foreground,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  l10n.listeningRewindYearEyebrow,
                                  style: textTheme.labelLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: 0.4,
                                    color: foreground,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Text(
                              l10n.listeningRewindYearTitle(year),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.w800,
                                color: foreground,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              l10n.listeningRewindYearBanner,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.bodyMedium?.copyWith(
                                color: foreground.withValues(alpha: 0.9),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      DecoratedBox(
                        decoration: ShapeDecoration(
                          color: foreground,
                          shape: const CircleBorder(),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Icon(
                            Icons.play_arrow_rounded,
                            color: colors.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
