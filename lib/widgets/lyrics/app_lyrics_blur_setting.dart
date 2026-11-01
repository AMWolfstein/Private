import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/settings/theme_provider.dart';
import 'package:sistrum/widgets/primitives/app_slider.dart';

class AppLyricsBlurSetting extends ConsumerWidget {
  const AppLyricsBlurSetting({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strength = ref.watch(themeProvider.select((s) => s.lyricsBlur));
    final notifier = ref.read(themeProvider.notifier);
    String label(double value) =>
        value == 0 ? context.l10n.lyricsBlurOff : '${(value * 100).round()}%';
    final style = Theme.of(context).textTheme.headlineSmall;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.l10n.lyricsBlur,
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              Text(label(strength)),
              IconButton(
                tooltip: context.l10n.libraryFilterReset,
                onPressed: strength == 1
                    ? null
                    : () => notifier.setLyricsBlur(1),
                icon: const Icon(Icons.restart_alt),
              ),
            ],
          ),
          Text(
            context.l10n.lyricsBlurDescription,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          // A static preview uses the immediate neighbour's defocus; current
          // lyrics stay sharp. Semantics keep both lines readable without blur.
          Text(context.l10n.lyricsTextPreview, style: style),
          ImageFiltered(
            enabled: strength > 0 && !MediaQuery.highContrastOf(context),
            imageFilter: ImageFilter.blur(
              sigmaX: strength * 2.4,
              sigmaY: strength * 2.4,
            ),
            child: Text(
              context.l10n.lyricsTextPreview,
              style: style?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Semantics(
            label: context.l10n.lyricsBlur,
            child: AppSlider(
              value: strength,
              min: 0,
              max: 1.5,
              divisions: 15,
              label: label(strength),
              semanticFormatterCallback: label,
              onChanged: (value) =>
                  notifier.setLyricsBlur(value, persist: false),
              onChangeEnd: notifier.setLyricsBlur,
            ),
          ),
        ],
      ),
    );
  }
}
