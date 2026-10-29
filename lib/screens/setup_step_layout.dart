import 'package:flutter/material.dart';

// Height of the back-button/progress header row above the PageView
// (16 vertical padding * 2 + 48 button).
const kSetupHeaderHeight = 80.0;

class SetupStepLayout extends StatelessWidget {
  final String title;
  final String description;
  final IconData icon;
  final Widget child;

  const SetupStepLayout({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        final shortestSide = MediaQuery.sizeOf(context).shortestSide;
        final iconPadding = (shortestSide * 0.06).clamp(16.0, 24.0);
        final iconSize = (shortestSide * 0.12).clamp(32.0, 48.0);
        final titleGap = (shortestSide * 0.06).clamp(16.0, 32.0);
        final descriptionGap = (shortestSide * 0.04).clamp(8.0, 16.0);
        final actionGap = (shortestSide * 0.09).clamp(20.0, 48.0);
        // Extra bottom padding offsets the 80dp header above the PageView so
        // the content sits at the optical center of the full screen.
        const totalPadding = 48.0 + kSetupHeaderHeight;
        final minContentHeight = constraints.maxHeight > totalPadding
            ? constraints.maxHeight - totalPadding
            : 0.0;

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            24,
            24,
            24,
            24 + kSetupHeaderHeight,
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: minContentHeight,
                maxWidth: 560,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: EdgeInsets.all(iconPadding),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: iconSize,
                      color: colorScheme.primary,
                    ),
                  ),
                  SizedBox(height: titleGap),
                  Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: descriptionGap),
                  Text(
                    description,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  SizedBox(height: actionGap),
                  child,
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class SetupSuccessCard extends StatelessWidget {
  final String text;
  final ColorScheme colorScheme;

  const SetupSuccessCard({
    super.key,
    required this.text,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: colorScheme.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: colorScheme.onPrimaryContainer,
              ),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
