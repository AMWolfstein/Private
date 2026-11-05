import 'dart:ui';

/// Backdrop assignment in paint order. A shared capture is taken before its
/// first member. A later member may reuse it only when none of the content
/// painted since then can enter that member's sampling region.
///
/// This POC has no interleaved content except the four surfaces and their
/// foregrounds. Callers must include blur/refraction reach in [samplingBounds]
/// and all foreground/effect outsets in [paintBounds]. Nested glass or extra
/// interleaved content must be represented too, or kept independent.
List<int> appGlassBackdropGroups({
  required List<Rect> paintBounds,
  required List<Rect> samplingBounds,
}) {
  if (paintBounds.length != samplingBounds.length) {
    throw ArgumentError(
      'Paint and sampling bounds must describe every surface',
    );
  }
  final firstMembers = <int>[];
  final groups = <int>[];
  for (var current = 0; current < paintBounds.length; current++) {
    final sample = samplingBounds[current];
    var group = -1;
    if (sample.isFinite && !sample.isEmpty) {
      for (var candidate = 0; candidate < firstMembers.length; candidate++) {
        var safe = true;
        for (var prior = firstMembers[candidate]; prior < current; prior++) {
          final painted = paintBounds[prior];
          if (!painted.isFinite || sample.overlaps(painted)) {
            safe = false;
            break;
          }
        }
        if (safe) {
          group = candidate;
          break;
        }
      }
    }
    if (group < 0) {
      group = firstMembers.length;
      firstMembers.add(current);
    }
    groups.add(group);
  }
  return groups;
}
