import 'package:flutter/material.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/widgets/scroll_edge_fade.dart';
import 'package:spotiflac_android/widgets/app_search_field.dart';

const localGuidePageCount = 5;

/// Local playback tips embedded in the single first-run setup flow.
List<Widget> buildLocalGuidePages(
  BuildContext context, {
  required int firstIndex,
  required int currentIndex,
}) {
  final l10n = context.l10n;
  return [
    _TutorialPage(
      index: firstIndex,
      currentIndex: currentIndex,
      icon: Icons.search_rounded,
      title: l10n.tutorialSearchTitle,
      description: l10n.tutorialSearchDesc,
      content: const _InteractiveSearchExample(),
    ),
    _TutorialPage(
      index: firstIndex + 1,
      currentIndex: currentIndex,
      icon: Icons.play_arrow_rounded,
      title: l10n.tutorialPlaybackTitle,
      description: l10n.tutorialPlaybackDesc,
      content: _buildFeatureList(context, [
        (Icons.play_arrow, l10n.tutorialPlaybackTip1),
        (Icons.queue_music, l10n.tutorialPlaybackTip2),
        (Icons.lyrics_outlined, l10n.tutorialPlaybackTip3),
      ]),
    ),
    _TutorialPage(
      index: firstIndex + 2,
      currentIndex: currentIndex,
      icon: Icons.library_music_rounded,
      title: l10n.tutorialLibraryTitle,
      description: l10n.tutorialLibraryDesc,
      content: _buildFeatureList(context, [
        (Icons.queue_music_rounded, l10n.tutorialLibraryTip1),
        (Icons.play_circle_fill, l10n.tutorialLibraryTip2),
        (Icons.grid_view_rounded, l10n.tutorialLibraryTip3),
      ]),
    ),
    _TutorialPage(
      index: firstIndex + 3,
      currentIndex: currentIndex,
      icon: Icons.folder_open_rounded,
      title: l10n.tutorialStorageTitle,
      description: l10n.tutorialStorageDesc,
      content: _buildFeatureList(context, [
        (Icons.folder_open_rounded, l10n.tutorialStorageTip1),
        (Icons.add_circle_outline_rounded, l10n.tutorialStorageTip2),
        (Icons.sync_rounded, l10n.tutorialStorageTip3),
      ]),
    ),
    _TutorialPage(
      index: firstIndex + 4,
      currentIndex: currentIndex,
      icon: Icons.settings_rounded,
      title: l10n.tutorialSettingsTitle,
      description: l10n.tutorialSettingsDesc,
      content: Column(
        children: [
          _buildFeatureList(context, [
            (Icons.folder_open_rounded, l10n.tutorialSettingsTip1),
            (Icons.tune_rounded, l10n.tutorialSettingsTip2),
            (Icons.palette_rounded, l10n.tutorialSettingsTip3),
          ]),
          const SizedBox(height: 24),
          _AnimatedReadyCard(text: l10n.tutorialReadyMessage),
        ],
      ),
    ),
  ];
}

Widget _buildFeatureList(
  BuildContext context,
  List<(IconData, String)> features,
) {
  final colorScheme = Theme.of(context).colorScheme;
  final reduceMotion = MediaQuery.disableAnimationsOf(context);
  return Column(
    children: features.asMap().entries.map((entry) {
      final index = entry.key;
      final feature = entry.value;
      return TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: reduceMotion
            ? Duration.zero
            : Duration(milliseconds: 600 + (index * 200)),
        curve: Curves.easeOutQuart,
        builder: (context, value, child) {
          return Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: Opacity(
              opacity: value,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        feature.$1,
                        size: 24,
                        color: colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 20),
                    Expanded(
                      child: Text(
                        feature.$2,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurface,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }).toList(),
  );
}

class _AnimatedReadyCard extends StatelessWidget {
  final String text;
  const _AnimatedReadyCard({required this.text});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(28),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_rounded,
            color: colorScheme.onPrimaryContainer,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractiveSearchExample extends StatefulWidget {
  const _InteractiveSearchExample();

  @override
  State<_InteractiveSearchExample> createState() =>
      _InteractiveSearchExampleState();
}

class _InteractiveSearchExampleState extends State<_InteractiveSearchExample> {
  final TextEditingController _controller = TextEditingController();
  bool _showResult = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppSearchField(
            controller: _controller,
            hintText: context.l10n.tutorialSearchHint,
            clearTooltip: context.l10n.dialogClear,
            onClear: () => setState(() => _showResult = false),
            onChanged: (value) {
              setState(() {
                _showResult = value.isNotEmpty;
              });
            },
          ),

          AnimatedSize(
            duration: MediaQuery.disableAnimationsOf(context)
                ? Duration.zero
                : const Duration(milliseconds: 400),
            curve: Curves.easeOutBack,
            child: _showResult
                ? Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.05),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(
                              Icons.music_note_rounded,
                              color: colorScheme.onPrimaryContainer,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  width: double.infinity,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.1,
                                    ),
                                    borderRadius: BorderRadius.circular(7),
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  width: 100,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    color: colorScheme.onSurfaceVariant
                                        .withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.play_arrow_rounded,
                            color: colorScheme.primary,
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _TutorialPage extends StatelessWidget {
  final int index;
  final int currentIndex;
  final IconData icon;
  final String title;
  final String description;
  final Widget content;

  const _TutorialPage({
    required this.index,
    required this.currentIndex,
    required this.icon,
    required this.title,
    required this.description,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shortestSide = MediaQuery.sizeOf(context).shortestSide;
    final textScale = MediaQuery.textScalerOf(
      context,
    ).scale(1.0).clamp(1.0, 1.4);
    final scale = (shortestSide / 390).clamp(0.86, 1.05);

    final isActive = currentIndex == index;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Shrink vertical rhythm on short viewports so a page fits with
        // little or no scrolling.
        final heightScale = (constraints.maxHeight / 640).clamp(0.6, 1.0);
        final topGap = (24 * scale).clamp(16.0, 24.0) * heightScale;
        final iconPadding = (24 * scale).clamp(18.0, 24.0) * heightScale;
        final iconSize = (56 * scale).clamp(44.0, 56.0) * heightScale;
        final iconTextGap = (48 * scale).clamp(28.0, 48.0) * heightScale;
        final descriptionGap = (20 * scale).clamp(12.0, 20.0) * heightScale;
        final contentGap =
            ((56 * scale) + ((textScale - 1) * 10)) * heightScale;
        final bottomGap = (32 * scale).clamp(20.0, 32.0) * heightScale;

        return ScrollEdgeFade(
          child: SingleChildScrollView(
            // 24 + the setup header height, matching the other steps so the
            // floating Next button never covers the last tip or Ready card.
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 104),
            physics: const BouncingScrollPhysics(),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Column(
                  children: [
                    SizedBox(height: topGap),
                    AnimatedContainer(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 500),
                      curve: Curves.easeOutBack,
                      transform: Matrix4.translationValues(
                        0,
                        isActive ? 0 : -20,
                        0,
                      ),
                      padding: EdgeInsets.all(iconPadding),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        icon,
                        size: iconSize,
                        color: colorScheme.primary,
                      ),
                    ),
                    SizedBox(height: iconTextGap),
                    AnimatedOpacity(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 500),
                      opacity: isActive ? 1.0 : 0.0,
                      curve: Curves.easeOut,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.headlineLarge
                            ?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                              letterSpacing: -0.5,
                            ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: descriptionGap),
                    AnimatedOpacity(
                      duration: MediaQuery.disableAnimationsOf(context)
                          ? Duration.zero
                          : const Duration(milliseconds: 500),
                      opacity: isActive ? 1.0 : 0.0,
                      curve: Curves.easeOut,
                      child: Text(
                        description,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          height: 1.5,
                          fontSize: 16 * (1 + ((textScale - 1) * 0.1)),
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    SizedBox(height: contentGap),
                    content, // The content itself now handles its own internal animations
                    SizedBox(height: bottomGap),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
