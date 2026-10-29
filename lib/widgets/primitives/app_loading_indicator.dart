import 'package:flutter/material.dart';

/// Indeterminate loading only. Downloads/analysis keep their real progress.
class AppLoadingIndicator extends StatelessWidget {
  const AppLoadingIndicator({
    super.key,
    this.size = 32,
    this.color,
    this.semanticLabel,
  });

  final double size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final animate =
        !MediaQuery.disableAnimationsOf(context) &&
        TickerMode.valuesOf(context).enabled;
    return SizedBox.square(
      dimension: size,
      child: TickerMode(
        enabled: animate,
        child: CircularProgressIndicator(
          color: color,
          strokeWidth: 3,
          semanticsLabel: semanticLabel,
        ),
      ),
    );
  }
}
