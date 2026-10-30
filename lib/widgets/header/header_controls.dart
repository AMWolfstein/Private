import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/services/library/covers/cover_palette.dart';
import 'package:sistrum/theme/app_icons.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
import 'package:sistrum/widgets/glass/chrome/app_floating_header.dart';

class HeaderFilledButton extends StatelessWidget {
  const HeaderFilledButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tonal = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool tonal;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    {
      return AppHeaderButton(
        icon: appIconFor(icon),
        label: label,
        onPressed: onPressed,
        prominent: !tonal,
        compact: compact,
      );
    }
  }
}

/// Circular header icon button (add-to-playlist, love-all, ...). Sized to the
/// minimum touch target and tinted from the [HeaderPalette].
class HeaderCircleButton extends ConsumerWidget {
  const HeaderCircleButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.iconColor,
    this.tonal = false,
    this.buttonSize,
    this.iconSize = 22,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Overrides the palette foreground, e.g. to mark an active "loved" state.
  final Color? iconColor;

  /// Uses the same translucent fill as the local album's Play/Shuffle pills.
  final bool tonal;

  final double? buttonSize;
  final double iconSize;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = HeaderPalette.of(context);
    {
      if (tonal) {
        return Tooltip(
          message: tooltip,
          child: SizedBox.square(
            dimension: buttonSize ?? kAppHeaderControlSize,
            child: CupertinoButton(
              padding: EdgeInsets.zero,
              borderRadius: BorderRadius.circular(
                (buttonSize ?? kAppHeaderControlSize) / 2,
              ),
              color: scheme.onSurface.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.10 : 0.06,
              ),
              onPressed: onPressed,
              child: Icon(
                appIconFor(icon),
                size: iconSize,
                color: onPressed == null
                    ? scheme.onSurfaceVariant
                    : iconColor ?? scheme.primary,
              ),
            ),
          ),
        );
      }
      final blurEnabled = ref.watch(appBlurEnabledProvider);
      final button = IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(appIconFor(icon), size: iconSize),
        style: IconButton.styleFrom(
          minimumSize: Size.square(buttonSize ?? kAppHeaderControlSize),
          foregroundColor: iconColor ?? scheme.onSurface,
        ),
      );
      return Center(
        widthFactor: 1,
        child: AppGlass.navigation(
          radius: (buttonSize ?? kAppHeaderControlSize) / 2,
          tintColor: scheme.brightness == Brightness.dark
              ? Colors.black
              : Colors.white,
          tintOpacity: scheme.brightness == Brightness.dark ? 0.45 : 0.55,
          blurEnabled: blurEnabled,
          allowLens: appLiquidChromeEnabled(context, ref),
          child: button,
        ),
      );
    }
  }
}

class AppHeaderButton extends StatelessWidget {
  const AppHeaderButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.prominent = false,
    this.compact = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final bool prominent;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    final foreground = onPressed == null
        ? scheme.onSurfaceVariant
        : prominent
        ? scheme.onPrimary
        : scheme.primary;
    // The compact Play/Shuffle pills share the width with the Loved and
    // Add-to-playlist circles; at large text the labels no longer fit, so the
    // pills drop to icon-only and keep their accessible name.
    final iconOnly =
        compact && MediaQuery.textScalerOf(context).scale(1) >= 1.3;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: compact ? 48 : 50),
      child: CupertinoButton(
        padding: EdgeInsets.symmetric(
          horizontal: iconOnly ? 0 : (compact ? 6 : 16),
          vertical: 12,
        ),
        minimumSize: const Size(48, 48),
        borderRadius: BorderRadius.circular(28),
        color: prominent
            ? scheme.primary
            : scheme.onSurface.withValues(
                alpha: scheme.brightness == Brightness.dark ? 0.10 : 0.06,
              ),
        onPressed: onPressed,
        child: iconOnly
            ? Tooltip(
                message: label,
                child: Semantics(
                  label: label,
                  child: Icon(icon, size: 20, color: foreground),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: compact ? 18 : 20, color: foreground),
                  SizedBox(width: compact ? 4 : 8),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: compact ? 15 : 17,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// "•"-joined row of [HeaderMetaItem]s shown under the header subtitle
/// (track count, duration, quality, ...).
class HeaderMetaRow extends StatelessWidget {
  const HeaderMetaRow({super.key, required this.items});

  final List<Widget> items;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    final parts = <Widget>[];
    for (final item in items) {
      if (parts.isNotEmpty) {
        parts.add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              '•',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
            ),
          ),
        );
      }
      parts.add(item);
    }

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: parts,
    );
  }
}

/// Single meta label (optional leading icon) for [HeaderMetaRow].
class HeaderMetaItem extends StatelessWidget {
  const HeaderMetaItem(this.label, {super.key, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = HeaderPalette.of(context);
    final textStyle = TextStyle(
      color: scheme.onSurfaceVariant,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    );
    if (icon == null) return Text(label, style: textStyle);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: scheme.onSurface),
        const SizedBox(width: 4),
        Text(label, style: textStyle),
      ],
    );
  }
}
