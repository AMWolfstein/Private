import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/music_player_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/playback_notification_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/screens/home/home_tab.dart';
import 'package:sistrum/screens/listening_statistics_screen.dart';
import 'package:sistrum/screens/library/library_section_tab.dart';
import 'package:sistrum/screens/settings/settings_tab.dart';
import 'package:sistrum/services/native/native_device.dart';
import 'package:sistrum/navigation/shell_navigation.dart';
import 'package:sistrum/services/playback/music_playback_deck.dart';
import 'package:sistrum/services/playback/listening_statistics.dart';
import 'package:sistrum/services/notification_service.dart';
import 'package:sistrum/services/update_checker.dart';
import 'package:sistrum/widgets/sheets/update_dialog.dart';
import 'package:sistrum/widgets/animation_utils.dart';
import 'package:sistrum/widgets/player/mini_player.dart';
import 'package:sistrum/widgets/shell/lazy_tab_view.dart';
import 'package:sistrum/widgets/glass/sistrum_backdrop_groups.dart';
import 'package:sistrum/widgets/shell/sistrum_bottom_bar.dart';
import 'package:sistrum/widgets/glass/sistrum_chrome.dart';
import 'package:sistrum/widgets/glass/sistrum_chrome_adaptivity.dart';
import 'package:sistrum/widgets/glass/sistrum_floating_header.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/widgets/selection/selection_bottom_bar.dart';
import 'package:sistrum/utils/adaptive_layout.dart';

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
  final _sistrumChrome = SistrumChromeController();
  final _chromeAdaptivity = SistrumChromeAdaptivity();
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
    listeningRecorder.setEnabled(settings.listeningStatisticsEnabled);
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

  Future<void> _checkForUpdates() async {
    if (_hasCheckedUpdate) return;
    _hasCheckedUpdate = true;

    final settings = ref.read(settingsProvider);

    // The check runs even when the user disabled update prompts: versions
    // that fall forceUpdateThreshold stable releases behind must update, and
    // that enforcement cannot be opted out of.
    final UpdateInfo? updateInfo;
    try {
      updateInfo = await UpdateChecker().checkForUpdate(
        channel: settings.updateChannel,
      );
    } on UpdateCheckException {
      // A background check that cannot reach the release list is silent.
      return;
    }
    if (updateInfo == null || !mounted) return;

    final forced =
        updateInfo.releasesBehind >= UpdateChecker.forceUpdateThreshold;
    if (!forced && !settings.checkForUpdates) return;

    unawaited(
      showUpdateDialog(
        context,
        updateInfo: updateInfo,
        forced: forced,
        onDisableUpdates: () {
          ref.read(settingsProvider.notifier).setCheckForUpdates(false);
        },
      ),
    );
  }

  void _onUsbAudioStatusChanged() {
    if (usbAudioStatus.value.reason == 'active') {
      _usbVolumeWarningShown = false;
    }
    if (usbAudioStatus.value.reason != 'volume_unavailable' ||
        _usbVolumeWarningShown) {
      return;
    }
    _usbVolumeWarningShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || usbAudioStatus.value.reason != 'volume_unavailable') {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.usbVolumeUnavailable),
          duration: const Duration(seconds: 8),
        ),
      );
    });
  }

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
    _sistrumChrome.dispose();
    _chromeAdaptivity.dispose();
    super.dispose();
  }

  void _resetHomeToMain({bool scrollToTop = false}) {
    if (scrollToTop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_homeFeedScrollController.hasClients) return;
        if (MediaQuery.disableAnimationsOf(context)) {
          _homeFeedScrollController.jumpTo(0);
        } else {
          unawaited(
            _homeFeedScrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
            ),
          );
        }
      });
    }
    final homeNavigator = _navigatorForTab(0);
    homeNavigator?.popUntil((route) => route.isFirst);
    FocusManager.instance.primaryFocus?.unfocus();
  }

  void _onShellTabRequested(ShellTab tab) {
    if (tab == ShellTab.settings) {
      unawaited(_openProfileSettings());
      return;
    }
    final index = switch (tab) {
      ShellTab.home => ShellNavigationService.homeTabIndex,
      ShellTab.stats => ShellNavigationService.statsTabIndex,
      ShellTab.library => ShellNavigationService.libraryTabIndex,
      ShellTab.search => ShellNavigationService.searchTabIndex,
      ShellTab.settings => ShellNavigationService.searchTabIndex,
    };
    _onNavTap(index, resetHome: tab != ShellTab.search);
  }

  bool _settingsPageOpen = false;

  Future<void> _openProfileSettings() async {
    if (_settingsPageOpen) return;
    _settingsPageOpen = true;
    ShellNavigationService.settingsOpen.value = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await Navigator.of(context).push(
        slidePageRoute<void>(
          page: const Scaffold(body: SettingsTab(asPage: true)),
        ),
      );
    } finally {
      _settingsPageOpen = false;
      ShellNavigationService.settingsOpen.value = false;
    }
  }

  void _onNavTap(int index, {bool resetHome = true}) {
    _sistrumChrome.expand();
    if (index == 0 && resetHome) {
      _resetHomeToMain(scrollToTop: _currentIndex == 0);
    }
    if (index == 0 && _currentIndex == 0) {
      return;
    }

    if (_currentIndex != index) {
      HapticFeedback.selectionClick();
      setState(() => _currentIndex = index);
      ShellNavigationService.syncState(
        currentTabIndex: _currentIndex,
        showSearchTab: context.isSistrum,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      // Jump directly when skipping intermediate tabs to avoid
      // sliding through them. For those jumps, keep a short fade-in
      // so the transition still feels intentional.
    }
  }

  Future<void> _handleBackPress() async {
    final rootNavigator = Navigator.of(context, rootNavigator: true);
    final handledByRootNavigator = await rootNavigator.maybePop();
    if (handledByRootNavigator) {
      _lastBackPress = null;
      return;
    }

    final currentNavigator = _navigatorForTab(_currentIndex);
    final handledByCurrentNavigator =
        await currentNavigator?.maybePop() ?? false;
    if (handledByCurrentNavigator) {
      _lastBackPress = null;
      return;
    }

    if (!mounted) return;

    final isSearchTab = _currentIndex == ShellNavigationService.searchTabIndex;

    final isKeyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;

    if (isSearchTab && isKeyboardVisible) {
      FocusManager.instance.primaryFocus?.unfocus();
      _lastBackPress = null;
      return;
    }

    if (_currentIndex != 0) {
      _onNavTap(0);
      _lastBackPress = null;
      return;
    }

    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) < const Duration(seconds: 2)) {
      unawaited(NativeDevice.exitApp());
    } else {
      _lastBackPress = now;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.pressBackAgainToExit),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  NavigatorState? _navigatorForTab(int index) {
    return switch (index) {
      ShellNavigationService.homeTabIndex => _homeTabNavigatorKey.currentState,
      ShellNavigationService.statsTabIndex =>
        _statsTabNavigatorKey.currentState,
      ShellNavigationService.libraryTabIndex =>
        _libraryTabNavigatorKey.currentState,
      ShellNavigationService.searchTabIndex =>
        _searchTabNavigatorKey.currentState,
      _ => null,
    };
  }

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
    ref.listen(
      settingsProvider.select((s) => s.listeningStatisticsEnabled),
      (_, enabled) => listeningRecorder.setEnabled(enabled),
    );
    final heroAnimationsEnabled = ref.watch(
      settingsProvider.select((s) => s.heroAnimationsEnabled),
    );
    ShellNavigationService.syncState(
      currentTabIndex: _currentIndex,
      showSearchTab: context.isSistrum,
    );

    final tabs = <Widget>[
      _TabNavigator(
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
      _TabNavigator(
        key: const ValueKey('tab-stats'),
        navigatorKey: _statsTabNavigatorKey,
        heroAnimationsEnabled: heroAnimationsEnabled,
        child: const ListeningStatisticsScreen(asTab: true),
      ),
      _TabNavigator(
        key: const ValueKey('tab-library'),
        navigatorKey: _libraryTabNavigatorKey,
        heroAnimationsEnabled: heroAnimationsEnabled,
        child: const _LibraryTabRoot(),
      ),
      ...[],
      _TabNavigator(
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
        icon: const SistrumNavigationIcon(
          icon: CupertinoIcons.square_stack_fill,
          badgeCount: 0,
        ),
        selectedIcon: const SistrumNavigationIcon(
          icon: CupertinoIcons.square_stack_fill,
          badgeCount: 0,
        ),
        label: l10n.navLibrary,
      ),
      ...[],
      NavigationDestination(
        icon: const Icon(CupertinoIcons.search),
        label: l10n.sistrumSearch,
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
              return _sistrumChrome.handleScroll(notification);
            }
            return false;
          },
          child: child,
        );

    final pageView = KeyedSubtree(
      key: _pageViewKey,
      child: LazyTabView(
        index: selectedDestination,
        preloadKeys: widget.preloadTabs ? {const ValueKey('tab-search')} : const {},
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
        !useNavigationRail && sistrumLiquidChromeEnabled(context, ref);
    // The developer A/B switch drops only the sampler; the bar keeps its
    // clear adaptive fill and the theme's palette.
    final sampleChrome =
        adaptiveChrome && !ref.watch(sistrumBarSamplerDisabledProvider);

    final shell = SelectionOverlayHost(
      child: BackButtonListener(
        onBackButtonPressed: () async {
          await _handleBackPress();
          return true;
        },
        // Header controls in the tab pages and the bottom bar share one
        // backdrop read; see SistrumChromeBatch.
        child: SistrumChromeBatch(
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
                : SistrumChromeBackdrop(
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
                      final brightness = sistrumChromeBrightness(
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
                            : SistrumTheme.fromContext(
                                context,
                                brightness: brightness,
                                chromeSurface: pageOverride == null
                                    ? null
                                    : ShellNavigationService
                                          .chromeSurface
                                          .value,
                              ),
                        child: SistrumAdaptiveChromeScope(
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
                              valueListenable: _sistrumChrome,
                              builder: (context, collapsed, _) =>
                                  SistrumBottomBar(
                                    collapsed: canMinimizeChrome && collapsed,
                                    destinations: destinations,
                                    selectedIndex: selectedDestination,
                                    onSelected: _onNavTap,
                                    onHome: () => _onNavTap(0),
                                    onSearch:
                                        ShellNavigationService.requestSearch,
                                    blurEnabled: ref.watch(
                                      sistrumBlurEnabledProvider,
                                    ),
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

class _TabNavigator extends StatefulWidget {
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;
  final bool heroAnimationsEnabled;

  const _TabNavigator({
    super.key,
    required this.navigatorKey,
    required this.child,
    required this.heroAnimationsEnabled,
  });

  @override
  State<_TabNavigator> createState() => _TabNavigatorState();
}

class _TabNavigatorState extends State<_TabNavigator> {
  late final ShellChromeObserver _chromeObserver = ShellChromeObserver(
    widget.navigatorKey,
  );
  // Nested navigators get no HeroController from MaterialApp; without one,
  // Hero widgets on routes pushed inside a tab never fly.
  final HeroController _heroController =
      MaterialApp.createMaterialHeroController();

  @override
  void dispose() {
    _chromeObserver.detach();
    _heroController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      key: widget.navigatorKey,
      observers: [
        _chromeObserver,
        if (widget.heroAnimationsEnabled) _heroController,
      ],
      onGenerateInitialRoutes: (_, _) => [
        MaterialPageRoute<void>(builder: (_) => widget.child),
      ],
    );
  }
}

class _LibraryTabRoot extends ConsumerWidget {
  const _LibraryTabRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const LibrarySectionTab();
  }
}
