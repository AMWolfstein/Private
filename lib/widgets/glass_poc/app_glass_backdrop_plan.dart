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

/// Splits a shared group whose members would hand the engine *equal* filters
/// that are not translation-invariant (the lens shader).
///
/// Impeller processes a shared backdrop once over the whole cached texture
/// when every filter on the key is equal (`all_filters_equal` in
/// impeller/display_list/canvas.cc; a runtime-effect filter is equal when its
/// effect and uniforms are). That is correct for a blur but not for the lens,
/// whose geometry comes from the input size. A member whose [identities]
/// entry repeats an earlier member of its group gets a group of its own, so a
/// shared group never holds two equal lens filters.
List<int> appGlassSplitEqualFilters(List<int> groups, List<Object> identities) {
  if (groups.length != identities.length) {
    throw ArgumentError('Every surface needs a filter identity');
  }
  var next = groups.isEmpty ? 0 : groups.reduce((a, b) => a > b ? a : b) + 1;
  final seen = <String>{};
  return [
    for (var i = 0; i < groups.length; i++)
      seen.add('${groups[i]}|${identities[i]}') ? groups[i] : next++,
  ];
}
