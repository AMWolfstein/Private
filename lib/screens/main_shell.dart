import 'dart:async';
import 'dart:io';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/providers/settings_provider.dart';
import 'package:spotiflac_android/providers/playback_notification_provider.dart';
import 'package:spotiflac_android/providers/runtime_profile_provider.dart';
import 'package:spotiflac_android/screens/home_tab.dart';
import 'package:spotiflac_android/screens/queue_tab.dart';
import 'package:spotiflac_android/screens/settings/settings_tab.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/services/shell_navigation_service.dart';
import 'package:spotiflac_android/services/music_playback_deck.dart';
import 'package:spotiflac_android/services/listening_statistics.dart';
import 'package:spotiflac_android/services/notification_service.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';
import 'package:spotiflac_android/widgets/animation_utils.dart';
import 'package:spotiflac_android/widgets/mini_player.dart';
import 'package:spotiflac_android/widgets/lazy_tab_view.dart';
import 'package:spotiflac_android/widgets/mornye_backdrop_groups.dart';
import 'package:spotiflac_android/widgets/mornye_bottom_bar.dart';
import 'package:spotiflac_android/widgets/mornye_chrome.dart';
import 'package:spotiflac_android/widgets/mornye_chrome_adaptivity.dart';
import 'package:spotiflac_android/widgets/mornye_floating_header.dart';
import 'package:spotiflac_android/theme/mornye_theme.dart';
import 'package:spotiflac_android/widgets/selection_bottom_bar.dart';
import 'package:spotiflac_android/utils/logger.dart';
import 'package:spotiflac_android/utils/adaptive_layout.dart';

final _log = AppLogger('MainShell');

class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  int _currentIndex = 0;
  final _homeFeedScrollController = ScrollController();
  final _mornyeChrome = MornyeChromeController();
  final _chromeAdaptivity = MornyeChromeAdaptivity();
  // Preserves the tab view element (and its kept-alive tabs) when the body
  // structure swaps between rail and bottom-bar layouts on rotation.
  final GlobalKey _pageViewKey = GlobalKey();
  bool _initialSafRepairComplete = false;
  bool _safRepairDialogVisible = false;
  bool _usbVolumeWarningShown = false;
  DateTime? _lastBackPress;
  final GlobalKey<NavigatorState> _homeTabNavigatorKey =
      ShellNavigationService.homeTabNavigatorKey;
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
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _repairSafAccessIfNeeded(
        knownLost: ref.read(initialSafAccessLostProvider),
      );
      _initialSafRepairComplete = true;
      if (!mounted) return;
      unawaited(ref.read(musicPlayerRuntimeProvider).restoreSession());
      await _checkSafMigration();
    });
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
    if (state == AppLifecycleState.resumed && _initialSafRepairComplete) {
      unawaited(_repairSafAccessIfNeeded());
    } else if (state == AppLifecycleState.paused) {
      unawaited(
        ref.read(musicPlayerRuntimeProvider).handler?.persistCurrentSession(),
      );
    }
  }

  Future<void> _repairSafAccessIfNeeded({bool knownLost = false}) async {
    if (!Platform.isAndroid || _safRepairDialogVisible) return;

    var accessLost = knownLost;
    if (!accessLost) {
      final settings = ref.read(settingsProvider);
      if (settings.storageMode != 'saf' || settings.downloadTreeUri.isEmpty) {
        return;
      }
      accessLost = !await PlatformBridge.isSafTreeAccessible(
        settings.downloadTreeUri,
      );
    }
    if (!accessLost || !mounted) return;

    _safRepairDialogVisible = true;
    try {
      await showAppDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          var isPickingFolder = false;
          return StatefulBuilder(
            builder: (context, setDialogState) {
              return PopScope(
                canPop: false,
                child: AppAlertDialog(
                  icon: Icon(
                    Icons.folder_off_outlined,
                    color: Theme.of(context).colorScheme.error,
                  ),
                  title: Text(context.l10n.downloadFolderAccessLostTitle),
                  content: Text(context.l10n.downloadFolderAccessLostSubtitle),
                  actions: [
                    AppDialogAction(
                      onPressed: isPickingFolder
                          ? null
                          : () {
                              final notifier = ref.read(
                                settingsProvider.notifier,
                              );
                              notifier.setStorageMode('app');
                              notifier.setDownloadTreeUri('');
                              notifier.setDownloadDirectory('');
                              Navigator.of(dialogContext).pop();
                            },
                      child: Text(context.l10n.storageAutomaticFolder),
                    ),
                    AppDialogAction(
                      filled: true,
                      onPressed: isPickingFolder
                          ? null
                          : () async {
                              setDialogState(() => isPickingFolder = true);
                              try {
                                final result =
                                    await PlatformBridge.pickSafTree();
                                if (result == null) return;
                                final treeUri =
                                    result['tree_uri'] as String? ?? '';
                                final displayName =
                                    result['display_name'] as String? ?? '';
                                if (treeUri.isEmpty) return;

                                final notifier = ref.read(
                                  settingsProvider.notifier,
                                );
                                notifier.setStorageMode('saf');
                                notifier.setDownloadTreeUri(
                                  treeUri,
                                  displayName: displayName.isNotEmpty
                                      ? displayName
                                      : treeUri,
                                );
                                if (dialogContext.mounted) {
                                  Navigator.of(dialogContext).pop();
                                }
                              } catch (e) {
                                _log.w(
                                  'Failed to repair SAF access from startup: $e',
                                );
                                if (context.mounted) {
                                  showCannotOpenFileSnackBar(context, e);
                                }
                              } finally {
                                if (dialogContext.mounted) {
                                  setDialogState(() => isPickingFolder = false);
                                }
                              }
                            },
                      child: isPickingFolder
                          ? const SizedBox.square(
                              dimension: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(context.l10n.downloadFolderReselect),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
    } finally {
      _safRepairDialogVisible = false;
    }
  }

  static const _safMigrationShownKey = 'saf_migration_prompt_shown';

  Future<void> _checkSafMigration() async {
    if (!Platform.isAndroid) return;

    final settings = ref.read(settingsProvider);
    if (settings.storageMode == 'saf') return;
    if (settings.downloadDirectory.isEmpty) return;

    final deviceInfo = DeviceInfoPlugin();
    final androidInfo = await deviceInfo.androidInfo;
    if (androidInfo.version.sdkInt < 29) return;

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_safMigrationShownKey) == true) return;
    await prefs.setBool(_safMigrationShownKey, true);

    if (!mounted) return;

    final colorScheme = Theme.of(context).colorScheme;

    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AppAlertDialog(
        icon: Icon(
          Icons.folder_special_outlined,
          size: 32,
          color: colorScheme.primary,
        ),
        title: Text(context.l10n.safMigrationTitle),
        content: ConstrainedBox(
          // Keeps the text column readable on tablets/landscape.
          constraints: const BoxConstraints(maxWidth: 400),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(context.l10n.safMigrationMessage1),
              const SizedBox(height: 12),
              Text(context.l10n.safMigrationMessage2),
            ],
          ),
        ),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(ctx),
            child: Text(context.l10n.updateLater),
          ),
          AppDialogAction(
            filled: true,
            onPressed: () async {
              Navigator.pop(ctx);
              final result = await PlatformBridge.pickSafTree();
              if (result != null) {
                final treeUri = result['tree_uri'] as String? ?? '';
                final displayName = result['display_name'] as String? ?? '';
                if (treeUri.isNotEmpty) {
                  ref
                      .read(settingsProvider.notifier)
                      .setDownloadTreeUri(
                        treeUri,
                        displayName: displayName.isNotEmpty
                            ? displayName
                            : treeUri,
                      );
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.l10n.safMigrationSuccess)),
                    );
                  }
                }
              }
            },
            child: Text(context.l10n.setupSelectFolder),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    usbAudioStatus.removeListener(_onUsbAudioStatusChanged);
    ShellNavigationService.unregisterTabSelectionHandler(this);
    _homeFeedScrollController.dispose();
    _mornyeChrome.dispose();
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
      ShellTab.home => 0,
      ShellTab.search => 2,
      ShellTab.library => 1,
      ShellTab.settings => 2,
    };
    _onNavTap(index, resetHome: tab != ShellTab.search);
  }

  bool _settingsPageOpen = false;

  Future<void> _openProfileSettings() async {
    if (_settingsPageOpen) return;
    _settingsPageOpen = true;
    FocusManager.instance.primaryFocus?.unfocus();
    try {
      await Navigator.of(context).push(
        slidePageRoute<void>(
          page: const Scaffold(body: SettingsTab(asPage: true)),
        ),
      );
    } finally {
      _settingsPageOpen = false;
    }
  }

  void _onNavTap(int index, {bool resetHome = true}) {
    _mornyeChrome.expand();
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
        showSearchTab: context.isMornye,
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

    final isSearchTab = _currentIndex == (2);

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
      unawaited(PlatformBridge.exitApp());
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
    if (index == 0) return _homeTabNavigatorKey.currentState;
    if (index == 1) return _libraryTabNavigatorKey.currentState;
    if (index == 2) {
      return _searchTabNavigatorKey.currentState;
    }
    return null;
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
      showSearchTab: context.isMornye,
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
        icon: const MornyeNavigationIcon(
          icon: CupertinoIcons.square_stack_fill,
          badgeCount: 0,
        ),
        selectedIcon: const MornyeNavigationIcon(
          icon: CupertinoIcons.square_stack_fill,
          badgeCount: 0,
        ),
        label: l10n.navLibrary,
      ),
      ...[],
      NavigationDestination(
        icon: const Icon(CupertinoIcons.search),
        label: l10n.mornyeSearch,
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
              return _mornyeChrome.handleScroll(notification);
            }
            return false;
          },
          child: child,
        );

    final pageView = KeyedSubtree(
      key: _pageViewKey,
      child: LazyTabView(
        index: selectedDestination,
        preloadKeys: {const ValueKey('tab-search')},
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
        !useNavigationRail && mornyeLiquidChromeEnabled(context, ref);
    // The developer A/B switch drops only the sampler; the bar keeps its
    // clear adaptive fill and the theme's palette.
    final sampleChrome =
        adaptiveChrome && !ref.watch(mornyeBarSamplerDisabledProvider);

    final shell = SelectionOverlayHost(
      child: BackButtonListener(
        onBackButtonPressed: () async {
          await _handleBackPress();
          return true;
        },
        // Headers in the tab pages and the bottom bar share two backdrop
        // reads between them; see MornyeBackdropGroup.
        child: MornyeBackdropGroups(
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
                : MornyeChromeBackdrop(
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
                      final brightness = mornyeChromeBrightness(
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
                            : MornyeTheme.fromContext(
                                context,
                                brightness: brightness,
                                chromeSurface: pageOverride == null
                                    ? null
                                    : ShellNavigationService
                                          .chromeSurface
                                          .value,
                              ),
                        child: MornyeAdaptiveChromeScope(
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
                              valueListenable: _mornyeChrome,
                              builder: (context, collapsed, _) =>
                                  MornyeBottomBar(
                                    collapsed: canMinimizeChrome && collapsed,
                                    destinations: destinations,
                                    selectedIndex: selectedDestination,
                                    onSelected: _onNavTap,
                                    onHome: () => _onNavTap(0),
                                    onSearch:
                                        ShellNavigationService.requestSearch,
                                    blurEnabled: ref.watch(
                                      mornyeBlurEnabledProvider,
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
    return const QueueTab();
  }
}

class _KeepAliveTabPage extends StatefulWidget {
  final Widget child;

  const _KeepAliveTabPage({required this.child});

  @override
  State<_KeepAliveTabPage> createState() => _KeepAliveTabPageState();
}

class _KeepAliveTabPageState extends State<_KeepAliveTabPage>
    with AutomaticKeepAliveClientMixin<_KeepAliveTabPage> {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
