import 'package:flutter/material.dart';
import 'package:mornye/widgets/app_icon.dart';
import 'package:mornye/widgets/track_card.dart';

/// End-to-start swipe that removes a track row over a delete background.
///
/// The background takes the row's [TrackCardSegment] corners. With expressive
/// motion the icon grows with the swipe and the fill deepens to the error
/// color once letting go would dismiss. Mornye and reduced motion keep the
/// static background.
class SwipeDeleteDismissible extends StatefulWidget {
  const SwipeDeleteDismissible({
    super.key,
    required this.dismissKey,
    required this.onDismissed,
    required this.child,
    this.confirmDismiss,
  });

  final Key dismissKey;
  final DismissDirectionCallback onDismissed;
  final ConfirmDismissCallback? confirmDismiss;
  final Widget child;

  @override
  State<SwipeDeleteDismissible> createState() => _SwipeDeleteDismissibleState();
}

class _SwipeDeleteDismissibleState extends State<SwipeDeleteDismissible> {
  static const _threshold = 0.4;
  final _swipe = ValueNotifier<DismissUpdateDetails?>(null);

  @override
  void dispose() {
    _swipe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final radius =
        TrackCardSegment.radiusOf(context) ?? BorderRadius.circular(12);
    final margin =
        TrackCardSegment.marginOf(context) ??
        const EdgeInsets.symmetric(horizontal: 16, vertical: 4);
    Widget background({required bool reached, required double progress}) {
      return AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: margin,
        decoration: BoxDecoration(
          color: reached ? colorScheme.error : colorScheme.errorContainer,
          borderRadius: radius,
        ),
        // The row slides toward the start, uncovering its end.
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: 20),
        child: Transform.scale(
          scale: 1,
          child: AppIcon(
            Icons.delete_outline,
            color: reached ? colorScheme.onError : colorScheme.onErrorContainer,
          ),
        ),
      );
    }

    return Dismissible(
      key: widget.dismissKey,
      direction: DismissDirection.endToStart,
      dismissThresholds: const {DismissDirection.endToStart: _threshold},
      confirmDismiss: widget.confirmDismiss,
      onDismissed: widget.onDismissed,
      onUpdate: null,
      background: background(reached: false, progress: _threshold),
      child: widget.child,
    );
  }
}
