import 'package:sistrum/providers/equalizer_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:sistrum/constants/app_info.dart';
import 'package:sistrum/screens/main_shell.dart';
import 'package:sistrum/screens/setup_screen.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/navigation/app_navigation.dart';
import 'package:sistrum/services/app_orientation.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/l10n/supported_locales.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/widgets/glass/app_backdrop_groups.dart';
import 'package:sistrum/widgets/glass/app_glass_auto_probe_host.dart';
import 'package:sistrum/widgets/glass/app_performance_hud.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/player/playback_feedback.dart';
import 'dart:async';
import 'package:sistrum/theme/app_glass_levels.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/widgets/glass/app_glass_warmup.dart';
import 'package:sistrum/widgets/glass/app_artwork_glass.dart';
import 'package:sistrum/providers/theme_provider.dart';
import 'package:sistrum/providers/custom_font_provider.dart';
import 'package:sistrum/theme/app_theme.dart';

String initialLocationForAppState({
  required bool isFirstLaunch,
  required bool hasCompletedTutorial,
}) {
  if (isFirstLaunch || !hasCompletedTutorial) return '/setup';
  return '/';
}

final _routerProvider = Provider<GoRouter>((ref) {
  final routingSettings = ref.watch(
    settingsProvider.select(
      (settings) => (
        isFirstLaunch: settings.isFirstLaunch,
        hasCompletedTutorial: settings.hasCompletedTutorial,
      ),
    ),
  );

  final initialLocation = initialLocationForAppState(
    isFirstLaunch: routingSettings.isFirstLaunch,
    hasCompletedTutorial: routingSettings.hasCompletedTutorial,
  );

  return GoRouter(
    navigatorKey: AppNavigationService.rootNavigatorKey,
    observers: [AppOrientationObserver()],
    initialLocation: initialLocation,
    routes: [
      GoRoute(path: '/', builder: (context, state) => const MainShell()),
      GoRoute(path: '/setup', builder: (context, state) => const SetupScreen()),
    ],
    // Safety net: if an unknown deep link somehow reaches GoRouter, redirect
    // to home instead of showing "Page Not Found".
    errorBuilder: (context, state) => const MainShell(),
  );
});

Locale _fallbackLocale(Iterable<Locale> supportedLocales) {
  for (final supportedLocale in supportedLocales) {
    if (supportedLocale.languageCode == 'en') {
      return supportedLocale;
    }
  }
  return supportedLocales.first;
}

Locale _resolveSupportedLocale(
  Locale? requestedLocale,
  Iterable<Locale> supportedLocales,
) {
  if (requestedLocale == null) {
    return _fallbackLocale(supportedLocales);
  }

  for (final supportedLocale in supportedLocales) {
    if (supportedLocale.languageCode == requestedLocale.languageCode &&
        supportedLocale.countryCode == requestedLocale.countryCode) {
      return supportedLocale;
    }
  }

  for (final supportedLocale in supportedLocales) {
    if (supportedLocale.languageCode == requestedLocale.languageCode) {
      return supportedLocale;
    }
  }

  return _fallbackLocale(supportedLocales);
}

/// iOS-style fluid scroll everywhere: momentum glide + bounce instead of the
/// Android clamping stop. Widgets that set explicit physics (queue filter
/// PageView, bottom sheets) are unaffected.
class _FluidScrollBehavior extends MaterialScrollBehavior {
  const _FluidScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
}

/// Fades the app content in after an orientation change or a width change
/// across the shell's rail breakpoint (fold/unfold, split-screen resize) —
/// Flutter reflows the layout in a single frame, so without this the new
/// layout pops in.
class _OrientationFade extends StatefulWidget {
  final Widget child;

  const _OrientationFade({required this.child});

  @override
  State<_OrientationFade> createState() => _OrientationFadeState();
}

class _OrientationFadeState extends State<_OrientationFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 300),
    value: 1,
  );
  Orientation? _lastOrientation;
  double? _lastWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final orientation = MediaQuery.orientationOf(context);
    final width = MediaQuery.sizeOf(context).width;
    final orientationChanged =
        _lastOrientation != null && orientation != _lastOrientation;
    final crossedRailBreakpoint =
        _lastWidth != null &&
        useNavigationRailForWidth(_lastWidth!) !=
            useNavigationRailForWidth(width);
    if (orientationChanged || crossedRailBreakpoint) {
      _controller.forward(from: 0);
    }
    _lastOrientation = orientation;
    _lastWidth = width;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: CurvedAnimation(parent: _controller, curve: Curves.easeOut),
      child: widget.child,
    );
  }
}

class SistrumApp extends ConsumerWidget {
  final bool disableOverscrollEffects;

  const SistrumApp({super.key, this.disableOverscrollEffects = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(equalizerProvider);
    final router = ref.watch(_routerProvider);
    final localeString = ref.watch(settingsProvider.select((s) => s.locale));
    final heroAnimationsEnabled = ref.watch(
      settingsProvider.select((s) => s.heroAnimationsEnabled),
    );
    final scrollBehavior = disableOverscrollEffects
        ? const MaterialScrollBehavior().copyWith(overscroll: false)
        : const _FluidScrollBehavior();

    Locale? locale;
    if (localeString != 'system' && localeString.isNotEmpty) {
      if (localeString.contains('_')) {
        final parts = localeString.split('_');
        if (parts.length == 2) {
          locale = Locale(parts[0], parts[1]);
        } else {
          locale = Locale(parts[0]);
        }
      } else {
        locale = Locale(localeString);
      }
    }

    return AppThemeWrapper(
      builder: (lightTheme, darkTheme, themeMode) {
        return MaterialApp.router(
          title: AppInfo.appName,
          debugShowCheckedModeBanner: false,
          theme: lightTheme,
          darkTheme: darkTheme,
          themeMode: themeMode,
          scrollBehavior: scrollBehavior,
          themeAnimationDuration: const Duration(milliseconds: 300),
          themeAnimationCurve: Curves.easeInOut,
          // Treat the display as one continuous surface so bottom sheets and
          // dialogs stay centered on large/foldable devices.
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            final appContent = _OrientationFade(
              child: AppScaffoldMessenger(
                child: PlaybackFeedback(
                  // Header controls on pages outside the tabs (Settings and
                  // what it opens) share one backdrop read, like the shell's.
                  child: AppChromeBatch(
                    child: child ?? const SizedBox.shrink(),
                  ),
                ),
              ),
            );
            return MediaQuery(
              data: mediaQuery.copyWith(displayFeatures: const []),
              // HeroMode only affects heroes below a *route* subtree. At this
              // level it sits above the router's Navigator, so the controller
              // never encounters it while collecting heroes. Removing the
              // inherited controller disables flights on the root Navigator.
              child: AppGlassPreparation(
                child: AppGlassAutoProbeHost(
                  child: AppPerformanceHudHost(
                    child: AdaptiveUiScaler(
                      child: heroAnimationsEnabled
                          ? appContent
                          : HeroControllerScope.none(child: appContent),
                    ),
                  ),
                ),
              ),
            );
          },
          routerConfig: router,
          locale: locale,
          localeResolutionCallback: (deviceLocale, supportedLocales) {
            return _resolveSupportedLocale(
              locale ?? deviceLocale,
              supportedLocales,
            );
          },
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          // ARB files below the translation threshold remain bundled so
          // translators can test them, but production users should only be
          // offered locales selected by the completion checker.
          supportedLocales: filteredSupportedLocales,
        );
      },
    );
  }
}

/// Starts the one-time preparation when the full glass theme is enabled,
/// including switching to Sistrum or enabling blur after the app has started.
class AppGlassPreparation extends ConsumerWidget {
  const AppGlassPreparation({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // The artwork glass program loads at start whatever the level, so the
    // first menu over the player has nothing left to load.
    unawaited(AppArtworkGlassProgram.load());
    // Lenses appear on full glass above Level 1, and as touch-only thumbs
    // and segment pills under lite.
    if (ref.watch(appBlurEnabledProvider) &&
        !appGlassClarity(
          ref.watch(appGlassClarityLevelProvider),
        ).plainBlur &&
        !ref.watch(
          appGlassContrastBlockedProvider(
            MediaQuery.highContrastOf(context),
          ),
        )) {
      unawaited(AppGlassWarmup.prepare(View.of(context)));
      // Its pipeline too, where it can refract.
      if (ref.watch(appShaderFiltersSupportedProvider)) {
        unawaited(AppArtworkGlassProgram.prepare());
      }
    }
    return child;
  }
}

class AppThemeWrapper extends ConsumerWidget {
  final Widget Function(ThemeData light, ThemeData dark, ThemeMode mode)
  builder;

  const AppThemeWrapper({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Select only what ThemeData needs; glass preferences have their own
    // providers so the clarity slider does not rebuild MaterialApp.
    final accent = ref.watch(themeProvider.select((s) => s.appAccent));
    final useSystemFont = ref.watch(
      themeProvider.select((s) => s.useSystemFont),
    );
    final themeMode = ref.watch(themeProvider.select((s) => s.themeMode));
    final fontFamily = ref.watch(customFontFamilyProvider).asData?.value;

    return builder(
      AppTheme.build(
        Brightness.light,
        accent: accent,
        useSystemFont: useSystemFont,
        fontFamily: fontFamily,
      ),
      AppTheme.build(
        Brightness.dark,
        accent: accent,
        useSystemFont: useSystemFont,
        fontFamily: fontFamily,
      ),
      themeMode,
    );
  }
}
