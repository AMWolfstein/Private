import 'package:sistrum/providers/settings/equalizer_provider.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/core/constants/perf_hud_build.dart';
import 'package:sistrum/widgets/performance/perf_hud_overlay.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:sistrum/core/constants/app_info.dart';
import 'package:sistrum/screens/shell/main_shell.dart';
import 'package:sistrum/screens/setup/setup_screen.dart';
import 'package:sistrum/providers/artist_images/artist_image_providers.dart';
import 'package:sistrum/providers/animated_artwork/animated_artwork_providers.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/core/navigation/app_navigation.dart';
import 'package:sistrum/services/platform/app_orientation.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/l10n/supported_locales.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/player/controls/playback_feedback.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';
import 'package:sistrum/core/theme/app_theme.dart';

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
    ref.watch(artistImageAutoDownloadProvider);
    ref.watch(animatedArtworkAutoDownloadProvider);
    final router = ref.watch(_routerProvider);
    final localeString = ref.watch(settingsProvider.select((s) => s.locale));
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
                  child: child ?? const SizedBox.shrink(),
                ),
              ),
            );
            return MediaQuery(
              data: mediaQuery.copyWith(displayFeatures: const []),
              // The developer HUD sits above the navigator, so it floats over
              // every route, dialog and sheet. It is absent unless the build
              // allows it.
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AdaptiveUiScaler(child: appContent),
                  if (kPerfHudBuildAllowed)
                    const Positioned.fill(child: PerfHudOverlay()),
                ],
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

class AppThemeWrapper extends ConsumerWidget {
  final Widget Function(ThemeData light, ThemeData dark, ThemeMode mode)
  builder;

  const AppThemeWrapper({super.key, required this.builder});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Select only what ThemeData needs.
    final themeMode = ref.watch(themeProvider.select((s) => s.themeMode));

    return builder(
      AppTheme.build(Brightness.light),
      AppTheme.build(Brightness.dark),
      themeMode,
    );
  }
}
