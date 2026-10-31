import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/playback/music_player_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/providers/playback/playback_notification_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/screens/home/home_tab.dart';
import 'package:sistrum/screens/stats/listening_statistics_screen.dart';
import 'package:sistrum/screens/shell/main_shell_tabs.dart';
import 'package:sistrum/screens/settings/settings_tab.dart';
import 'package:sistrum/services/native/native_device.dart';
import 'package:sistrum/core/navigation/shell_navigation.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/services/platform/notification_service.dart';
import 'package:sistrum/services/platform/update_checker.dart';
import 'package:sistrum/widgets/sheets/update_dialog.dart';
import 'package:sistrum/widgets/animation/animation_utils.dart';
import 'package:sistrum/widgets/player/mini_player.dart';
import 'package:sistrum/widgets/shell/lazy_tab_view.dart';
import 'package:sistrum/widgets/glass/chrome/app_backdrop_groups.dart';
import 'package:sistrum/widgets/shell/app_bottom_bar.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_controls.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome_adaptivity.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';

part 'main_shell_navigation.dart';

class MainShell extends ConsumerStatefulWidget {
  /// Builds the Search tab in the background after the first frame. Tests turn
  /// this off so the idle preload does not build every tab.
  const MainShell({super.key, this.preloadTabs = true});

  final bool preloadTabs;

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = 0;
  final _homeFeedScrollController = ScrollController();
  final _appChrome = AppChromeController();
  final _chromeAdaptivity = AppChromeAdaptivity();
  // Preserves the tab view element (and its kept-alive tabs) when the body
  // structure swaps between rail and bottom-bar layouts on rotation.
  final GlobalKey _pageViewKey = GlobalKey();
  bool _usbVolumeWarningShown = false;
  DateTime? _lastBackPress;
  final GlobalKey<NavigatorState> _homeTabNavigatorKey =
      ShellNavigationService.homeTabNavigatorKey;
  final GlobalKey<NavigatorState> _statsTabNavigatorKey =
      ShellNavigationService.statsTabNavigatorKey;
  final GlobalKey<NavigatorState> _libraryTabNavigatorKey =
      ShellNavigationService.libraryTabNavigatorKey;
  final GlobalKey<NavigatorState> _searchTabNavigatorKey =
      ShellNavigationService.searchTabNavigatorKey;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    NotificationService().updateStrings(l10n);
    final playback = ref.read(musicPlayerRuntimeProvider);
    playback.updateStrings(
      unknownTitle: l10n.unknownTitle,
      unknownArtist: l10n.unknownArtist,
    );
    final settings = ref.read(settingsProvider);
    playback.configure(settings);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    usbAudioStatus.addListener(_onUsbAudioStatusChanged);
    ShellNavigationService.registerTabSelectionHandler(
      owner: this,
      handler: _onShellTabRequested,
    );
    ShellNavigationService.syncState(currentTabIndex: _currentIndex);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(ref.read(musicPlayerRuntimeProvider).restoreSession());
      unawaited(_checkForUpdates());
    });
  }

  bool _hasCheckedUpdate = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      unawaited(
        ref.read(musicPlayerRuntimeProvider).handler?.persistCurrentSession(),
      );
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    usbAudioStatus.removeListener(_onUsbAudioStatusChanged);
    ShellNavigationService.unregisterTabSelectionHandler(this);
    _homeFeedScrollController.dispose();
    _appChrome.dispose();
    _chromeAdaptivity.dispose();
    super.dispose();
  }

  bool _settingsPageOpen = false;

  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    ref.watch(
      playbackNotificationProvider((
        favorite: context.l10n.trackOptionAddToLoved,
        unfavorite: context.l10n.trackOptionRemoveFromLoved,
        shuffleOn: context.l10n.nowPlayingShuffleOn,
        shuffleOff: context.l10n.nowPlayingPlayInOrder,
      )),
    );
    ref.listen(settingsProvider, (_, settings) {
      ref.read(musicPlayerRuntimeProvider).configure(settings);
    });
    final heroAnimationsEnabled = ref.watch(
      settingsProvider.select((s) => s.heroAnimationsEnabled),
    );
    ShellNavigationService.syncState(
      currentTabIndex: _currentIndex,
      showSearchTab: context.isAppTheme,
    );

    final tabs = <Widget>[
      TabNavigator(
        key: const ValueKey('tab-home'),
        navigatorKey: _homeTabNavigatorKey,
        heroAnimationsEnabled: heroAnimationsEnabled,
        child: Builder(
          builder: (context) => HomeTab(
            scrollController: _homeFeedScrollController,
            mode: HomeTabMode.browse,
          ),
        ),
      ),
      TabNavigator(
        key: const ValueKey('tab-stats'),
        navigatorKey: _statsTabNavigatorKey,
        heroAnimationsEnabled: heroAnimationsEnabled,
        child: const ListeningStatisticsScreen(asTab: true),
      ),
      TabNavigator(
        key: const ValueKey('tab-library'),
        navigatorKey: _libraryTabNavigatorKey,
        heroAnimationsEnabled: heroAnimationsEnabled,
        child: const LibraryTabRoot(),
      ),
      ...[],
      TabNavigator(
        key: const ValueKey('tab-search'),
        navigatorKey: _searchTabNavigatorKey,
        heroAnimationsEnabled: heroAnimationsEnabled,
        child: const HomeTab(mode: HomeTabMode.search),
      ),
    ];

    final l10n = context.l10n;
    final destinations = <NavigationDestination>[
      NavigationDestination(
        icon: Icon(CupertinoIcons.house_fill),
        selectedIcon: const Icon(CupertinoIcons.house_fill),
        label: l10n.navHome,
      ),
      NavigationDestination(
        icon: const Icon(CupertinoIcons.chart_bar_alt_fill),
        selectedIcon: const Icon(CupertinoIcons.chart_bar_alt_fill),
        label: l10n.listeningStats,
      ),
      NavigationDestination(
        icon: const AppNavigationIcon(
          icon: CupertinoIcons.square_stack_fill,
          badgeCount: 0,
        ),
        selectedIcon: const AppNavigationIcon(
          icon: CupertinoIcons.square_stack_fill,
          badgeCount: 0,
        ),
        label: l10n.navLibrary,
      ),
      ...[],
      NavigationDestination(
        icon: const Icon(CupertinoIcons.search),
        label: l10n.appSearch,
      ),
    ];

    final maxIndex = tabs.length - 1;
    final selectedDestination = _currentIndex.clamp(0, maxIndex);
    if (_currentIndex > maxIndex) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _currentIndex = maxIndex);
        }
      });
    }

    final screenSize = MediaQuery.sizeOf(context);

    // Tablets remain touch-first in both orientations. Reserving the rail for
    // desktop-width windows keeps all primary destinations at the reachable
    // bottom edge on iPad and large Android tablets.
    final useNavigationRail = useNavigationRailForWidth(screenSize.width);
    final canMinimizeChrome =
        !useNavigationRail &&
        MediaQuery.viewInsetsOf(context).bottom == 0 &&
        MediaQuery.textScalerOf(context).scale(15) <= 20;

    Widget observeScroll(Widget child, int index) =>
        NotificationListener<ScrollNotification>(
          onNotification: (notification) {
            if (canMinimizeChrome && index == _currentIndex) {
              return _appChrome.handleScroll(notification);
            }
            return false;
          },
          child: child,
        );

    final pageView = KeyedSubtree(
      key: _pageViewKey,
      child: LazyTabView(
        index: selectedDestination,
        preloadKeys: widget.preloadTabs
            ? {const ValueKey('tab-search')}
            : const {},
        children: [
          for (var index = 0; index < tabs.length; index++)
            KeyedSubtree(
              key: tabs[index].key,
              child: observeScroll(tabs[index], index),
            ),
        ],
      ),
    );

    // The bar's palette follows the page behind it only where liquid chrome
    // is allowed; elsewhere it keeps the theme and its readable strong tint.
    final adaptiveChrome =
        !useNavigationRail && appLiquidChromeEnabled(context, ref);
    // The developer A/B switch drops only the sampler; the bar keeps its
    // clear adaptive fill and the theme's palette.
    final sampleChrome =
        adaptiveChrome && !ref.watch(appBarSamplerDisabledProvider);

    final shell = SelectionOverlayHost(
      child: BackButtonListener(
        onBackButtonPressed: () async {
          await _handleBackPress();
          return true;
        },
        // Header controls in the tab pages and the bottom bar share one
        // backdrop read; see AppChromeBatch.
        child: AppChromeBatch(
          child: Scaffold(
            extendBody: true,
            // The tab view keeps one element across the rail<->bar structure
            // swap via _pageViewKey so rotation doesn't remount tab navigators.
            body: useNavigationRail
                ? Row(
                    children: [
                      SafeArea(
                        right: false,
                        bottom: false,
                        // The rail needs ~300dp of height for four labeled
                        // destinations; on short viewports (landscape phone with
                        // the mini player showing) it must scroll, not overflow.
                        child: LayoutBuilder(
                          builder: (context, constraints) =>
                              SingleChildScrollView(
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: IntrinsicHeight(
                                    child: NavigationRail(
                                      selectedIndex: selectedDestination,
                                      onDestinationSelected: _onNavTap,
                                      labelType: NavigationRailLabelType.all,
                                      backgroundColor: Theme.of(
                                        context,
                                      ).colorScheme.surfaceContainer,
                                      destinations: [
                                        for (final destination in destinations)
                                          NavigationRailDestination(
                                            icon: destination.icon,
                                            selectedIcon:
                                                destination.selectedIcon,
                                            label: Text(destination.label),
                                          ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                        ),
                      ),
                      const VerticalDivider(width: 1),
                      Expanded(child: pageView),
                    ],
                  )
                : AppChromeBackdrop(
                    adaptivity: _chromeAdaptivity,
                    enabled: sampleChrome,
                    child: pageView,
                  ),
            bottomNavigationBar: Builder(
              builder: (context) {
                {
                  return ListenableBuilder(
                    listenable: Listenable.merge([
                      ShellNavigationService.chromeBrightness,
                      ShellNavigationService.chromeSurface,
                      _chromeAdaptivity.link,
                    ]),
                    builder: (context, child) {
                      final pageOverride =
                          ShellNavigationService.chromeBrightness.value;
                      final brightness = appChromeBrightness(
                        pageOverride: pageOverride,
                        sampled: sampleChrome
                            ? _chromeAdaptivity.link.value
                            : null,
                      );
                      final theme = Theme.of(context);
                      return AnimatedTheme(
                        duration: MediaQuery.disableAnimationsOf(context)
                            ? Duration.zero
                            : const Duration(milliseconds: 300),
                        data:
                            brightness == null ||
                                (pageOverride == null &&
                                    brightness == theme.brightness)
                            ? theme
                            : AppTheme.fromContext(
                                context,
                                brightness: brightness,
                                chromeSurface: pageOverride == null
                                    ? null
                                    : ShellNavigationService
                                          .chromeSurface
                                          .value,
                              ),
                        child: AppAdaptiveChromeScope(
                          active: adaptiveChrome,
                          child: child!,
                        ),
                      );
                    },
                    child: SafeArea(
                      top: false,
                      minimum: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                      child: useNavigationRail
                          ? const MiniPlayer()
                          : ValueListenableBuilder<bool>(
                              valueListenable: _appChrome,
                              builder: (context, collapsed, _) => AppBottomBar(
                                collapsed: canMinimizeChrome && collapsed,
                                destinations: destinations,
                                selectedIndex: selectedDestination,
                                onSelected: _onNavTap,
                                onHome: () => _onNavTap(0),
                                onSearch: ShellNavigationService.requestSearch,
                                blurEnabled: ref.watch(appBlurEnabledProvider),
                              ),
                            ),
                    ),
                  );
                }
              },
            ),
          ),
        ),
      ),
    );
    return shell;
  }
}
