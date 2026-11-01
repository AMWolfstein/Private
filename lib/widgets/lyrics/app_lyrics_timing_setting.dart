import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';
import 'package:sistrum/widgets/primitives/app_slider.dart';

class AppLyricsTimingSetting extends ConsumerWidget {
  const AppLyricsTimingSetting({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offset = ref.watch(
      themeProvider.select((s) => s.lyricsTimingOffsetMs),
    );
    final notifier = ref.read(themeProvider.notifier);
    final label =
        '${offset > 0 ? '+' : ''}${(offset / 1000).toStringAsFixed(1)} s';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.lyricsTimingOffset,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(label),
              IconButton(
                tooltip: context.l10n.libraryFilterReset,
                onPressed: offset == 0
                    ? null
                    : () => notifier.setLyricsTimingOffset(0),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          Text(context.l10n.lyricsTimingOffsetDescription),
          AppSlider(
            value: offset.toDouble(),
            min: -2000,
            max: 2000,
            divisions: 40,
            label: label,
            onChanged: (value) =>
                notifier.setLyricsTimingOffset(value.round(), persist: false),
            onChangeEnd: (value) =>
                notifier.setLyricsTimingOffset(value.round()),
          ),
        ],
      ),
    );
  }
}
