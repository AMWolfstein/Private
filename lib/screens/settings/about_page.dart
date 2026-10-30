import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/core/constants/app_info.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/core/theme/app_icons.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/utils/layout/nav_bar_inset.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';

class AboutPage extends ConsumerStatefulWidget {
  const AboutPage({super.key});

  /// Taps on the version row that reveal the developer options.
  static const developerTaps = 7;

  @override
  ConsumerState<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends ConsumerState<AboutPage> {
  int _versionTaps = 0;

  void _onVersionTap() {
    if (ref.read(settingsProvider).developerOptionsUnlocked) return;
    if (++_versionTaps < AboutPage.developerTaps) return;
    _versionTaps = 0;
    ref.read(settingsProvider.notifier).setDeveloperOptionsUnlocked(true);
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(context.l10n.aboutDeveloperOptionsEnabled)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final developer = ref.watch(
      settingsProvider.select(
        (s) => (
          unlocked: s.developerOptionsUnlocked,
          hud: s.performanceHudEnabled,
          sampler: !s.barSamplerDisabled,
          bandBlur: !s.headerBandBlurDisabled,
        ),
      ),
    );

    return PopScope(
      canPop: true,
      child: Scaffold(
        body: CustomScrollView(
          slivers: [
            AppSliverHeader.page(title: context.l10n.aboutTitle),

            SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16 + wideListInset(context),
                  16,
                  16 + wideListInset(context),
                  8,
                ),
                child: _AppHeaderCard(),
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(title: context.l10n.aboutApp),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  _AboutSettingsItem(
                    key: const ValueKey('about-version'),
                    icon: Icons.info_outline,
                    title: context.l10n.aboutVersion,
                    subtitle:
                        'v${AppInfo.displayVersion} (build ${AppInfo.buildNumber})',
                    showDivider: false,
                    onTap: _onVersionTap,
                  ),
                ],
              ),
            ),

            if (developer.unlocked) ...[
              SliverToBoxAdapter(
                child: SettingsSectionHeader(
                  title: context.l10n.aboutDeveloperOptions,
                ),
              ),
              SliverToBoxAdapter(
                child: SettingsGroup(
                  children: [
                    SettingsSwitchItem(
                      key: const ValueKey('performance-hud'),
                      icon: Icons.speed,
                      title: context.l10n.aboutPerformanceHud,
                      subtitle: context.l10n.aboutPerformanceHudSubtitle,
                      value: developer.hud,
                      onChanged: ref
                          .read(settingsProvider.notifier)
                          .setPerformanceHudEnabled,
                    ),
                    // A/B switches for measuring glass costs on their own.
                    SettingsSwitchItem(
                      key: const ValueKey('developer-bar-sampler'),
                      icon: Icons.contrast,
                      title: context.l10n.aboutBarSampler,
                      subtitle: context.l10n.aboutBarSamplerSubtitle,
                      value: developer.sampler,
                      onChanged: (on) => ref
                          .read(settingsProvider.notifier)
                          .setBarSamplerDisabled(!on),
                    ),
                    SettingsSwitchItem(
                      key: const ValueKey('developer-header-band-blur'),
                      icon: Icons.blur_on,
                      title: context.l10n.aboutHeaderBandBlur,
                      subtitle: context.l10n.aboutHeaderBandBlurSubtitle,
                      value: developer.bandBlur,
                      onChanged: (on) => ref
                          .read(settingsProvider.notifier)
                          .setHeaderBandBlurDisabled(!on),
                    ),
                    _AboutSettingsItem(
                      key: const ValueKey('developer-remeasure-glass'),
                      icon: Icons.refresh,
                      title: context.l10n.aboutRemeasureGlass,
                      subtitle: context.l10n.aboutRemeasureGlassSubtitle,
                      onTap: ref
                          .read(appGlassAutoResultProvider.notifier)
                          .clear,
                    ),
                    _AboutSettingsItem(
                      icon: Icons.visibility_off_outlined,
                      title: context.l10n.aboutHideDeveloperOptions,
                      showDivider: false,
                      onTap: () => ref
                          .read(settingsProvider.notifier)
                          .setDeveloperOptionsUnlocked(false),
                    ),
                  ],
                ),
              ),
            ],

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Center(
                  child: Text(
                    AppInfo.shortGitCommit.isEmpty
                        ? AppInfo.copyright
                        : '${AppInfo.copyright} · ${AppInfo.shortGitCommit}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 16)),
            const NavBarSliverSpacer(),
          ],
        ),
      ),
    );
  }
}

class _AppHeaderCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final cardColor = isDark
        ? Color.alphaBlend(
            Colors.white.withValues(alpha: 0.08),
            colorScheme.surface,
          )
        : colorScheme.surfaceContainerHighest;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cardWidth = constraints.maxWidth;
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1.0).clamp(1.0, 1.4);
        final logoSize = (shortestSide * 0.22).clamp(72.0, 88.0);
        final contentPadding = (cardWidth * 0.06).clamp(16.0, 24.0);
        final titleGap = (16 * (1 + ((textScale - 1) * 0.2))).clamp(12.0, 20.0);

        return Container(
          decoration: BoxDecoration(
            color: cardColor,
            borderRadius: BorderRadius.circular(20),
          ),
          padding: EdgeInsets.all(contentPadding),
          child: Column(
            children: [
              Image.asset(
                'assets/images/logo-transparent.png',
                width: logoSize,
                height: logoSize,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => Image.asset(
                  'assets/images/logo.png',
                  width: logoSize,
                  height: logoSize,
                  fit: BoxFit.contain,
                ),
              ),
              SizedBox(height: titleGap),
              Text(
                AppInfo.appName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'v${AppInfo.displayVersion}',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              SizedBox(height: titleGap),
              Text(
                context.l10n.aboutAppDescription,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AboutSettingsItem extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool showDivider;
  final VoidCallback? onTap;

  const _AboutSettingsItem({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.showDivider = true,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                height: 40,
                child: Icon(
                  context.adaptiveIcon(icon),
                  color: colorScheme.primary,
                  size: 24,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.bodyLarge),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle!,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            thickness: 1,
            indent: 76, // 20 + 40 + 16
            endIndent: 20,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
    return SettingsSearchTarget(
      label: title,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}
