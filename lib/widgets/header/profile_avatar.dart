import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/user_profile_provider.dart';
import 'package:sistrum/navigation/shell_navigation.dart';

class ProfileAvatar extends StatelessWidget {
  const ProfileAvatar({
    super.key,
    this.name = '',
    this.photoPath,
    this.photo,
    this.size = 40,
  });

  final String name;
  final String? photoPath;
  final Uint8List? photo;
  final double size;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // ListTile can constrain height more than width. Keep the clipped
        // image square even when the surrounding slot is rectangular.
        final diameter = constraints.biggest.shortestSide.clamp(0.0, size);
        return Align(
          widthFactor: 1,
          heightFactor: 1,
          child: _buildAvatar(context, diameter),
        );
      },
    );
  }

  Widget _buildAvatar(BuildContext context, double diameter) {
    final scheme = Theme.of(context).colorScheme;
    final fallback = ColoredBox(
      color: scheme.primaryContainer,
      child: Center(
        child: name.trim().isEmpty
            ? Icon(
                Icons.person,
                size: diameter * 0.55,
                color: scheme.onPrimaryContainer,
              )
            : Text(
                name.trim().characters.first.toUpperCase(),
                style: TextStyle(
                  fontSize: diameter * 0.42,
                  fontWeight: FontWeight.w600,
                  color: scheme.onPrimaryContainer,
                ),
              ),
      ),
    );
    return ExcludeSemantics(
      child: ClipOval(
        child: SizedBox.square(
          dimension: diameter,
          child: photo != null
              ? Image.memory(
                  photo!,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => fallback,
                )
              : photoPath != null
              ? Image.file(
                  File(photoPath!),
                  fit: BoxFit.cover,
                  cacheWidth:
                      (diameter * MediaQuery.devicePixelRatioOf(context))
                          .ceil(),
                  errorBuilder: (_, _, _) => fallback,
                )
              : fallback,
        ),
      ),
    );
  }
}

/// The header profile photo that opens Settings. Sits at the trailing end of
/// every pinned header, [gap] after the actions before it, and hides itself
/// on Settings and the pages Settings opens (and outside the shell).
class HeaderProfileButton extends StatelessWidget {
  const HeaderProfileButton({super.key, this.gap = 0});

  final double gap;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: ShellNavigationService.settingsOpen,
      builder: (context, settingsOpen, _) {
        final hidden =
            !ShellNavigationService.hasTabSelectionHandler ||
            (settingsOpen &&
                !ShellNavigationService.isTabNavigator(
                  Navigator.maybeOf(context),
                ));
        if (hidden) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsetsDirectional.only(start: gap),
          child: const HomeProfileButton(),
        );
      },
    );
  }
}

/// The profile photo, 48dp, outlined like the header glass rim.
class HomeProfileButton extends ConsumerWidget {
  const HomeProfileButton({super.key});

  static const double _size = 48;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).value;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return IconButton(
      tooltip: context.l10n.settingsTitle,
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        minimumSize: const Size.square(_size),
        fixedSize: const Size.square(_size),
        iconSize: _size,
      ),
      onPressed: () => ShellNavigationService.requestTab(ShellTab.settings),
      icon: CustomPaint(
        foregroundPainter: _ProfileRim(dark: dark),
        child: ProfileAvatar(
          name: profile?.name ?? '',
          photoPath: profile?.photoPath,
          size: _size,
        ),
      ),
    );
  }
}

/// The glass rim's contact stroke and top/bottom highlight, on a circle.
class _ProfileRim extends CustomPainter {
  const _ProfileRim({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final center = bounds.center;
    final radius = size.shortestSide / 2;
    canvas.drawCircle(
      center,
      radius - 0.25,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.5
        ..color = Colors.black.withValues(alpha: dark ? 0.5 : 0.16),
    );
    canvas.drawCircle(
      center,
      radius - 0.8,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.6
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          stops: [0, 0.14, 0.5, 0.86, 1],
          colors: [
            Color(0x40ffffff),
            Color(0x0dffffff),
            Color(0x0a000000),
            Color(0x0dffffff),
            Color(0x26ffffff),
          ],
        ).createShader(bounds),
    );
  }

  @override
  bool shouldRepaint(covariant _ProfileRim oldDelegate) =>
      dark != oldDelegate.dark;
}
