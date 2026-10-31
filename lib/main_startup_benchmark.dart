part of 'main.dart';

class _StartupBenchmark {
  final _watch = Stopwatch()..start();
  late final Future<int> _firstFrame;

  void observeFirstFrame() {
    _firstFrame = WidgetsBinding.instance.waitUntilFirstFrameRasterized.then(
      (_) => _watch.elapsedMicroseconds,
    );
  }

  // Startup services init closes the benchmark boundary.
  void appReady(AppSettings settings) {
    final ready = _watch.elapsedMicroseconds;
    unawaited(_report(settings, ready));
  }

  Future<void> _report(AppSettings settings, int ready) async {
    try {
      if (!kReleaseMode) throw StateError('Startup benchmark requires release');
      final firstFrame = await _firstFrame.timeout(const Duration(seconds: 30));
      final backends = await NativeDevice.getBackendImplementations();
      const backend = String.fromEnvironment('EXPECTED_CORE_BACKEND');
      if (backend != 'rust' ||
          backends.length != 3 ||
          !const {
            'filename',
            'file_metadata',
            'library',
          }.containsAll(backends.keys) ||
          backends.values.any((value) => value != backend)) {
        throw StateError('Unexpected backend ownership: $backends');
      }
      await _write({
        'result': 'CORE_BACKEND_STARTUP_PASS backend=$backend',
        'startup': {
          'schema': 1,
          'backend': backend,
          'mode': 'release',
          'start_boundary': 'Dart main entry before bindings',
          'first_frame_boundary': 'first rasterized frame observed',
          'ready_boundary': 'local app services initialized',
          'cache': 'fresh process; warm filesystem',
          'first_frame_us': firstFrame,
          'app_ready_us': ready,
          'settings_sha256': sha256
              .convert(utf8.encode(jsonEncode(settings.toJson())))
              .toString(),
        },
      });
    } catch (error) {
      await _write({'result': 'CORE_BACKEND_STARTUP_FAIL $error'});
    }
  }

  Future<void> _write(Map<String, Object?> result) async {
    final support = await getApplicationSupportDirectory();
    await File(
      '${support.path}/core-backend-probe-result.json',
    ).writeAsString(jsonEncode({'pid': pid, ...result}), flush: true);
  }
}

Future<void> _prepareAndroidInstallationState(SharedPreferences prefs) async {
  if (!Platform.isAndroid) return;

  try {
    final hasPersistedSettings = hasPersistedAppSettings(prefs);
    final installState = await NativeInstallation.ensureMarker();
    final shouldReset = shouldResetRestoredInstallation(
      hasPersistedSettings: hasPersistedSettings,
      installState: installState,
    );
    if (!shouldReset) return;

    _log.w(
      'Android restored state into a fresh installation; resetting '
      'installation-bound settings',
    );
    await resetRestoredInstallationSettings(prefs);
    await prefs.remove(_runtimeProfileTierKey);
    await prefs.remove(localLibraryLastScannedAtKey);
    await AppStateDatabase.instance.clearRestoredPlaybackState();
  } catch (e) {
    // Failed marker inspection must not prevent startup. Local sources still
    // validate their own grants before access.
    _log.w('Failed to inspect restored installation state: $e');
  }
}

Future<_RuntimeProfile> _resolveRuntimeProfile(SharedPreferences prefs) async {
  final cachedTier = prefs.getString(_runtimeProfileTierKey);
  if (cachedTier != null) {
    final cached = _RuntimeProfile.fromTier(cachedTier);
    if (cached != null) return cached;
  }

  const defaults = _RuntimeProfile.standard();

  if (!Platform.isAndroid) {
    await prefs.setString(_runtimeProfileTierKey, defaults.tier);
    return defaults;
  }

  try {
    final androidInfo = await DeviceInfoPlugin().androidInfo;
    final isArm32Only = androidInfo.supported64BitAbis.isEmpty;
    final isLowRamDevice =
        androidInfo.isLowRamDevice || androidInfo.physicalRamSize <= 2500;

    final profile = (isArm32Only || isLowRamDevice)
        ? const _RuntimeProfile.low()
        : androidInfo.physicalRamSize >= 6000
        ? const _RuntimeProfile.high()
        : defaults;
    await prefs.setString(_runtimeProfileTierKey, profile.tier);
    return profile;
  } catch (e) {
    debugPrint('Failed to resolve runtime profile: $e');
    return defaults;
  }
}

void _configureImageCache(_RuntimeProfile runtimeProfile) {
  final imageCache = PaintingBinding.instance.imageCache;
  // Keep memory cache bounded so cover-heavy pages don't retain too many
  // full-resolution images simultaneously.
  imageCache.maximumSize = runtimeProfile.imageCacheMaximumSize;
  imageCache.maximumSizeBytes = runtimeProfile.imageCacheMaximumSizeBytes;
}

class _RuntimeProfile {
  final String tier;
  final int imageCacheMaximumSize;
  final int imageCacheMaximumSizeBytes;
  final bool disableOverscrollEffects;
  final bool enableBackdropBlur;

  const _RuntimeProfile._({
    required this.tier,
    required this.imageCacheMaximumSize,
    required this.imageCacheMaximumSizeBytes,
    required this.disableOverscrollEffects,
    required this.enableBackdropBlur,
  });

  const _RuntimeProfile.low()
    : this._(
        tier: 'low',
        imageCacheMaximumSize: 120,
        imageCacheMaximumSizeBytes: 24 << 20,
        disableOverscrollEffects: true,
        enableBackdropBlur: false,
      );

  const _RuntimeProfile.standard()
    : this._(
        tier: 'standard',
        imageCacheMaximumSize: 240,
        imageCacheMaximumSizeBytes: 60 << 20,
        disableOverscrollEffects: false,
        enableBackdropBlur: false,
      );

  const _RuntimeProfile.high()
    : this._(
        tier: 'high',
        imageCacheMaximumSize: 320,
        imageCacheMaximumSizeBytes: 80 << 20,
        disableOverscrollEffects: false,
        enableBackdropBlur: true,
      );

  static _RuntimeProfile? fromTier(String tier) => switch (tier) {
    'low' => const _RuntimeProfile.low(),
    'standard' => const _RuntimeProfile.standard(),
    'high' => const _RuntimeProfile.high(),
    _ => null,
  };
}

class _EagerInitializationState extends ConsumerState<EagerInitialization>
    with WidgetsBindingObserver {
  Timer? _localLibraryWarmupTimer;
  bool _localLibraryWarmupScheduled = false;
  bool _autoScanTriggeredOnLaunch = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _initializeAppServices();
      _initializeDeferredProviders();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _localLibraryWarmupTimer?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _maybeAutoScanLocalLibrary();
      if (ref.exists(localLibraryProvider)) {
        unawaited(
          ref
              .read(localLibraryProvider.notifier)
              .refreshSourceAvailability(scanReconnected: true),
        );
      }
    } else if (state == AppLifecycleState.paused) {
      // Backgrounded: release idle native runtimes and connections.
      unawaited(NativeDevice.releaseMemory());
    }
  }

  @override
  void didHaveMemoryPressure() {
    // OS memory pressure: drop decoded bitmaps (disk caches stay intact) and
    // ask the native backend to release disposable runtimes and caches.
    final imageCache = PaintingBinding.instance.imageCache;
    imageCache.clear();
    imageCache.clearLiveImages();
    unawaited(NativeDevice.releaseMemory(underPressure: true));
  }

  void _initializeDeferredProviders() {
    _scheduleLocalLibraryWarmup();
  }

  Timer _scheduleProviderWarmup(Duration delay, VoidCallback action) {
    return Timer(delay, () {
      if (!mounted) return;
      action();
    });
  }

  void _scheduleLocalLibraryWarmup() {
    if (_localLibraryWarmupScheduled) return;
    _localLibraryWarmupScheduled = true;
    _localLibraryWarmupTimer = _scheduleProviderWarmup(
      const Duration(milliseconds: 1600),
      () {
        ref.read(localLibraryProvider);
        if (!_autoScanTriggeredOnLaunch) {
          _autoScanTriggeredOnLaunch = true;
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _maybeAutoScanLocalLibrary();
          });
        }
      },
    );
  }

  Future<void> _maybeAutoScanLocalLibrary() async {
    if (!mounted) return;

    final settings = ref.read(settingsProvider);
    if (settings.localLibraryAutoScan == 'off') return;

    final libraryState = ref.read(localLibraryProvider);
    if (libraryState.isScanning) return;

    final now = DateTime.now();
    final prefs = await SharedPreferences.getInstance();
    final pendingSourceId = prefs.getString(localLibraryActiveScanSourceKey);
    if (pendingSourceId != null && pendingSourceId.trim().isNotEmpty) {
      await ref
          .read(localLibraryProvider.notifier)
          .startSourceScan(pendingSourceId.trim());
      return;
    }
    final lastScanned = readLocalLibraryLastScannedAt(prefs);

    if (lastScanned != null) {
      final elapsed = now.difference(lastScanned);

      switch (settings.localLibraryAutoScan) {
        case 'on_open':
          if (elapsed.inMinutes < 10) return;
          break;
        case 'daily':
          if (elapsed.inHours < 24) return;
          break;
        case 'weekly':
          if (elapsed.inDays < 7) return;
          break;
        default:
          return;
      }
    }

    await ref.read(localLibraryProvider.notifier).scanAllSources();
  }

  Future<void> _initializeAppServices() async {
    try {
      await Future.wait([NotificationService().initialize()]);
      _startupBenchmark?.appReady(ref.read(settingsProvider));
    } catch (e) {
      debugPrint('Failed to initialize app services: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
