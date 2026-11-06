import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/providers/performance_provider.dart';
import 'package:mornye/providers/settings_provider.dart';
import 'package:mornye/widgets/app_sliver_header.dart';
import 'package:mornye/widgets/settings_group.dart';

class PerformanceHubPage extends ConsumerStatefulWidget {
  const PerformanceHubPage({super.key});
  @override
  ConsumerState<PerformanceHubPage> createState() => _PerformanceHubPageState();
}

class _PerformanceHubPageState extends ConsumerState<PerformanceHubPage> {
  String? _reportScreen;
  @override
  void initState() {
    super.initState();
    _reportScreen = ref
        .read(performanceControllerProvider)
        .recorder
        .recentSnapshots
        .keys
        .where((key) => key != 'unavailable')
        .lastOrNull;
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final controller = ref.watch(performanceControllerProvider);
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const AppSliverHeader.page(title: 'Performance Hub'),
          ...settingsSectionSlivers(
            title: 'Monitoring',
            children: [
              SettingsItem(
                icon: Icons.monitor,
                title: 'Measurement screen',
                subtitle:
                    'Previous screens keep a frozen window (up to eight).',
                trailing: DropdownButton<String>(
                  value:
                      controller.recorder.recentSnapshots.containsKey(
                        _reportScreen,
                      )
                      ? _reportScreen
                      : 'current',
                  items: [
                    const DropdownMenuItem(
                      value: 'current',
                      child: Text('Current screen'),
                    ),
                    for (final screen
                        in controller.recorder.recentSnapshots.keys)
                      DropdownMenuItem(
                        value: screen,
                        child: Text(
                          screen.split('/').last,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (v) =>
                      setState(() => _reportScreen = v == 'current' ? null : v),
                ),
              ),
              SettingsSwitchItem(
                icon: Icons.speed,
                title: 'Enable Performance Monitoring',
                subtitle:
                    'Flutter frame production, not physical display presentation.',
                value: settings.performanceMonitoring,
                onChanged: notifier.setPerformanceMonitoring,
              ),
              SettingsSwitchItem(
                icon: Icons.picture_in_picture_alt,
                title: 'Show Floating Performance HUD',
                subtitle:
                    'Updates once per second while monitoring is enabled.',
                value: settings.performanceHud,
                onChanged: notifier.setPerformanceHud,
              ),
              SettingsItem(
                icon: Icons.blur_on,
                title: 'Glass batch renderer',
                subtitle:
                    'Diagnostic: how batched glass shares its read and blurs. Default is the reviewed look.',
                trailing: DropdownButton<String>(
                  value: settings.glassBatchRenderer,
                  items: const [
                    DropdownMenuItem(
                      value: 'separate_pass',
                      child: Text('Separate pass (default)'),
                    ),
                    DropdownMenuItem(
                      value: 'single_pass',
                      child: Text('Single pass'),
                    ),
                    DropdownMenuItem(
                      value: 'shader_blur',
                      child: Text('Shader blur'),
                    ),
                  ],
                  onChanged: (v) {
                    if (v != null) notifier.setGlassBatchRenderer(v);
                  },
                ),
              ),
              SettingsSwitchItem(
                icon: Icons.touch_app,
                title: 'Enable First Interaction Analysis',
                subtitle:
                    'Observe the first frame after idle; never pointer-to-photon latency.',
                value: settings.performanceFirstInteraction,
                onChanged: notifier.setPerformanceFirstInteraction,
              ),
              SettingsItem(
                icon: Icons.timer_outlined,
                title: 'Idle Threshold',
                trailing: DropdownButton<int>(
                  value: settings.performanceIdleMs,
                  items: [
                    for (final ms in ({
                      settings.performanceIdleMs,
                      1000,
                      3000,
                      5000,
                      10000,
                    }.toList()..sort()))
                      DropdownMenuItem(value: ms, child: Text('${ms / 1000}s')),
                  ],
                  onChanged: (v) {
                    if (v != null) notifier.setPerformanceIdleMs(v);
                  },
                ),
              ),
              SettingsItem(
                icon: Icons.history,
                title: 'Rolling Window',
                trailing: DropdownButton<int>(
                  value: settings.performanceWindowMs,
                  items: [
                    for (final ms in ({
                      settings.performanceWindowMs,
                      5000,
                      10000,
                      30000,
                      60000,
                    }.toList()..sort()))
                      DropdownMenuItem(
                        value: ms,
                        child: Text('${ms ~/ 1000}s'),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) notifier.setPerformanceWindowMs(v);
                  },
                ),
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final s =
                      controller.recorder.recentSnapshots[_reportScreen] ??
                      controller.snapshot;
                  final d = controller.display;
                  String n(double? v) => v?.toStringAsFixed(2) ?? 'unavailable';
                  return SelectableText(
                    [
                      'Screen: ${s.screen} • current: ${controller.recorder.screen}',
                      if (controller.recorder.recentSnapshots.containsKey(
                        _reportScreen,
                      ))
                        'Frozen previous-screen window',
                      'Original Mornye glass • ${controller.glassConfiguration}',
                      'Motion artwork preference: ${controller.motionArtworkEnabled ?? 'unavailable'} • active background: unavailable',
                      'Requested: ${n(d.number('requested_hz'))} Hz (preference only)',
                      'Reported active mode: ${n(d.hz)} Hz • ID ${d.values['active_mode_id'] ?? 'unavailable'}',
                      'Supported at current resolution: ${d.values['supported_hz'] ?? 'unavailable'}',
                      'Budget: ${n(d.budgetMs)} ms • transitions: ${d.transitions ?? 'unavailable'}',
                      'Rendered FPS: ${n(s.fps)} (includes idle)',
                      'Frames: ${s.frames.length} • window: ${n(s.durationMs)} ms',
                      for (final series in ['build', 'raster', 'span', 'gap'])
                        '$series ms P50/P90/P95/P99: ${[.5, .9, .95, .99].map((p) => n(s.percentile(series, p))).join(' / ')}',
                      'Longest gap: ${n(s.percentile('gap', 1))} ms',
                      'Jank: ${n(s.jankPercent)}% • slow frames: ${s.slow}',
                      'Slow = build or raster exceeds reported budget. Idle gaps are not jank.',
                      'First-interaction captures: ${controller.recorder.interactions.length}',
                      'See report for capture frames and timestamped display changes.',
                      'FrameTiming delivery may be batched; span is not presentation latency.',
                      'Mode preference does not guarantee physical refresh rate.',
                    ].join('\n'),
                    style: const TextStyle(height: 1.6),
                  );
                },
              ),
            ),
          ),
          ...settingsSectionSlivers(
            title: 'Statistics and report',
            children: [
              SettingsItem(
                icon: Icons.restart_alt,
                title: 'Reset Statistics',
                onTap: controller.reset,
              ),
              SettingsItem(
                icon: Icons.copy,
                title: 'Copy Performance Report',
                onTap: () async {
                  await Clipboard.setData(
                    ClipboardData(
                      text: controller.report(screen: _reportScreen),
                    ),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Performance report copied'),
                      ),
                    );
                  }
                },
              ),
              SettingsItem(
                icon: Icons.file_download_outlined,
                title: 'Export Performance Report',
                onTap: () async {
                  try {
                    await FilePicker.saveFile(
                      dialogTitle: 'Export Performance Report',
                      fileName: 'mornye-performance.txt',
                      bytes: Uint8List.fromList(
                        utf8.encode(controller.report(screen: _reportScreen)),
                      ),
                    );
                  } catch (error) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Could not export report: $error'),
                        ),
                      );
                    }
                  }
                },
              ),
            ],
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 120)),
        ],
      ),
    );
  }
}
