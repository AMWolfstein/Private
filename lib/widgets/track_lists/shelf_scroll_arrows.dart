import 'package:flutter/material.dart';

/// Builds a horizontal list that scrolls with [controller].
typedef ShelfScrollArrowsBuilder =
    Widget Function(BuildContext context, ScrollController controller);

/// Hosts a horizontal list and owns its [ScrollController]. Phones and tablets
/// scroll the list by touch, so it is passed through unchanged.
class ShelfScrollArrows extends StatefulWidget {
  const ShelfScrollArrows({super.key, required this.builder});

  final ShelfScrollArrowsBuilder builder;

  @override
  State<ShelfScrollArrows> createState() => _ShelfScrollArrowsState();
}

class _ShelfScrollArrowsState extends State<ShelfScrollArrows> {
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
