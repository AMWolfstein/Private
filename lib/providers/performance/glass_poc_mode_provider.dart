import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/widgets/glass_poc/sistrum_glass_mode.dart';

/// The Glass POC mode selected on the developer page. Held in memory only, so
/// a restart returns to the baseline. The performance HUD reads it to label
/// its reports.
final glassPocModeProvider =
    NotifierProvider<GlassPocModeNotifier, SistrumGlassMode>(
      GlassPocModeNotifier.new,
    );

class GlassPocModeNotifier extends Notifier<SistrumGlassMode> {
  @override
  SistrumGlassMode build() => SistrumGlassMode.transparentBaseline;

  void select(SistrumGlassMode mode) {
    if (state != mode) state = mode;
  }
}
