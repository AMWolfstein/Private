import 'dart:async';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:ui' show FramePhase, FrameTiming, PlatformDispatcher;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/providers/theme_provider.dart';
import 'package:mornye/services/performance/performance_recorder.dart';

final performanceControllerProvider = Provider<PerformanceController>((ref) {
  final controller = PerformanceController();
  ref.listen(
    settingsProvider.select(
      (s) => (
        s.performanceMonitoring,
        s.performanceFirstInteraction,
        s.performanceWindowMs,
        s.performanceIdleMs,
        s.motionArtworkEnabled,
      ),
    ),
    (_, next) {
      controller.motionArtworkEnabled = next.$5;
      controller.configure(next.$1, next.$2, next.$3, next.$4);
    },
    fireImmediately: true,
  );
  ref.listen(themeProvider.select((t) => (t.style.name, t.mornyeGlassOutlines)), (
    _,
    next,
  ) {
    controller.glassConfiguration =
        'style:${next.$1},clarity:fixed_clear,outlines_preference:${next.$2}; effective_per_surface_parameters:unavailable';
  }, fireImmediately: true);
  ref.onDispose(controller.dispose);
  return controller;
});

/// One collector per ProviderScope. The native listener is event driven; the
/// frame callback exists only while enabled. Nothing requests an extra frame.
class PerformanceController extends ChangeNotifier with WidgetsBindingObserver {
  PerformanceController({this.androidOverride}) {
    if (androidOverride ?? Platform.isAndroid) {
      _channel.setMethodCallHandler((call) async {
        if (call.method == 'onState' && !_disposed) _setDisplay(call.arguments);
      });
      unawaited(_readDisplay());
    }
  }
  final bool? androidOverride;
  static const _channel = MethodChannel('com.zarz.mornye/performance_display');
  final recorder = PerformanceRecorder();
  String glassConfiguration = 'unavailable';
  bool? motionArtworkEnabled;
  PerformanceDisplay display = PerformanceDisplay();
  final _clock = Stopwatch()..start();
  Timer? _updates, _captureEnd;
  bool _registered = false, _disposed = false;
  bool _observingLifecycle = false, _foreground = true;
  int _generation = 0;
  int get nowUs => _clock.elapsedMicroseconds;
  bool get registered => _registered;
  PerformanceSnapshot get snapshot => recorder.snapshot(nowUs);

  Future<void> _readDisplay([String method = 'getState']) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method);
      if (!_disposed) _setDisplay(result);
    } on PlatformException {
      /* Unsupported platforms report unavailable. */
    } on MissingPluginException {
      /* Host tests and desktop have no bridge. */
    }
  }

  void _setDisplay(Object? result) {
    if (result is! Map) return;
    display = PerformanceDisplay(result.cast<Object?, Object?>());
    notifyListeners();
  }

  void configure(bool enabled, bool first, int windowMs, int idleMs) {
    final wasEnabled = recorder.enabled;
    recorder.configure(
      enabled: enabled,
      firstInteraction: first,
      windowMs: windowMs,
      idleMs: idleMs,
      nowUs: nowUs,
    );
    _foreground =
        SchedulerBinding.instance.lifecycleState == null ||
        SchedulerBinding.instance.lifecycleState == AppLifecycleState.resumed;
    if (enabled && !_observingLifecycle) {
      WidgetsBinding.instance.addObserver(this);
      _observingLifecycle = true;
    } else if (!enabled && _observingLifecycle) {
      WidgetsBinding.instance.removeObserver(this);
      _observingLifecycle = false;
    }
    _syncRegistration();
    if (!enabled || !first || wasEnabled != enabled) {
      _generation++;
      _captureEnd?.cancel();
      recorder.finishInteraction();
    }
    _updateTimer();
    notifyListeners();
  }

  void _syncRegistration() {
    final collect = recorder.enabled && _foreground;
    if (collect && !_registered) {
      SchedulerBinding.instance.addTimingsCallback(_timings);
      _registered = true;
    } else if (!collect && _registered) {
      SchedulerBinding.instance.removeTimingsCallback(_timings);
      _registered = false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_disposed) return;
    _foreground = state == AppLifecycleState.resumed;
    _syncRegistration();
    if (!_foreground) {
      _generation++;
      _captureEnd?.cancel();
      recorder.finishInteraction();
    }
    _updateTimer();
  }

  void _timings(List<FrameTiming> frames) {
    if (!recorder.enabled || !_foreground || _disposed) return;
    final receipt = nowUs;
    final budget = display.budgetMs;
    for (final frame in frames) {
      recorder.addFrame(
        observedUs: receipt,
        engineUs: frame.timestampInMicroseconds(FramePhase.vsyncStart),
        buildMs: frame.buildDuration.inMicroseconds / 1000,
        rasterMs: frame.rasterDuration.inMicroseconds / 1000,
        spanMs: frame.totalSpan.inMicroseconds / 1000,
        budgetMs: budget,
      );
    }
  }

  void pointer([Duration? eventTimeStamp]) {
    if (!_foreground) return;
    if (!recorder.pointer(
      nowUs,
      DateTime.now().toUtc(),
      eventUs: eventTimeStamp?.inMicroseconds,
    )) {
      return;
    }
    final generation = ++_generation;
    // Passive observation: addPostFrameCallback never schedules a frame.
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && generation == _generation) {
        recorder.observeInteractionFrame(
          nowUs,
          SchedulerBinding.instance.currentSystemFrameTimeStamp.inMicroseconds,
        );
      }
    });
    _captureEnd?.cancel();
    // Close passive observation; late timing delivery still matches bounded history.
    _captureEnd = Timer(
      const Duration(milliseconds: 1500),
      recorder.finishInteraction,
    );
  }

  final _scopes = <String, String>{};
  String _root = '/', _tab = 'home';
  void setRoute(String scope, String name) {
    if (scope == 'root') {
      _root = name;
    } else {
      _scopes[scope] = name;
    }
    _screen();
  }

  void setTab(String name) {
    _tab = name;
    _screen();
  }

  void _screen() => recorder.changeScreen(
    _root == '/' ? (_scopes[_tab] ?? _tab) : _root,
    nowUs,
  );
  void reset() {
    _generation++;
    _captureEnd?.cancel();
    recorder.reset(nowUs);
    if (androidOverride ?? Platform.isAndroid) {
      unawaited(_readDisplay('resetStatistics'));
    }
    notifyListeners();
  }

  void _updateTimer() {
    _updates?.cancel();
    _updates = recorder.enabled && _foreground && hasListeners
        ? Timer.periodic(const Duration(seconds: 1), (_) => notifyListeners())
        : null;
  }

  @override
  void addListener(VoidCallback listener) {
    super.addListener(listener);
    _updateTimer();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    _updateTimer();
  }

  String report({String? screen}) {
    final result = formatPerformanceReport(
      snapshot: recorder.recentSnapshots[screen] ?? snapshot,
      display: display,
      glassConfiguration: glassConfiguration,
      motionArtworkEnabled: motionArtworkEnabled,
      build: kReleaseMode
          ? 'release'
          : kProfileMode
          ? 'profile'
          : 'debug',
      abi: _abi(),
      flutterHz: PlatformDispatcher.instance.views.isEmpty
          ? 'unavailable'
          : PlatformDispatcher.instance.views.first.display.refreshRate
                .toStringAsFixed(2),
      enabled: recorder.enabled,
      interactions: recorder.interactions
          .where(
            (i) =>
                i.screen ==
                (recorder.recentSnapshots[screen]?.screen ?? recorder.screen),
          )
          .toList(),
      lastInteractionUtc: recorder.lastInteractionUtc,
    );
    return '$result\ncurrent_screen=${recorder.screen}\narchived_window=${recorder.recentSnapshots.containsKey(screen)}';
  }

  String _abi() => switch (Abi.current()) {
    Abi.androidArm64 => 'arm64-v8a',
    Abi.androidArm => 'armeabi-v7a',
    Abi.androidX64 => 'x86_64',
    _ => Abi.current().toString(),
  };
  @override
  void dispose() {
    _disposed = true;
    _generation++;
    if (_registered) SchedulerBinding.instance.removeTimingsCallback(_timings);
    _registered = false;
    if (_observingLifecycle) WidgetsBinding.instance.removeObserver(this);
    _observingLifecycle = false;
    _updates?.cancel();
    _captureEnd?.cancel();
    if (androidOverride ?? Platform.isAndroid) {
      _channel.setMethodCallHandler(null);
    }
    super.dispose();
  }
}

/// Names are route identifiers, never titles containing private library data.
class PerformanceRouteObserver extends NavigatorObserver {
  PerformanceRouteObserver(this.controller, {this.scope = 'root'});
  final String scope;
  final PerformanceController controller;
  final _routes = <Route<dynamic>>[];
  void _refresh() => controller.setRoute(
    scope,
    _routes.isEmpty
        ? 'unavailable'
        : _routes.last.settings.name ??
              (_routes.length == 1 && scope != 'root' ? scope : 'unavailable'),
  );
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.add(route);
    _refresh();
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _refresh();
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _routes.remove(route);
    _refresh();
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final i = oldRoute == null ? -1 : _routes.indexOf(oldRoute);
    if (i >= 0) {
      if (newRoute == null) {
        _routes.removeAt(i);
      } else {
        _routes[i] = newRoute;
      }
    }
    _refresh();
  }
}
