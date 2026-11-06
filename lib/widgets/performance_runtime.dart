import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mornye/providers/performance_provider.dart';
import 'package:mornye/providers/settings_provider.dart';

class PerformanceRuntime extends ConsumerWidget {
  const PerformanceRuntime({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final flags = ref.watch(
      settingsProvider.select(
        (s) => (
          s.performanceMonitoring,
          s.performanceFirstInteraction,
          s.performanceHud,
        ),
      ),
    );
    final controller = ref.watch(performanceControllerProvider);
    final observe = flags.$1 && flags.$2;
    return Stack(
      fit: StackFit.passthrough,
      children: [
        Listener(
          onPointerDown: observe
              ? (event) => controller.pointer(event.timeStamp)
              : null,
          onPointerMove: observe
              ? (event) => controller.pointer(event.timeStamp)
              : null,
          onPointerSignal: observe
              ? (event) => controller.pointer(event.timeStamp)
              : null,
          child: child,
        ),
        if (flags.$1 && flags.$3)
          Positioned(
            top: MediaQuery.paddingOf(context).top + 8,
            right: 8,
            child: IgnorePointer(
              child: AnimatedBuilder(
                animation: controller,
                builder: (context, _) {
                  final s = controller.snapshot;
                  String n(double? value) => value?.toStringAsFixed(1) ?? '—';
                  return Material(
                    color: const Color(0xDD111111),
                    borderRadius: BorderRadius.circular(6),
                    child: Padding(
                      padding: const EdgeInsets.all(8),
                      child: Text(
                        '${n(s.fps)} FPS  ${n(controller.display.hz)} Hz\n'
                        'Build P95 ${n(s.percentile('build', .95))} ms\n'
                        'Raster P95 ${n(s.percentile('raster', .95))} ms\n'
                        'Jank ${n(s.jankPercent)}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}
