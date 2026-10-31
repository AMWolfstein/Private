part of 'setup_screen.dart';

extension _SetupScreenStatePart1 on _SetupScreenState {
  int get _storageStep => 2 + localGuidePageCount;
  int get _totalSteps => _storageStep + (_androidSdkVersion >= 33 ? 2 : 1);
  Future<void> _initDeviceInfo() async {
    try {
      await ref.read(settingsProvider.notifier).ensureLoaded();
      if (_platform == TargetPlatform.android) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        _androidSdkVersion = androidInfo.version.sdkInt;
      }
      final prefs = await _prefs;
      if (!mounted) return;
      _selectedLocale = ref.read(settingsProvider).locale;
      final saved = prefs.getString(_SetupScreenState._progressKey);
      if (saved != null) {
        try {
          final draft = jsonDecode(saved) as Map<String, dynamic>;
          var savedStep = (draft['step'] as int?) ?? 0;
          final version = draft['version'];
          // Version 1 drafts used 2/3 for permissions and ended in a
          // download-folder step.
          if (version != 2 && version != 3 && savedStep >= 2) {
            savedStep += _SetupScreenState._fivePageGuideCount;
          }
          // Version 3 drafts (English-only build) had no language step at 1.
          if (version == 3 && savedStep >= 1) savedStep += 1;
          // Drafts from before version 4 counted the guide as five pages:
          // steps 2-6 were its tips and later steps came after them.
          if (version != 4) {
            if (savedStep >= 2 && savedStep <= 6) {
              savedStep = 2;
            } else if (savedStep >= 7) {
              savedStep -=
                  _SetupScreenState._fivePageGuideCount - localGuidePageCount;
            }
          }
          _currentStep = savedStep.clamp(0, _totalSteps - 1);
          _notificationPermissionSkipped = draft['skipNotifications'] == true;
          _storageSkipped = draft['skipStorage'] == true;
        } catch (error) {
          await prefs.remove(_SetupScreenState._progressKey);
          _log.w('Discarding malformed setup progress: $error');
        }
      }
      await _checkInitialPermissions();
    } catch (e, stack) {
      _log.e('Failed to restore setup progress', e, stack);
    } finally {
      if (mounted) {
        _pageController = PageController(initialPage: _currentStep);
        _rebuild(() => _initializing = false);
      }
    }
  }

  Future<void> _refreshAfterResume() async {
    await _initialization;
    if (!mounted) return;
    try {
      await _checkInitialPermissions();
    } catch (e, stack) {
      _log.e('Failed to refresh setup permissions', e, stack);
    }
  }

  Future<void> _saveProgress({int? step}) async {
    final draft = jsonEncode({
      'step': step ?? _currentStep,
      'version': 4,
      'skipNotifications': _notificationPermissionSkipped,
      'skipStorage': _storageSkipped,
    });
    if (!await (await _prefs).setString(
      _SetupScreenState._progressKey,
      draft,
    )) {
      throw StateError('Could not save setup progress');
    }
  }

  Future<void> _checkInitialPermissions() async {
    if (_platform == TargetPlatform.android) {
      bool storageGranted = false;

      if (_androidSdkVersion < 29) {
        // Android 10 and later read music through a scoped SAF folder, which
        // the storage step asks for instead of a broad permission.
        final storageStatus = await Permission.storage.status;
        storageGranted = storageStatus.isGranted;
      }

      PermissionStatus notificationStatus = PermissionStatus.granted;
      if (_androidSdkVersion >= 33) {
        notificationStatus = await Permission.notification.status;
      }

      if (mounted) {
        _rebuild(() {
          _storagePermissionGranted = storageGranted;
          _notificationPermissionGranted = notificationStatus.isGranted;
        });
      }
    } else {
      _rebuild(() {
        _storagePermissionGranted = true;
        _notificationPermissionGranted = true;
      });
    }
  }

  Future<void> _requestStoragePermission() async {
    if (_isLoading) return;
    _rebuild(() => _isLoading = true);
    try {
      await _saveProgress();
      if (!mounted) return;
      if (_platform == TargetPlatform.android && _androidSdkVersion >= 29) {
        // Scoped folder access: the user picks a music folder instead of
        // granting all-files access.
        final added = await selectLibraryFolder(
          ref.read(localLibraryProvider.notifier),
          androidSdkVersion: _androidSdkVersion,
          onFailure: (message) {
            if (mounted) {
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text(message)));
            }
          },
        );
        if (!mounted) return;
        _rebuild(() => _storagePermissionGranted = added);
        return;
      }

      if (_platform == TargetPlatform.android) {
        final permissionStorage = context.l10n.permissionStorage;
        final status = await Permission.storage.request();
        if (!mounted) return;
        _rebuild(() => _storagePermissionGranted = status.isGranted);
        if (status.isPermanentlyDenied) {
          await _showPermissionDeniedDialog(permissionStorage);
          return;
        }
        if (!status.isGranted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(context.l10n.setupPermissionDeniedMessage)),
          );
        }
      } else {
        _rebuild(() => _storagePermissionGranted = true);
      }
    } catch (e, stack) {
      _log.e('Storage access request failed', e, stack);
    } finally {
      if (mounted) _rebuild(() => _isLoading = false);
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (_isLoading) return;
    final permissionNotification = context.l10n.permissionNotification;
    _rebuild(() => _isLoading = true);
    try {
      await _saveProgress();
      if (!mounted) return;
      if (_androidSdkVersion >= 33) {
        final status = await Permission.notification.request();
        if (!mounted) return;
        if (status.isGranted) {
          _rebuild(() => _notificationPermissionGranted = true);
        } else if (status.isPermanentlyDenied) {
          await _showPermissionDeniedDialog(permissionNotification);
        }
      } else {
        _rebuild(() => _notificationPermissionGranted = true);
      }
    } catch (e, stack) {
      _log.e('Failed to request notification permission', e, stack);
    } finally {
      if (mounted) _rebuild(() => _isLoading = false);
    }
  }

  Future<void> _showPermissionDeniedDialog(String permissionType) async {
    await showAppDialog<void>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.setupPermissionRequired(permissionType)),
        content: Text(
          context.l10n.setupPermissionRequiredMessage(permissionType),
        ),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.dialogCancel),
          ),
          AppDialogAction(
            filled: true,
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: Text(context.l10n.setupOpenSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _completeSetup() async {
    if (_isLoading || !_isStepCompleted(_currentStep)) return;
    _rebuild(() => _isLoading = true);

    try {
      await ref.read(settingsProvider.notifier).setFirstLaunchComplete();
      await (await _prefs).remove(_SetupScreenState._progressKey);

      if (mounted) context.go('/');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.snackbarError(context.friendlyError(e))),
          ),
        );
      }
    } finally {
      if (mounted) _rebuild(() => _isLoading = false);
    }
  }

  void _nextPage() {
    bool canProceed = false;
    if (_currentStep == 0) {
      canProceed = true;
    } else {
      canProceed = _isStepCompleted(_currentStep);
    }

    if (canProceed) {
      unawaited(_goToStep(_currentStep + 1));
    }
  }

  void _prevPage() {
    unawaited(_goToStep(_currentStep - 1));
  }

  Future<void> _goToStep(int step) async {
    if (_isLoading) return;
    _rebuild(() => _isLoading = true);
    try {
      await _saveProgress(step: step);
      if (!mounted) return;
      _rebuild(() => _currentStep = step);
      final controller = _pageController;
      if (controller == null) return;
      // Reduced motion turns the slide into a jump.
      if (MediaQuery.disableAnimationsOf(context)) {
        controller.jumpToPage(step);
      } else {
        await controller.animateToPage(
          step,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } catch (e, stack) {
      _log.e('Failed to save setup step', e, stack);
    } finally {
      if (mounted) _rebuild(() => _isLoading = false);
    }
  }

  bool _isStepCompleted(int step) {
    if (step < _storageStep) return true;
    if (step == _storageStep) {
      return _storagePermissionGranted || _storageSkipped;
    }
    return _notificationPermissionGranted || _notificationPermissionSkipped;
  }

  Widget _buildWelcomeStep(ColorScheme colorScheme) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final textScale = MediaQuery.textScalerOf(
          context,
        ).scale(1.0).clamp(1.0, 1.4);
        final logoSize = (shortestSide * 0.24).clamp(80.0, 104.0);
        final titleGap = (shortestSide * 0.06).clamp(16.0, 32.0);
        final subtitleGap = (shortestSide * 0.04).clamp(8.0, 16.0);
        const totalPadding = 48.0 + kSetupHeaderHeight;
        final minContentHeight = constraints.maxHeight > totalPadding
            ? constraints.maxHeight - totalPadding
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + kSetupHeaderHeight,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: minContentHeight,
                maxWidth: 560,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset(
                    'assets/images/logo-transparent.png',
                    width: logoSize,
                    height: logoSize,
                    fit: BoxFit.contain,
                  ),
                  SizedBox(height: titleGap),
                  Text(
                    context.l10n.appName,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      fontSize:
                          (Theme.of(context).textTheme.displaySmall?.fontSize ??
                              36) *
                          (1 + ((textScale - 1) * 0.18)),
                    ),
                  ),
                  SizedBox(height: subtitleGap),
                  Text(
                    context.l10n.setupLocalPlayback,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _onLanguageSelected(String locale) {
    _rebuild(() => _selectedLocale = locale);
    ref.read(settingsProvider.notifier).setLocale(locale);
  }
}
