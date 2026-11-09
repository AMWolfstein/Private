import 'package:flutter/material.dart';

/// Builds a horizontal list that scrolls with [controller].
typedef DesktopScrollArrowsBuilder =
    Widget Function(BuildContext context, ScrollController controller);

/// Hosts a horizontal list and owns its [ScrollController]. Phones and tablets
/// scroll the list by touch, so it is passed through unchanged.
class DesktopScrollArrows extends StatefulWidget {
  const DesktopScrollArrows({super.key, required this.builder});

  final DesktopScrollArrowsBuilder builder;

  @override
  State<DesktopScrollArrows> createState() => _DesktopScrollArrowsState();
}

class _DesktopScrollArrowsState extends State<DesktopScrollArrows> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _controller);
}
