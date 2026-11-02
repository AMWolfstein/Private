/// A pass measures tracks, measures whole albums, then publishes each file once.
enum ReplayGainPhase {
  preparing,
  tracks,
  albums,
  writing,
  waitingForCharging,
  waitingForPlayback,
  completed,
  failed,
}

class ReplayGainProgress {
  const ReplayGainProgress({
    required this.phase,
    this.checked = 0,
    this.total = 0,
    this.written = 0,
    this.unchanged = 0,
    this.failed = 0,
    this.deferred = 0,
    this.completedUnits = 0,
    this.totalUnits = 0,
  });

  final ReplayGainPhase phase;
  final int checked, total, written, unchanged, failed, deferred;
  final int completedUnits, totalUnits;

  ReplayGainProgress withPhase(ReplayGainPhase phase) => ReplayGainProgress(
    phase: phase,
    checked: checked,
    total: total,
    written: written,
    unchanged: unchanged,
    failed: failed,
    deferred: deferred,
    completedUnits: completedUnits,
    totalUnits: totalUnits,
  );

  double? get fraction => totalUnits == 0
      ? (phase == ReplayGainPhase.completed ? 1 : null)
      : (completedUnits / totalUnits).clamp(
          0.0,
          phase == ReplayGainPhase.completed ? 1.0 : 0.99,
        );
}
