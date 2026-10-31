part of 'player_lyrics.dart';

/// Visual order is separate from the chronological timeline: a backing part
/// stays directly under its lead, including when another singer starts first.
class LyricDisplayLayout {
  final List<int> lineOrder;
  final List<int> rowForLine;
  final List<int> leadForLine;
  final List<int> focusForLine;

  LyricDisplayLayout(List<LyricLine> lines)
    : lineOrder = [],
      rowForLine = List.filled(lines.length, 0),
      leadForLine = List.generate(lines.length, (index) => index),
      focusForLine = List.filled(lines.length, 0) {
    final leads = {
      for (var i = 0; i < lines.length; i++)
        if (!lines[i].isBackground && lines[i].vocalGroup != null)
          lines[i].vocalGroup!: i,
    };
    final backing = <int, List<int>>{};
    int? previousLead;
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (!line.isBackground) {
        if (line.text.isNotEmpty) previousLead = i;
        continue;
      }
      final lead = line.vocalGroup == null
          ? previousLead
          : leads[line.vocalGroup];
      if (lead == null) continue;
      leadForLine[i] = lead;
      backing.putIfAbsent(lead, () => []).add(i);
    }
    for (var i = 0; i < lines.length; i++) {
      if (leadForLine[i] != i) continue;
      lineOrder.add(i);
      lineOrder.addAll(backing[i] ?? const []);
    }
    for (var row = 0; row < lineOrder.length; row++) {
      rowForLine[lineOrder[row]] = row;
    }
    var latestLead = 0;
    Duration? latestLeadStart;
    for (var i = 0; i < lines.length; i++) {
      if (!lines[i].isBackground && lines[i].time != latestLeadStart) {
        latestLead = i;
        latestLeadStart = lines[i].time;
      }
      // Simultaneous leads share the first row as their scroll anchor, so the
      // earlier singer cannot be pushed above the viewport while still singing.
      // A delayed echo must not scroll backwards after the next lead starts.
      focusForLine[i] = lines[i].isBackground && leadForLine[i] > latestLead
          ? leadForLine[i]
          : latestLead;
    }
  }
}

/// Indexed playback queries retain overlapping voices without walking every
/// preceding line on each position report. Build once for a lyrics snapshot.
class LyricTimelineIndex {
  LyricTimelineIndex(this.lines)
    : starts = List.unmodifiable(lines.map((line) => line.time)),
      _heldLeads = List.filled(lines.length, -1) {
    var heldLead = -1;
    for (var index = 0; index < lines.length; index++) {
      final line = lines[index];
      if (!line.isBackground &&
          line.text.isNotEmpty &&
          (heldLead < 0 || line.time != lines[heldLead].time)) {
        heldLead = index;
      }
      _heldLeads[index] = heldLead;
    }
    while (_leafCount < lines.length) {
      _leafCount *= 2;
    }
    _latestEnds = List.filled(_leafCount * 2, null);
    for (var index = 0; index < lines.length; index++) {
      if (lines[index].text.isNotEmpty) {
        _latestEnds[_leafCount + index] = lines[index].end;
      }
    }
    for (var index = _leafCount - 1; index > 0; index--) {
      final left = _latestEnds[index * 2];
      final right = _latestEnds[index * 2 + 1];
      _latestEnds[index] = left == null || (right != null && right > left)
          ? right
          : left;
    }
  }

  final List<LyricLine> lines;
  final List<Duration> starts;
  final List<int> _heldLeads;
  int _leafCount = 1;
  late final List<Duration?> _latestEnds;

  Set<int> activeIndices(Duration position, int currentIndex) {
    if (currentIndex < 0) return {};
    final active = <int>{};
    void collect(int node, int start, int end) {
      final latestEnd = _latestEnds[node];
      if (start >= currentIndex || latestEnd == null || latestEnd <= position) {
        return;
      }
      if (end - start == 1) {
        active.add(start);
        return;
      }
      final middle = (start + end) ~/ 2;
      collect(node * 2, start, middle);
      collect(node * 2 + 1, middle, end);
    }

    collect(1, 0, _leafCount);
    final current = lines[currentIndex];
    final boundedVoice =
        (current.voice != null || current.isBackground) &&
        current.text.isNotEmpty &&
        current.end != null;
    if (!boundedVoice || current.end! > position) active.add(currentIndex);
    for (
      var index = currentIndex - 1;
      index >= 0 && lines[index].time == current.time;
      index--
    ) {
      if (lines[index].text.isNotEmpty && lines[index].end == null) {
        active.add(index);
      }
    }
    final heldLead = _heldLeads[currentIndex];
    if (heldLead >= 0) active.add(heldLead);
    return active;
  }
}
