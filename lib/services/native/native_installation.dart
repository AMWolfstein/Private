import 'dart:io';

import 'package:sistrum/services/native/native_channel.dart';

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
