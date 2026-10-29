import 'package:sistrum/services/platform_bridge.dart';

typedef NativeCacheJobRunner =
    Future<Map<String, dynamic>> Function(
      Map<String, dynamic> request, {
      String? requestId,
    });

/// Filesystem cache work runs in the native backend's cancellable worker.
Future<Map<String, dynamic>> runNativeCacheMaintenance(
  Map<String, dynamic> request, {
  String? requestId,
  NativeCacheJobRunner? nativeJobRunner,
}) async {
  if (nativeJobRunner != null) {
    return nativeJobRunner(request, requestId: requestId);
  }
  return PlatformBridge.runNativeDataJob(request, requestId: requestId);
}

int cacheMaintenanceDeletedCount(Map<String, dynamic> result) {
  final deleted = result['deleted'];
  if (deleted is! int || deleted < 0) {
    throw StateError('Invalid native cache maintenance result');
  }
  return deleted;
}
