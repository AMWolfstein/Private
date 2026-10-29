import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sistrum/theme/app_tokens.dart';

/// Carries a Settings search result into its destination page.
///
/// Descendant [SettingsSearchTarget] widgets compete to claim the matching
/// label. The first match scrolls into view and briefly highlights itself.
class SettingsSearchHighlightScope extends StatefulWidget {
  const SettingsSearchHighlightScope({
    super.key,
    required this.targetLabel,
    required this.child,
  });

  final String targetLabel;
  final Widget child;

  @override
  State<SettingsSearchHighlightScope> createState() =>
      _SettingsSearchHighlightScopeState();
}

class _SettingsSearchHighlightScopeState
    extends State<SettingsSearchHighlightScope> {
  late _SettingsSearchHighlightController _controller;

  @override
  void initState() {
    super.initState();
    _controller = _SettingsSearchHighlightController(widget.targetLabel);
  }

  @override
  void didUpdateWidget(SettingsSearchHighlightScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.targetLabel != widget.targetLabel) {
      _controller = _SettingsSearchHighlightController(widget.targetLabel);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _SettingsSearchHighlightInherited(
      controller: _controller,
      child: widget.child,
    );
  }
}

class _SettingsSearchHighlightController {
  _SettingsSearchHighlightController(this.targetLabel);

  final String targetLabel;
  bool _claimed = false;

  bool matches(String label) => label == targetLabel;

  bool claim(String label) {
    if (_claimed || !matches(label)) return false;
    _claimed = true;
    return true;
  }
}

class _SettingsSearchHighlightInherited extends InheritedWidget {
  const _SettingsSearchHighlightInherited({
    required this.controller,
    required super.child,
  });

  final _SettingsSearchHighlightController controller;

  static _SettingsSearchHighlightInherited? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<
          _SettingsSearchHighlightInherited
        >();
  }

  @override
  bool updateShouldNotify(_SettingsSearchHighlightInherited oldWidget) {
    return controller != oldWidget.controller;
  }
}

/// Marks one settings control as a possible deep-link target from search.
class SettingsSearchTarget extends StatefulWidget {
  const SettingsSearchTarget({
    super.key,
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  State<SettingsSearchTarget> createState() => _SettingsSearchTargetState();
}

class _SettingsSearchTargetState extends State<SettingsSearchTarget> {
  Timer? _highlightTimer;
  bool _handled = false;
  bool _highlighted = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_handled) return;

    final scope = _SettingsSearchHighlightInherited.maybeOf(context);
    if (scope?.controller.claim(widget.label) != true) return;
    _handled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  Future<void> _reveal() async {
    if (!mounted) return;
    setState(() => _highlighted = true);

    await Scrollable.ensureVisible(
      context,
      alignment: 0.32,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 480),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;

    _highlightTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _highlighted = false);
    });
  }

  @override
  void dispose() {
    _highlightTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Normal settings rendering stays allocation-light: only the one claimed
    // search target creates an animated decoration and semantics node.
    if (!_handled) return widget.child;

    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: _highlighted,
      child: AnimatedContainer(
        key: ValueKey('settings-highlight:${widget.label}'),
        duration: context.tokens.motionMedium,
        curve: Curves.easeOutCubic,
        color: _highlighted
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : Colors.transparent,
        child: widget.child,
      ),
    );
  }
}
