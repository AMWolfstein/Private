part of 'lyrics_parser.dart';

ParsedLyrics? _parseTtml(String text) {
  try {
    final doc = XmlDocument.parse(text);
    const metadataNamespace = 'http://www.w3.org/ns/ttml#metadata';
    final elements = doc.descendants.whereType<XmlElement>().toList();
    final paragraphs = elements.where((node) => node.name.local == 'p');
    if (paragraphs.isEmpty) return null;

    final voices = <String, LyricVoice>{};
    var individualIndex = 0;
    for (final agent in elements.where(
      (node) =>
          node.name.local == 'agent' &&
          node.name.namespaceUri == metadataNamespace,
    )) {
      final id = agent.getAttribute(
        'id',
        namespaceUri: 'http://www.w3.org/XML/1998/namespace',
      );
      if (id == null || id.isEmpty) continue;
      final group =
          agent.getAttribute('type') == 'group' || id.toLowerCase() == 'v3';
      voices[id] = LyricVoice(id: id, index: individualIndex, isGroup: group);
      if (!group) individualIndex++;
    }

    LyricVoice? voiceOf(XmlElement element, LyricVoice? inherited) {
      final id = element.getAttribute('agent', namespaceUri: metadataNamespace);
      if (id == null || id.isEmpty) return inherited;
      return voices.putIfAbsent(
        id,
        () => LyricVoice(
          id: id,
          index: individualIndex++,
          isGroup: id.toLowerCase() == 'v3',
        ),
      );
    }

    final lines = <LyricLine>[];
    final plain = <String>[];
    var sawWords = false;
    var nextVocalGroup = 0;

    for (final p in paragraphs) {
      final begin = _parseClock(p.getAttribute('begin'));
      final end = _parseClock(p.getAttribute('end'));

      LyricVoice? inheritedVoice;
      for (final ancestor
          in p.ancestors.whereType<XmlElement>().toList().reversed) {
        inheritedVoice = voiceOf(ancestor, inheritedVoice);
      }
      final runs = <_TtmlVocalRun>[];
      void visit(
        XmlNode node,
        LyricVoice? voice,
        bool background,
        Duration? wordBegin,
        Duration? wordEnd,
      ) {
        if (node is XmlText) {
          if (node.value.trim().isEmpty && runs.isEmpty) return;
          var run = runs
              .where(
                (run) =>
                    run.voice?.id == voice?.id && run.background == background,
              )
              .firstOrNull;
          if (run == null) {
            if (node.value.trim().isEmpty) return;
            run = _TtmlVocalRun(voice, background);
            runs.add(run);
          }
          run.add(node.value, wordBegin, wordEnd);
        } else if (node is XmlElement) {
          final nextVoice = voiceOf(node, voice);
          final nextBackground =
              background ||
              node.getAttribute('role', namespaceUri: metadataNamespace) ==
                  'x-bg';
          final spanBegin = node == p
              ? null
              : _parseClock(node.getAttribute('begin'));
          final spanEnd = node == p
              ? null
              : _parseClock(node.getAttribute('end'));
          for (final child in node.children) {
            visit(
              child,
              nextVoice,
              nextBackground,
              spanBegin ?? wordBegin,
              spanEnd ?? wordEnd,
            );
          }
        }
      }

      visit(p, inheritedVoice, false, null, null);
      final leadGroups = {
        for (final run in runs)
          if (!run.background && run.text.isNotEmpty) run: nextVocalGroup++,
      };
      for (final run in runs) {
        final lineText = run.text;
        if (lineText.isEmpty) continue;
        plain.add(lineText);
        final words = run.words;
        final lineBegin = runs.length == 1
            ? begin
            : words.firstOrNull?.time ?? begin;
        if (lineBegin == null) continue;
        sawWords |= words.isNotEmpty;
        final lead = run.background
            ? leadGroups.keys
                      .where((lead) => lead.voice?.id == run.voice?.id)
                      .firstOrNull ??
                  leadGroups.keys.firstOrNull
            : run;
        lines.add(
          LyricLine(
            time: lineBegin,
            end: runs.length == 1 ? end : words.lastOrNull?.end ?? end,
            text: lineText,
            words: words,
            voice: run.voice,
            isBackground: run.background,
            vocalGroup:
                leadGroups[lead] ??
                (run.background ? lines.lastOrNull?.vocalGroup : null),
          ),
        );
      }
    }

    if (lines.isEmpty) {
      return ParsedLyrics(
        synced: false,
        wordSynced: false,
        lines: const [],
        plainText: plain.join('\n'),
      );
    }

    _LyricsParserSupport._sortLines(lines);
    final synced = _LyricsParserSupport._hasUsableTiming(lines);
    return ParsedLyrics(
      synced: synced,
      wordSynced: synced && sawWords,
      lines: lines,
      plainText: plain.where((l) => l.isNotEmpty).join('\n'),
    );
  } catch (_) {
    return null;
  }
}

// TTML clock value: "mm:ss.fff", "hh:mm:ss.fff" or "12.5s".
Duration? _parseClock(String? value) {
  if (value == null || value.isEmpty) return null;
  final v = value.trim();

  if (v.endsWith('s') && !v.contains(':')) {
    final seconds = double.tryParse(v.substring(0, v.length - 1));
    if (seconds == null) return null;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  final parts = v.split(':');
  try {
    if (parts.length == 3) {
      final h = int.parse(parts[0]);
      final m = int.parse(parts[1]);
      final s = double.parse(parts[2]);
      return Duration(hours: h, minutes: m, milliseconds: (s * 1000).round());
    } else if (parts.length == 2) {
      final m = int.parse(parts[0]);
      final s = double.parse(parts[1]);
      return Duration(minutes: m, milliseconds: (s * 1000).round());
    }
  } catch (_) {
    return null;
  }
  return null;
}

class _TtmlVocalRun {
  final LyricVoice? voice;
  final bool background;
  final List<(String, Duration?, Duration?)> _fragments = [];

  _TtmlVocalRun(this.voice, this.background);

  void add(String value, Duration? begin, Duration? end) {
    var text = value.replaceAll(RegExp(r'\s+'), ' ');
    if (_fragments.isEmpty || _fragments.last.$1.endsWith(' ')) {
      text = text.trimLeft();
    }
    if (text.isEmpty) return;
    if (_fragments.isNotEmpty &&
        (text.trim().isEmpty ||
            (begin == _fragments.last.$2 && end == _fragments.last.$3))) {
      final previous = _fragments.removeLast();
      _fragments.add(('${previous.$1}$text', previous.$2, previous.$3));
    } else {
      _fragments.add((text, begin, end));
    }
  }

  String get text => _fragments.map((fragment) => fragment.$1).join().trim();

  List<LyricWord> get words {
    // Never drop untimed text from a partially timed paragraph.
    if (_fragments.any((fragment) => fragment.$2 == null)) return const [];
    return [
      for (var i = 0; i < _fragments.length; i++)
        LyricWord(
          time: _fragments[i].$2!,
          end:
              _fragments[i].$3 != null && _fragments[i].$3! >= _fragments[i].$2!
              ? _fragments[i].$3
              : null,
          text: i == _fragments.length - 1
              ? _fragments[i].$1.trimRight()
              : _fragments[i].$1,
        ),
    ];
  }
}
