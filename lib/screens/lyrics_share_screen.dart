import 'dart:io';
import 'dart:ui' show ImageByteFormat;

import 'package:audio_service/audio_service.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderRepaintBoundary;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus, XFile;
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/services/library/cover_palette.dart';
import 'package:sistrum/utils/lyrics_parser.dart';
import 'package:sistrum/widgets/header/header_controls.dart';
import 'package:sistrum/providers/cover_palette_provider.dart';
import 'package:sistrum/screens/lyrics_share_card.dart';
import 'package:sistrum/screens/lyrics_share_controls.dart';

/// Lines a card can quote: timed lines in order, or the plain text's lines.
List<LyricsShareLine> lyricsShareLines(ParsedLyrics lyrics) {
  if (lyrics.lines.isNotEmpty) {
    return [
      for (final line in lyrics.lines)
        if (line.text.trim().isNotEmpty)
          (text: line.text.trim(), background: line.isBackground),
    ];
  }
  return [
    for (final line in lyrics.plainText.split(RegExp(r'\r\n|\r|\n')))
      if (line.trim().isNotEmpty) (text: line.trim(), background: false),
  ];
}

/// Opens the lyric card editor. [initial] preselects the line the user
/// long-pressed in the player.
Future<void> openLyricsShare(
  BuildContext context, {
  required MediaItem mediaItem,
  required ParsedLyrics lyrics,
  LyricLine? initial,
}) {
  final lines = lyricsShareLines(lyrics);
  var selected = -1;
  if (initial != null) {
    var row = 0;
    for (final line in lyrics.lines) {
      if (line.text.trim().isEmpty) continue;
      if (line.time == initial.time &&
          line.text.trim() == initial.text.trim()) {
        selected = row;
        break;
      }
      row++;
    }
  }
  return Navigator.of(context, rootNavigator: true).push(
    MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => LyricsShareScreen(
        mediaItem: mediaItem,
        lines: lines,
        initialSelection: {if (selected >= 0) selected},
      ),
    ),
  );
}

class LyricsShareScreen extends StatefulWidget {
  const LyricsShareScreen({
    super.key,
    required this.mediaItem,
    required this.lines,
    this.initialSelection = const {},
  });

  final MediaItem mediaItem;
  final List<LyricsShareLine> lines;
  final Set<int> initialSelection;

  @override
  State<LyricsShareScreen> createState() => _LyricsShareScreenState();
}

class _LyricsShareScreenState extends State<LyricsShareScreen> {
  final _cardKey = GlobalKey();
  final _shareButtonKey = GlobalKey();
  late final Set<int> _selected = {...widget.initialSelection};
  late final ScrollController _list = ScrollController(
    initialScrollOffset: widget.initialSelection.isEmpty
        ? 0
        : (widget.initialSelection.first - 2).clamp(0, 1 << 20) * 58.0,
  );
  LyricsCardBackground _background = LyricsCardBackground.artwork;
  bool _sharing = false;

  String? get _artSource {
    final art = widget.mediaItem.artUri;
    if (art == null ||
        (art.scheme.isNotEmpty &&
            art.scheme != 'file' &&
            art.scheme != 'content')) {
      return null;
    }
    return art.scheme == 'file' ? art.toFilePath() : art.toString();
  }

  @override
  void dispose() {
    _list.dispose();
    super.dispose();
  }

  void _toggle(int index) {
    setState(() {
      if (_selected.remove(index)) return;
      if (_selected.length >= lyricsShareMaxLines) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(context.l10n.lyricsShareLimit(lyricsShareMaxLines)),
            ),
          );
        return;
      }
      _selected.add(index);
    });
  }

  List<LyricsShareLine> get _quoted => [
    for (final index in _selected.toList()..sort()) widget.lines[index],
  ];

  Future<void> _share() async {
    if (_sharing || _selected.isEmpty) return;
    final l10n = context.l10n;
    final messenger = ScaffoldMessenger.of(context);
    final origin = _originOf(_shareButtonKey.currentContext);
    setState(() => _sharing = true);
    try {
      // A selection/background change can still be waiting for paint when
      // Share is tapped. Capture the current card after that frame finishes.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('Card is not laid out');
      final image = await boundary.toImage(pixelRatio: 3);
      final bytes = await image.toByteData(format: ImageByteFormat.png);
      image.dispose();
      if (bytes == null) throw StateError('Card could not be encoded');
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/sistrum_lyrics.png');
      await file.writeAsBytes(bytes.buffer.asUint8List(), flush: true);
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
          text: [
            widget.mediaItem.title,
            if ((widget.mediaItem.artist ?? '').trim().isNotEmpty)
              widget.mediaItem.artist!.trim(),
          ].join(' · '),
          sharePositionOrigin: origin,
        ),
      );
    } catch (_) {
      messenger.showSnackBar(SnackBar(content: Text(l10n.lyricsShareError)));
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  static Rect? _originOf(BuildContext? context) {
    final box = context?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final tokens = context.tokens;
    final l10n = context.l10n;
    final source = _artSource;
    return Scaffold(
      appBar: AppBar(
        leadingWidth: 64,
        leading: Padding(
          padding: const EdgeInsets.all(6),
          child: HeaderCircleButton(
            tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
            icon: CupertinoIcons.xmark,
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        title: Text(l10n.lyricsShareTitle),
      ),
      body: SafeArea(
        top: false,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final card = Padding(
              padding: EdgeInsets.symmetric(vertical: tokens.gapSm),
              child: Center(
                child: AspectRatio(
                  aspectRatio:
                      lyricsShareCardSize.width / lyricsShareCardSize.height,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      boxShadow: [
                        BoxShadow(
                          color: colors.shadow.withValues(alpha: 0.22),
                          blurRadius: 24,
                          offset: const Offset(0, 10),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(28),
                      child: FittedBox(
                        child: CoverPaletteBuilder(
                          palette: paletteOf(context),
                          imageSource: source,
                          builder: (context, _) => RepaintBoundary(
                            key: _cardKey,
                            child: LyricsShareCard(
                              title: widget.mediaItem.title,
                              artist: widget.mediaItem.artist ?? '',
                              artUri: widget.mediaItem.artUri?.toString(),
                              lines: _quoted,
                              background: _background,
                              coverColors: paletteOf(context).colors(source),
                              placeholder: l10n.lyricsShareSelectHint(
                                lyricsShareMaxLines,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
            final picker = Column(
              children: [
                Padding(
                  padding: EdgeInsets.fromLTRB(
                    tokens.gapLg,
                    tokens.gapSm,
                    tokens.gapLg,
                    tokens.gapSm,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          l10n.lyricsShareSelectHint(lyricsShareMaxLines),
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colors.onSurfaceVariant,
                          ),
                        ),
                      ),
                      SelectionCount(count: _selected.length),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _list,
                    padding: EdgeInsets.symmetric(horizontal: tokens.gapMd),
                    itemCount: widget.lines.length,
                    itemBuilder: (context, index) => LineChoice(
                      line: widget.lines[index],
                      selected: _selected.contains(index),
                      first: index == 0,
                      last: index == widget.lines.length - 1,
                      onTap: () => _toggle(index),
                    ),
                  ),
                ),
              ],
            );
            // Floating toolbar: background swatches beside the primary action.
            final toolbar = Padding(
              padding: EdgeInsets.fromLTRB(
                tokens.gapMd,
                tokens.gapSm,
                tokens.gapMd,
                tokens.gapMd,
              ),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  SizedBox(
                    // Four full-size swatch targets, plus the picker padding.
                    width: 204,
                    child: BackgroundPicker(
                      value: _background,
                      onChanged: (value) => setState(() => _background = value),
                    ),
                  ),
                  CupertinoButton.filled(
                    key: _shareButtonKey,
                    minimumSize: const Size(64, 56),
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    borderRadius: BorderRadius.circular(28),
                    onPressed: _selected.isEmpty || _sharing ? null : _share,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(CupertinoIcons.share, size: 22),
                        const SizedBox(width: 8),
                        Text(l10n.lyricsShareAction),
                      ],
                    ),
                  ),
                ],
              ),
            );
            // A landscape phone (or a very large text scale) leaves about one
            // row of height in the stacked layout, so the line picker moves to
            // the side of the preview instead.
            final short = constraints.maxHeight < 560;
            return Column(
              children: [
                Expanded(
                  child: short && constraints.maxWidth >= 600
                      ? Row(
                          children: [
                            Expanded(flex: 6, child: card),
                            Expanded(flex: 4, child: picker),
                          ],
                        )
                      : Column(
                          children: [
                            Expanded(flex: short ? 2 : 6, child: card),
                            Expanded(flex: short ? 5 : 4, child: picker),
                          ],
                        ),
                ),
                // The toolbar always gets the full window width and can wrap.
                toolbar,
              ],
            );
          },
        ),
      ),
    );
  }
}
