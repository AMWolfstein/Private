import 'dart:math';

import 'package:flutter/material.dart';

/// The original five-song artist carousel keeps discography close to the hero.
class ArtistSongPages extends StatefulWidget {
  const ArtistSongPages({
    super.key,
    required this.itemCount,
    required this.itemBuilder,
  });
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  @override
  State<ArtistSongPages> createState() => _ArtistSongPagesState();
}

class _ArtistSongPagesState extends State<ArtistSongPages> {
  final _pages = PageController();
  int _page = 0;
  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final count = (widget.itemCount / 5).ceil();
    final rowHeight =
        64 + max(0.0, MediaQuery.textScalerOf(context).scale(14) - 14) * 2;
    return Column(
      children: [
        SizedBox(
          height: min(widget.itemCount, 5) * rowHeight,
          child: PageView.builder(
            controller: _pages,
            itemCount: count,
            onPageChanged: (page) => setState(() => _page = page),
            itemBuilder: (context, page) => Column(
              children: [
                for (
                  var i = page * 5;
                  i < min(page * 5 + 5, widget.itemCount);
                  i++
                )
                  SizedBox(
                    height: rowHeight,
                    child: widget.itemBuilder(context, i),
                  ),
              ],
            ),
          ),
        ),
        if (count > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var page = 0; page < count; page++)
                  Semantics(
                    label: '${page + 1} / $count',
                    selected: _page == page,
                    button: true,
                    child: GestureDetector(
                      key: ValueKey('artist-popular-dot-$page'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _pages.animateToPage(
                        page,
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOut,
                      ),
                      // The painted dot stays 8dp; the touch target is 48dp.
                      child: SizedBox(
                        width: 48,
                        height: 48,
                        child: Center(
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _page == page
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context).colorScheme.onSurface
                                        .withValues(alpha: 0.25),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
