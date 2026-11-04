import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/widgets/primitives/app_surface.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';

/// The standard search field used by top-level app surfaces.
///
/// Keeping the decoration here prevents Settings, Store, and future search
/// surfaces from drifting into slightly different shapes and colors.
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    required this.clearTooltip,
    this.onChanged,
    required this.onClear,
    this.onSubmitted,

    this.suffixIcon,
    this.focusNode,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hintText;
  final String clearTooltip;
  final ValueChanged<String>? onChanged;
  final VoidCallback onClear;
  final ValueChanged<String>? onSubmitted;

  final Widget? suffixIcon;
  final FocusNode? focusNode;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final sistrum = context.isAppTheme;
    final radius = BorderRadius.circular(28);

    final field = ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) => TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hintText,
          prefixIcon: const Icon(CupertinoIcons.search),

          suffixIcon:
              suffixIcon ??
              (value.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: clearTooltip,
                      icon: Icon(
                        sistrum
                            ? CupertinoIcons.clear_circled_solid
                            : Icons.clear,
                      ),
                      onPressed: () {
                        controller.clear();
                        onClear();
                      },
                    )),
          border: OutlineInputBorder(
            borderRadius: radius,
            borderSide: sistrum
                ? BorderSide.none
                : BorderSide(color: colorScheme.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: sistrum
                ? BorderSide.none
                : BorderSide(color: colorScheme.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: radius,
            borderSide: sistrum
                ? BorderSide.none
                : BorderSide(color: colorScheme.primary, width: 2),
          ),
          filled: true,
          fillColor: sistrum ? Colors.transparent : settingsGroupColor(context),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 16,
          ),
        ),
        onChanged: onChanged,
        onSubmitted: onSubmitted,
        onTapOutside: (_) => FocusScope.of(context).unfocus(),
      ),
    );

    return AppSurface(radius: 28, child: field);
  }
}
