import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/services/playback/audio/replaygain_progress.dart';

class AppReplayGainProgressView extends StatelessWidget {
  const AppReplayGainProgressView({super.key, required this.progress});
  final ReplayGainProgress? progress;

  @override
  Widget build(BuildContext context) {
    final current = progress;
    if (current == null) return const SizedBox.shrink();
    final l10n = context.l10n;
    final label = switch (current.phase) {
      ReplayGainPhase.preparing => l10n.replayGainPreparing,
      ReplayGainPhase.tracks => l10n.replayGainMeasuringTracks,
      ReplayGainPhase.albums => l10n.replayGainMeasuringAlbums,
      ReplayGainPhase.writing => l10n.replayGainWritingTags,
      ReplayGainPhase.waitingForCharging => l10n.replayGainWaitingForCharging,
      ReplayGainPhase.waitingForPlayback => l10n.replayGainWaitingForPlayback,
      ReplayGainPhase.completed =>
        current.failed > 0
            ? l10n.replayGainFinishedWithErrors
            : l10n.replayGainFinished,
      ReplayGainPhase.failed => l10n.replayGainStoppedWithError,
    };
    final supportingStyle = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: Theme.of(context).colorScheme.onSurfaceVariant,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsItem(
          title: label,
          subtitle: l10n.replayGainProgress(current.checked, current.total),
          showDivider: false,
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  Text(
                    l10n.replayGainWrittenCount(current.written),
                    style: supportingStyle,
                  ),
                  Text(
                    l10n.replayGainUnchangedCount(current.unchanged),
                    style: supportingStyle,
                  ),
                  Text(
                    l10n.replayGainFailedCount(current.failed),
                    style: supportingStyle,
                  ),
                  Text(
                    l10n.replayGainDeferredCount(current.deferred),
                    style: supportingStyle,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: current.phase == ReplayGainPhase.preparing
                    ? current.fraction
                    : current.fraction ?? 0,
                semanticsLabel: label,
              ),
            ],
          ),
        ),
      ],
    );
  }
}
