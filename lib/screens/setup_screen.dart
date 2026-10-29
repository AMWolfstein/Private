import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:go_router/go_router.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/local_guide_pages.dart';
import 'package:sistrum/services/library/library_folder_selection.dart';
import 'package:sistrum/constants/language_choices.dart';
import 'package:sistrum/utils/adaptive_layout.dart';
import 'package:sistrum/widgets/shell/scroll_edge_fade.dart';
import 'package:sistrum/utils/logger.dart';
import 'package:sistrum/providers/local_library_provider.dart';

final _log = AppLogger('SetupScreen');

// Height of the back-button/progress header row above the PageView
// (16 vertical padding * 2 + 48 button).
const _headerHeight = 80.0;

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen>
    with WidgetsBindingObserver {
  static const _progressKey = 'setup_progress_v1';
  final _prefs = SharedPreferences.getInstance();
  final _platform = defaultTargetPlatform;
  PageController? _pageController;
  final ScrollController _languageScrollController = ScrollController();
  late final Future<void> _initialization;
  bool _initializing = true;
  int _currentStep = 0;

  String _selectedLocale = 'system';
  bool _storagePermissionGranted = false;
  bool _notificationPermissionGranted = false;
  bool _notificationPermissionSkipped = false;
  bool _storageSkipped = false;
  bool _isLoading = false;
  int _androidSdkVersion = 0;

  int get _storageStep => 2 + localGuidePageCount;
  int get _totalSteps => _storageStep + (_androidSdkVersion >= 33 ? 2 : 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialization = _initDeviceInfo();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pageController?.dispose();
    _languageScrollController.dispose();
    super.dispose();
  }

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
      final saved = prefs.getString(_progressKey);
      if (saved != null) {
        try {
          final draft = jsonDecode(saved) as Map<String, dynamic>;
          var savedStep = (draft['step'] as int?) ?? 0;
          final version = draft['version'];
          // Version 1 drafts used 2/3 for permissions and ended in a
          // download-folder step.
          if (version != 2 && version != 3 && savedStep >= 2) {
            savedStep += localGuidePageCount;
          }
          // Version 3 drafts (English-only build) had no language step at 1.
          if (version == 3 && savedStep >= 1) savedStep += 1;
          _currentStep = savedStep.clamp(0, _totalSteps - 1);
          _notificationPermissionSkipped = draft['skipNotifications'] == true;
          _storageSkipped = draft['skipStorage'] == true;
        } catch (error) {
          await prefs.remove(_progressKey);
          _log.w('Discarding malformed setup progress: $error');
        }
      }
      await _checkInitialPermissions();
    } catch (e, stack) {
      _log.e('Failed to restore setup progress', e, stack);
    } finally {
      if (mounted) {
        _pageController = PageController(initialPage: _currentStep);
        setState(() => _initializing = false);
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAfterResume());
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
      'version': 2,
      'skipNotifications': _notificationPermissionSkipped,
      'skipStorage': _storageSkipped,
    });
    if (!await (await _prefs).setString(_progressKey, draft)) {
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
        setState(() {
          _storagePermissionGranted = storageGranted;
          _notificationPermissionGranted = notificationStatus.isGranted;
        });
      }
    } else {
      setState(() {
        _storagePermissionGranted = true;
        _notificationPermissionGranted = true;
      });
    }
  }

  Future<void> _requestStoragePermission() async {
    if (_isLoading) return;
    setState(() => _isLoading = true);
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
        setState(() => _storagePermissionGranted = added);
        return;
      }

      if (_platform == TargetPlatform.android) {
        final permissionStorage = context.l10n.permissionStorage;
        final status = await Permission.storage.request();
        if (!mounted) return;
        setState(() => _storagePermissionGranted = status.isGranted);
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
        setState(() => _storagePermissionGranted = true);
      }
    } catch (e, stack) {
      _log.e('Storage access request failed', e, stack);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _requestNotificationPermission() async {
    if (_isLoading) return;
    final permissionNotification = context.l10n.permissionNotification;
    setState(() => _isLoading = true);
    try {
      await _saveProgress();
      if (!mounted) return;
      if (_androidSdkVersion >= 33) {
        final status = await Permission.notification.request();
        if (!mounted) return;
        if (status.isGranted) {
          setState(() => _notificationPermissionGranted = true);
        } else if (status.isPermanentlyDenied) {
          await _showPermissionDeniedDialog(permissionNotification);
        }
      } else {
        setState(() => _notificationPermissionGranted = true);
      }
    } catch (e, stack) {
      _log.e('Failed to request notification permission', e, stack);
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
    setState(() => _isLoading = true);

    try {
      await ref.read(settingsProvider.notifier).setFirstLaunchComplete();
      await (await _prefs).remove(_progressKey);

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
      if (mounted) setState(() => _isLoading = false);
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
    setState(() => _isLoading = true);
    try {
      await _saveProgress(step: step);
      if (!mounted) return;
      setState(() => _currentStep = step);
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
      if (mounted) setState(() => _isLoading = false);
    }
  }

  bool _isStepCompleted(int step) {
    if (step < _storageStep) return true;
    if (step == _storageStep) {
      return _storagePermissionGranted || _storageSkipped;
    }
    return _notificationPermissionGranted || _notificationPermissionSkipped;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_initializing) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final progress = (_currentStep + 1) / _totalSteps;

    return PopScope(
      canPop: _currentStep == 0,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _prevPage();
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Row(
                  children: [
                    if (_currentStep > 0)
                      IconButton.filledTonal(
                        onPressed: _prevPage,
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).backButtonTooltip,
                        icon: const Icon(Icons.arrow_back),
                        style: IconButton.styleFrom(
                          backgroundColor: colorScheme.surfaceContainerHighest,
                          foregroundColor: colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      const SizedBox(width: 48),
                    const Spacer(),
                    SizedBox(
                      width: 48,
                      height: 48,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          CircularProgressIndicator(
                            value: progress,
                            strokeWidth: 4,
                            backgroundColor:
                                colorScheme.surfaceContainerHighest,
                            color: colorScheme.primary,
                            strokeCap: StrokeCap.round,
                          ),
                          Center(
                            child: Text(
                              '${_currentStep + 1}/$_totalSteps',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              Expanded(
                child: PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildWelcomeStep(colorScheme),
                    _buildLanguageStep(colorScheme),
                    ...buildLocalGuidePages(
                      context,
                      firstIndex: 2,
                      currentIndex: _currentStep,
                    ),
                    _buildStorageStep(colorScheme),
                    if (_androidSdkVersion >= 33)
                      _buildNotificationStep(colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
        floatingActionButton: _currentStep < _totalSteps - 1
            ? FloatingActionButton.extended(
                onPressed: !_isLoading && _isStepCompleted(_currentStep)
                    ? _nextPage
                    : null,
                label: Row(
                  children: [
                    Text(context.l10n.setupNext),
                    const SizedBox(width: 8),
                    const Icon(Icons.arrow_forward),
                  ],
                ),
                icon: const SizedBox.shrink(), // Custom layout
              )
            : FloatingActionButton.extended(
                onPressed: !_isLoading && _isStepCompleted(_currentStep)
                    ? _completeSetup
                    : null,
                label: _isLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(context.l10n.setupGetStarted),
                icon: const Icon(Icons.check),
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
              ),
      ),
    );
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
        const totalPadding = 48.0 + _headerHeight;
        final minContentHeight = constraints.maxHeight > totalPadding
            ? constraints.maxHeight - totalPadding
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24 + _headerHeight),
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
    setState(() => _selectedLocale = locale);
    ref.read(settingsProvider.notifier).setLocale(locale);
  }

  Widget _buildLanguageStep(ColorScheme colorScheme) {
    final languages = supportedLanguageChoices;

    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final iconPadding = (shortestSide * 0.06).clamp(16.0, 24.0);
        final iconSize = (shortestSide * 0.12).clamp(32.0, 48.0);
        final titleGap = (shortestSide * 0.06).clamp(16.0, 32.0);
        final descriptionGap = (shortestSide * 0.04).clamp(8.0, 16.0);
        final actionGap = (shortestSide * 0.09).clamp(20.0, 48.0);

        return Column(
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(
                24 + wideListInset(context, contentMaxWidth: 560),
                24,
                24 + wideListInset(context, contentMaxWidth: 560),
                0,
              ),
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.all(iconPadding),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.translate,
                      size: iconSize,
                      color: colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: titleGap),
                  Text(
                    context.l10n.setupLanguageTitle,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: descriptionGap),
                  Text(
                    context.l10n.setupLanguageDescription,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: actionGap),
                ],
              ),
            ),
            Expanded(
              child: ScrollEdgeFade(
                child: Scrollbar(
                  controller: _languageScrollController,
                  thumbVisibility: true,
                  child: _buildLanguageList(languages, colorScheme),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildLanguageList(
    List<(String, String, IconData)> languages,
    ColorScheme colorScheme,
  ) {
    return ListView.builder(
      controller: _languageScrollController,
      padding: EdgeInsets.fromLTRB(
        24 + wideListInset(context, contentMaxWidth: 560),
        0,
        24 + wideListInset(context, contentMaxWidth: 560),
        80,
      ),
      itemCount: languages.length,
      itemBuilder: (context, index) {
        final lang = languages[index];
        final code = lang.$1;
        final name = lang.$2;
        final isSelected = _selectedLocale == code;

        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Material(
            color: isSelected
                ? colorScheme.primaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _onLanguageSelected(code),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      lang.$3,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurfaceVariant,
                      size: 22,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        code == 'system'
                            ? context.l10n.setupLanguageSystemDefault
                            : name,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: isSelected
                              ? FontWeight.w600
                              : FontWeight.normal,
                          color: isSelected
                              ? colorScheme.onPrimaryContainer
                              : colorScheme.onSurface,
                        ),
                      ),
                    ),
                    if (isSelected)
                      Icon(
                        Icons.check_circle,
                        color: colorScheme.onPrimaryContainer,
                        size: 22,
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildStorageStep(ColorScheme colorScheme) {
    final scopedFolder =
        _platform == TargetPlatform.android && _androidSdkVersion >= 29;
    return _StepLayout(
      title: context.l10n.setupStorageRequired,
      description: scopedFolder
          ? context.l10n.setupLibraryFolderDescription
          : context.l10n.setupStorageDescription,
      icon: Icons.folder,
      child: _storagePermissionGranted
          ? _SuccessCard(
              text: context.l10n.setupStorageGranted,
              colorScheme: colorScheme,
            )
          : Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _requestStoragePermission,
                  icon: const Icon(Icons.folder_open),
                  label: Text(
                    scopedFolder
                        ? context.l10n.setupChooseMusicFolder
                        : context.l10n.setupGrantPermission,
                  ),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                if (scopedFolder)
                  TextButton(
                    onPressed: () async {
                      setState(() => _storageSkipped = true);
                      await _saveProgress();
                    },
                    child: Text(context.l10n.setupSkipForNow),
                  ),
              ],
            ),
    );
  }

  Widget _buildNotificationStep(ColorScheme colorScheme) {
    return _StepLayout(
      title: context.l10n.setupNotificationEnable,
      description: context.l10n.setupNotificationBackgroundDescription,
      icon: Icons.notifications,
      child: _notificationPermissionGranted || _notificationPermissionSkipped
          ? _SuccessCard(
              text: context.l10n.setupNotificationGranted,
              colorScheme: colorScheme,
            )
          : Column(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _requestNotificationPermission,
                  icon: const Icon(Icons.notifications_active),
                  label: Text(context.l10n.setupEnableNotifications),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 16,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    setState(() => _notificationPermissionSkipped = true);
                    await _saveProgress();
                  },
                  child: Text(context.l10n.setupSkipForNow),
                ),
              ],
            ),
    );
  }
}

class _StepLayout extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Widget child;

  const _StepLayout({
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final iconPadding = (shortestSide * 0.06).clamp(16.0, 24.0);
        final iconSize = (shortestSide * 0.12).clamp(32.0, 48.0);
        final titleGap = (shortestSide * 0.06).clamp(16.0, 32.0);
        final descriptionGap = (shortestSide * 0.04).clamp(8.0, 16.0);
        final actionGap = (shortestSide * 0.09).clamp(20.0, 48.0);
        // Extra bottom padding offsets the 80dp header above the PageView so
        // the content sits at the optical center of the full screen.
        const totalPadding = 48.0 + _headerHeight;
        final minContentHeight = constraints.maxHeight > totalPadding
            ? constraints.maxHeight - totalPadding
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24 + _headerHeight),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: minContentHeight,
                maxWidth: 560,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(iconPadding),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: iconSize,
                      color: colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: titleGap),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: descriptionGap),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: actionGap),
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SuccessCard extends StatelessWidget {
  final String text;
  final ColorScheme colorScheme;

  const _SuccessCard({required this.text, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
