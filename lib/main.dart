import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/navigation/app_screens.dart';
import 'package:sistrum/screens/app_screens.dart';
import 'package:sistrum/app.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/cover_palette_provider.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:sistrum/providers/theme_provider.dart';
import 'package:sistrum/services/glass/app_glass_auto_probe.dart';
import 'package:sistrum/services/platform/notification_service.dart';
import 'package:sistrum/services/native/native_device.dart';
import 'package:sistrum/services/storage/app_state_database.dart';
import 'package:sistrum/core/navigation/app_navigation.dart';
import 'package:sistrum/services/platform/app_orientation.dart';
import 'package:sistrum/services/playback/notification/activity_attachment.dart';
import 'package:sistrum/services/playback/music_player/music_player_service.dart';
import 'package:sistrum/services/playback/notification/player_widget_service.dart';
import 'package:sistrum/screens/now_playing_screen.dart';
import 'package:sistrum/utils/scan/local_library_scan_prefs.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/services/native/native_channel.dart';

part 'main_startup_1.dart';

final _log = AppLogger('Main');
_StartupBenchmark? _startupBenchmark;

void main() {
  if (const bool.fromEnvironment('CORE_BACKEND_STARTUP_BENCHMARK')) {
    _startupBenchmark = _StartupBenchmark();
  }
  // Catch uncaught Dart errors so a failing async path is logged, not fatal.
  // Native (Go) crashes still can't be caught here.
  runZonedGuarded(
    () async {
      final binding = WidgetsFlutterBinding.ensureInitialized();
      if (Platform.isAndroid) {
        // A media service can start the shared engine before MainActivity
        // registers the local backend and platform channels.
        await waitForActivityAttachment(binding);
      }
      // PERF-604: the orientation lock is independent of the prefs and
      // installation steps; run it in parallel and await it before runApp.
      final orientation = setAppOrientation();
      LicenseRegistry.addLicense(() async* {
        yield LicenseEntryWithLineBreaks(const [
          'Inter',
        ], await rootBundle.loadString('assets/fonts/Inter-LICENSE.txt'));
        yield LicenseEntryWithLineBreaks(const [
          'Material Color Utilities (native palette)',
          'Dart SDK (native Random compatibility)',
        ], await rootBundle.loadString('assets/licenses/native_palette.txt'));
        yield LicenseEntryWithLineBreaks(const [
          'rusqlite',
          'roxmltree',
        ], await rootBundle.loadString('assets/licenses/native_data_jobs.txt'));
        if (Platform.isAndroid) {
          yield LicenseEntryWithLineBreaks(const [
            'libusb',
            'libusb1-sys',
          ], await rootBundle.loadString('assets/licenses/usb.txt'));
          yield LicenseEntryWithLineBreaks(const [
            'Oboe',
          ], await rootBundle.loadString('assets/licenses/oboe.txt'));
          yield LicenseEntryWithLineBreaks(const [
            'WavPack',
          ], await rootBundle.loadString('assets/licenses/wavpack.txt'));
          yield LicenseEntryWithLineBreaks(const [
            'libFLAC',
          ], await rootBundle.loadString('assets/licenses/flac.txt'));
          yield LicenseEntryWithLineBreaks(const [
            'FFmpeg',
          ], await rootBundle.loadString('assets/licenses/ffmpeg.txt'));
          yield LicenseEntryWithLineBreaks(const [
            'FFmpeg',
            'FFmpegKit',
          ], await rootBundle.loadString('assets/licenses/lgpl-3.0.txt'));
        }
      });
      _startupBenchmark?.observeFirstFrame();

      final previousOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        previousOnError?.call(details);
        _log.e(
          'Uncaught Flutter error: ${details.exceptionAsString()}',
          details.exception,
          details.stack,
        );
      };
      WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
        _log.e('Uncaught platform error: $error', error, stack);
        return true;
      };

      final prefs = await SharedPreferences.getInstance();
      await _prepareAndroidInstallationState(prefs);
      final bootstrapSettings = loadBootstrapSettings(prefs);
      musicPlayerRuntime.configure(bootstrapSettings);
      final bootstrapTheme = loadBootstrapThemeSettings(prefs);
      final runtimeProfile = await _resolveRuntimeProfile(prefs);
      _configureImageCache(runtimeProfile);
      await orientation;

      final container = ProviderContainer(
        overrides: [
          appScreensProvider.overrideWithValue(const AppScreenBuilders()),
          lowEndDeviceProvider.overrideWithValue(
            runtimeProfile.disableOverscrollEffects,
          ),
          // The RAM tiers describe Android hardware. Other platforms keep
          // the existing full material by default.
          deviceSupportsLiquidGlassProvider.overrideWithValue(
            !Platform.isAndroid || runtimeProfile.enableBackdropBlur,
          ),
          initialSettingsProvider.overrideWithValue(bootstrapSettings),
          initialThemeSettingsProvider.overrideWithValue(bootstrapTheme),
          initialGlassAutoResultProvider.overrideWithValue(
            loadGlassAutoResult(prefs, build: appGlassAutoBuild()),
          ),
        ],
      );
      runApp(
        UncontrolledProviderScope(
          container: container,
          child: EagerInitialization(
            child: SistrumApp(
              disableOverscrollEffects: runtimeProfile.disableOverscrollEffects,
            ),
          ),
        ),
      );
      if (Platform.isAndroid) {
        unawaited(
          PlayerWidgetService.instance.initialize((command) async {
            await restorePersistedPlaybackSession();
            final handler = await initMusicPlayer();
            if (command == 'open') {
              await WidgetsBinding.instance.endOfFrame;
              final navigator =
                  AppNavigationService.rootNavigatorKey.currentState;
              if (navigator != null && handler.mediaItem.value != null) {
                unawaited(
                  navigator.push<void>(
                    NowPlayingRoute(child: const NowPlayingScreen()),
                  ),
                );
              }
            } else {
              await PlayerWidgetService.control(handler, command);
            }
          }, palette: container.read(coverPaletteProvider)),
        );
      }
    },
    (error, stack) {
      _log.e('Uncaught zone error: $error');
    },
  );
}

// Opt-in release measurement. The ordinary startup path owns initialization;
// reporting and validation happen after both measured boundaries are captured.

const _runtimeProfileTierKey = 'runtime_profile_tier_v1';

class EagerInitialization extends ConsumerStatefulWidget {
  const EagerInitialization({super.key, required this.child});
  final Widget child;

  @override
  ConsumerState<EagerInitialization> createState() =>
      _EagerInitializationState();
}

class InstallationState {
  final bool markerExisted;
  final bool markerCreated;
  final bool freshPackageInstall;

  const InstallationState({
    required this.markerExisted,
    required this.markerCreated,
    required this.freshPackageInstall,
  });

  const InstallationState.unsupported()
    : markerExisted = true,
      markerCreated = true,
      freshPackageInstall = false;

  factory InstallationState.fromMap(Map<String, dynamic> map) {
    return InstallationState(
      markerExisted: map['marker_existed'] == true,
      markerCreated: map['marker_created'] == true,
      freshPackageInstall: map['fresh_package_install'] == true,
    );
  }
}

bool shouldResetRestoredInstallation({
  required bool hasPersistedSettings,
  required InstallationState installState,
}) {
  return hasPersistedSettings &&
      !installState.markerExisted &&
      installState.markerCreated &&
      installState.freshPackageInstall;
}

final class NativeInstallation {
  NativeInstallation._();

  static Future<InstallationState> ensureMarker() async {
    if (!Platform.isAndroid) return const InstallationState.unsupported();
    final result = await nativeInvokeMap('ensureInstallMarker');
    return InstallationState.fromMap(result);
  }
}
