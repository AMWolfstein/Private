part of 'main_shell.dart';

extension _MainShellStatePart1 on _MainShellState {
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
    _appChrome.expand();
    if (index == 0 && resetHome) {
      _resetHomeToMain(scrollToTop: _currentIndex == 0);
    }
    if (index == 0 && _currentIndex == 0) {
      return;
    }

    if (_currentIndex != index) {
      HapticFeedback.selectionClick();
      _rebuild(() => _currentIndex = index);
      ShellNavigationService.syncState(
        currentTabIndex: _currentIndex,
        showSearchTab: context.isAppTheme,
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
}
