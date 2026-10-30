import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/runtime_profile_provider.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/thumb/app_glass_surface.dart';
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
    this.samplesBackdrop = true,
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

  /// See [AppGlass.samplesBackdrop]: false where the field scrolls over
  /// the plain page background.
  final bool samplesBackdrop;

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

    return Consumer(
      builder: (context, ref, child) => AppGlass.navigation(
        radius: 28,
        blurEnabled: ref.watch(appBlurEnabledProvider),
        samplesBackdrop: samplesBackdrop,
        child: child!,
      ),
      child: field,
    );
  }
}
