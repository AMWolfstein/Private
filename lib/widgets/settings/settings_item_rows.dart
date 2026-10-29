import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/material.dart';
import 'package:sistrum/theme/app_icons.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/widgets/settings/settings_search_highlight.dart';

class SettingsItem extends StatelessWidget {
  final IconData? icon;
  final Color? iconColor;

  /// Show category icons in Sistrum's top-level settings and search results.
  final bool showIconInSistrum;
  final String title;
  final Widget? titleTrailing;
  final String? subtitle;

  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  const SettingsItem({
    super.key,
    this.icon,
    this.iconColor,
    this.showIconInSistrum = false,
    required this.title,
    this.titleTrailing,
    this.subtitle,

    this.trailing,
    this.onTap,
    this.showDivider = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final showIcon = icon != null && (showIconInSistrum);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          splashColor: colorScheme.primary.withValues(alpha: 0.12),
          highlightColor: Colors.transparent,
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: context.tokens.rowPaddingH,
              vertical: context.tokens.rowPaddingV,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: context.tokens.rowMinHeight,
              ),
              child: Row(
                children: [
                  if (showIcon) ...[
                    Icon(
                      context.adaptiveIcon(icon!),
                      color: iconColor ?? colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                    SizedBox(width: context.tokens.rowIconGap),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                            ),
                            if (titleTrailing != null) ...[
                              const SizedBox(width: 8),
                              titleTrailing!,
                            ],
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: (Theme.of(context).textTheme.bodySmall)
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                        ...[],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    trailing!,
                  ] else if (onTap != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      CupertinoIcons.forward,
                      size: context.tokens.rowChevronSize,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: showIcon
                ? context.tokens.rowIconDividerIndent
                : context.tokens.rowPaddingH,
            endIndent: context.tokens.rowPaddingH,
            color: colorScheme.outlineVariant,
          ),
      ],
    );
    return SettingsSearchTarget(label: title, child: content);
  }
}

class SettingsSwitchItem extends StatelessWidget {
  final IconData? icon;
  final String title;
  final Widget? titleTrailing;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool showDivider;
  final bool enabled;

  const SettingsSwitchItem({
    super.key,
    this.icon,
    required this.title,
    this.titleTrailing,
    this.subtitle,
    required this.value,
    this.onChanged,
    this.showDivider = true,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDisabled = !enabled || onChanged == null;
    final showIcon = icon != null && !context.isAppTheme;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Opacity(
          opacity: isDisabled ? 0.5 : 1.0,
          child: InkWell(
            onTap: isDisabled ? null : () => onChanged!(!value),
            splashColor: colorScheme.primary.withValues(alpha: 0.12),
            highlightColor: Colors.transparent,
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: context.tokens.rowPaddingH,
                vertical: context.tokens.rowPaddingVCompact,
              ),
              child: Row(
                children: [
                  if (showIcon) ...[
                    Icon(
                      icon,
                      color: isDisabled
                          ? colorScheme.outline
                          : colorScheme.onSurfaceVariant,
                      size: 24,
                    ),
                    SizedBox(width: context.tokens.rowIconGap),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Flexible(
                              child: Text(
                                title,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: isDisabled
                                          ? colorScheme.outline
                                          : null,
                                    ),
                              ),
                            ),
                            if (titleTrailing != null) ...[
                              const SizedBox(width: 8),
                              titleTrailing!,
                            ],
                          ],
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            subtitle!,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(
                                  color: isDisabled
                                      ? colorScheme.outline
                                      : colorScheme.onSurfaceVariant,
                                ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  AppSwitch(
                    value: value,
                    semanticLabel: title,
                    onChanged: isDisabled ? null : onChanged,
                  ),
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: showIcon
                ? context.tokens.rowIconDividerIndent
                : context.tokens.rowPaddingH,
            endIndent: context.tokens.rowPaddingH,
            color: colorScheme.outlineVariant,
          ),
      ],
    );
    return SettingsSearchTarget(label: title, child: content);
  }
}

class SettingsSectionHeader extends StatelessWidget {
  final String title;

  const SettingsSectionHeader({super.key, required this.title});

  @override
  Widget build(BuildContext context) {
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 8),
      child: Text(
        title,
        style: (Theme.of(context).textTheme.bodyLarge)?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
    return SettingsSearchTarget(label: title, child: content);
  }
}
