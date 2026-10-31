import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/providers/library/local_library_provider.dart';
import 'package:sistrum/providers/settings/settings_provider.dart';
import 'package:sistrum/services/library/database/library_database.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/services/native/library_scan_bridge.dart';
import 'package:sistrum/services/platform/notification_service.dart';
import 'package:sistrum/utils/scan/local_library_scan_prefs.dart';

part 'library_scan_scheduling_starts.dart';
part 'library_scan_scheduling_reconnect.dart';

/// Scan jobs reach the backend as `runNativeDataJob` requests; these tests
/// hold them open through their own channel handler.
bool _isScanJob(MethodCall call) =>
    call.method == 'runNativeDataJob' &&
    _jobRequest(call)['operation'] == 'library_scan_incremental';

Map<String, dynamic> _jobRequest(MethodCall call) =>
    jsonDecode((call.arguments as Map)['request_json'] as String)
        as Map<String, dynamic>;

class _Settings extends SettingsNotifier {
  @override
  AppSettings build() => const AppSettings();

  @override
  Future<void> ensureLoaded() async {}
}

class _Database implements LibraryDatabase {
  _Database(this.sources);

  List<LocalLibrarySource> sources;
  Future<List<LocalLibrarySource>> Function()? sourceRead;
  bool failLookup = false;
  bool failScanErrorWrite = false;
  int? countOverride;
  Future<({int inserted})> Function()? fullReplacement;
  int clearCalls = 0;

  @override
  Future<void> clearAll() async {
    clearCalls++;
    countOverride = 0;
  }

  @override
  Future<List<LocalLibrarySource>> getSources() async =>
      sourceRead == null ? List.of(sources) : await sourceRead!();

  @override
  Future<LocalLibrarySource?> getSourceByPath(String path) async {
    if (failLookup) throw StateError('source lookup failed');
    return sources.where((source) => source.path == path).firstOrNull;
  }

  @override
  Future<int> getCount() async =>
      countOverride ??
      sources.where((source) => source.enabled && source.available).length;

  @override
  Future<({int inserted})> replaceSourceScanFile(
    String sourceId,
    LibraryScanNDJSONFile scan, {
    required String requestId,
    required bool Function() isCancelled,
  }) => fullReplacement!();

  @override
  Future<String> exportNativeFileModTimesSnapshot(
    String sourceId, {
    required String requestId,
    required bool Function() isCancelled,
  }) async => 'library-scan-snapshot.tsv';

  @override
  Future<Map<String, dynamic>> scanIncrementalNative(
    String sourceId,
    String folderPath,
    String snapshotPath, {
    required bool isSaf,
    required String requestId,
    required bool Function() isCancelled,
  }) => NativeDataJobs.run({
    'operation': 'library_scan_incremental',
    'folder_path': folderPath,
    'snapshot_path': snapshotPath,
  }, requestId: requestId);

  @override
  Future<int> getSourceCount(String sourceId) async => 1;

  @override
  Future<void> removeSource(String sourceId) async {
    sources.removeWhere((source) => source.id == sourceId);
  }

  @override
  Future<void> updateSourceState(
    String sourceId, {
    bool? enabled,
    bool? available,
    DateTime? lastScannedAt,
    DateTime? lastSeenAt,
    String? lastScanError,
    bool clearLastScanError = false,
  }) async {
    if (lastScanError != null && failScanErrorWrite) {
      throw StateError('Could not save scan failure');
    }
    sources = [
      for (final source in sources)
        source.id == sourceId
            ? source.copyWith(
                enabled: enabled,
                available: available,
                lastScanError: lastScanError,
                clearLastScanError: clearLastScanError,
              )
            : source,
    ];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _waitFor(bool Function() condition) async {
  for (var i = 0; i < 100 && !condition(); i++) {
    await Future<void>.delayed(Duration.zero);
  }
  expect(condition(), isTrue);
}

void main() {
  _registerLibraryScanSchedulingStarts();
  _registerLibraryScanSchedulingReconnect();
}
