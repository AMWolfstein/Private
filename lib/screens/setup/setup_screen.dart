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
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/screens/setup/local_guide_pages.dart';
import 'package:sistrum/services/library/scan/library_folder_selection.dart';
import 'package:sistrum/core/constants/language_choices.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/widgets/shell/scroll_edge_fade.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/screens/setup/setup_step_layout.dart';

part 'setup_screen_flow.dart';
part 'setup_screen_steps.dart';

final _log = AppLogger('SetupScreen');

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

  /// Tips the guide had before it was merged into one page; only old drafts
  /// still count in these steps.
  static const _fivePageGuideCount = 5;

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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshAfterResume());
    }
  }

  void _rebuild(VoidCallback fn) => setState(fn);

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
}
