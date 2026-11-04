import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/widgets/glass/debug/app_artist_glass_isolation.dart';

/// Developer-only: draws every LIQUID surface as TINT, from the performance
/// HUD, so a measurement can tell g1455's host capture (a layer-tree walk on
/// the UI thread and a rasterization, whenever the tree changes) apart from
/// everything else. With no LIQUID surface mounted the host records nothing.
/// On by default (normal rendering) and never persisted.
class AppLiquidDiagnosticNotifier extends Notifier<bool> {
  @override
  bool build() => true;

  void toggle() {
    state = !state;
    // A new measurement window starts with every change.
    appDiagnosticWindowEpoch.value++;
  }
}

/// Whether LIQUID surfaces draw (true, the normal rendering).
final appLiquidDiagnosticProvider =
    NotifierProvider<AppLiquidDiagnosticNotifier, bool>(
      AppLiquidDiagnosticNotifier.new,
    );
