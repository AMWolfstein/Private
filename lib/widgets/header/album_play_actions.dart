import 'package:flutter/cupertino.dart';
import 'package:sistrum/widgets/header/header_controls.dart';

/// Centered Play/Shuffle pills with optional outer Loved and playlist controls.
/// Colours and translucent fills follow the existing detail-header design.
class AlbumPlayActions extends StatelessWidget {
  const AlbumPlayActions({
    super.key,
    required this.playLabel,
    required this.shuffleTooltip,
    required this.onPlay,
    required this.onShuffle,
    this.isPlaying = false,
    this.leadingAction,
    this.trailingAction,
  });

  final String playLabel;
  final String shuffleTooltip;
  final VoidCallback onPlay;
  final VoidCallback onShuffle;
  final bool isPlaying;
  final Widget? leadingAction;
  final Widget? trailingAction;

  @override
  Widget build(BuildContext context) {
    {
      final compact = leadingAction != null || trailingAction != null;
      final gap = compact ? 6.0 : 12.0;
      return Row(
        textDirection: TextDirection.ltr,
        children: [
          if (leadingAction != null) ...[leadingAction!, SizedBox(width: gap)],
          Expanded(
            child: HeaderFilledButton(
              icon: isPlaying
                  ? CupertinoIcons.pause_fill
                  : CupertinoIcons.play_fill,
              label: playLabel,
              compact: compact,
              onPressed: onPlay,
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: AppHeaderButton(
              icon: CupertinoIcons.shuffle,
              label: shuffleTooltip,
              compact: compact,
              onPressed: onShuffle,
            ),
          ),
          if (trailingAction != null) ...[
            SizedBox(width: gap),
            trailingAction!,
          ],
        ],
      );
    }
  }
}
