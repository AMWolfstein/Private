import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/display/display_refresh_rate.dart';
import 'package:sistrum/widgets/glass_poc/glass_display_mode_log.dart';

DisplayRefreshState _s(int id, double hz, {int preferenceHz = 120}) =>
    DisplayRefreshState.fromMap({
      'attached': true,
      'preferenceHz': preferenceHz,
      'requestedModeId': 3,
      'requestedHz': 120.0,
      'activeModeId': id,
      'activeModeHz': hz,
      'displayRefreshHz': hz,
      'supportedRates': [60, 90, 120],
      'modes': ['1:1080x2400@60.00', '3:1080x2400@120.00'],
    });

void main() {
  test('only active-mode changes are logged, and only while running', () {
    final log = GlassDisplayModeLog()..begin(_s(3, 120));
    log.onState(_s(3, 120), 'phase=measuring');
    expect(log.changes, 0);
    log.onState(_s(1, 60), 'phase=measuring mode=newFullGlass');
    log.onState(_s(3, 120), 'phase=measuring mode=newFullGlass');
    expect(log.changes, 2);
    expect(log.entries.first, contains('start'));
    expect(log.entries[1], contains('active_mode=1@60.00Hz'));
    log.end();
    log.onState(_s(1, 60), 'after');
    expect(log.changes, 2);
  });

  test('the log is bounded', () {
    final log = GlassDisplayModeLog(capacity: 3)..begin(_s(3, 120));
    for (var i = 0; i < 10; i++) {
      log.onState(_s(i.isEven ? 1 : 3, i.isEven ? 60 : 120), 'x');
    }
    expect(log.changes, 10);
    expect(log.entries, hasLength(3));
  });

  test('report lines keep the request apart from the reported mode', () {
    final lines = glassDisplayRefreshLines(
      preferenceHz: 120,
      state: _s(1, 60),
      log: GlassDisplayModeLog()..begin(_s(1, 60)),
    ).join('\n');
    expect(lines, contains('display_refresh_selected=120Hz'));
    expect(lines, contains('display_refresh_requested=mode 3 @ 120.00Hz'));
    expect(lines, contains('display_active_mode[android]=mode 1'));
    expect(lines, contains('@ 60.00Hz'));
    expect(lines, contains('display_refresh_status=notApplied'));
    expect(lines, contains('display_mode_changes_during_benchmark=0'));
    expect(lines, contains('not the panel\'s presentation cadence'));
  });

  test('System Default and no platform are labelled as such', () {
    final lines = glassDisplayRefreshLines(
      preferenceHz: 0,
      state: DisplayRefreshState.unavailable,
    ).join('\n');
    expect(lines, contains('display_refresh_selected=system_default'));
    expect(lines, contains('display_refresh_requested=none'));
    expect(lines, contains('display_active_mode[android]=unavailable'));
    expect(lines, isNot(contains('during_benchmark')));
  });
}
