import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
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
    final waiting =
        current.phase == ReplayGainPhase.waitingForCharging ||
        current.phase == ReplayGainPhase.waitingForPlayback ||
        current.phase == ReplayGainPhase.failed;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 8),
          Text(l10n.replayGainProgress(current.checked, current.total)),
          Text(
            l10n.replayGainOutcomeCounts(
              current.written,
              current.unchanged,
              current.failed,
              current.deferred,
            ),
          ),
          if (!waiting) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: current.fraction,
              semanticsLabel: label,
            ),
          ],
        ],
      ),
    );
  }
}
