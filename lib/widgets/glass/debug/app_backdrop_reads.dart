import 'package:flutter/rendering.dart';

/// Counts the backdrop blurs in one composited layer tree: each one reads the
/// page behind it. Used by the performance HUD.
int appCountBackdropReads(Layer? root) => appCountBackdrops(root).reads;

/// The backdrop blurs in one composited layer tree ([reads]) and the copies of
/// the page the engine makes for them ([copies]): blurs that share a
/// [BackdropKey] share one copy.
({int reads, int copies}) appCountBackdrops(Layer? root) {
  var reads = 0;
  var unkeyed = 0;
  final keys = <BackdropKey>{};
  void visit(Layer layer) {
    if (layer is BackdropFilterLayer) {
      reads++;
      final key = layer.backdropKey;
      if (key == null) {
        unkeyed++;
      } else {
        keys.add(key);
      }
    }
    if (layer is ContainerLayer) {
      for (
        var child = layer.firstChild;
        child != null;
        child = child.nextSibling
      ) {
        visit(child);
      }
    }
  }

  if (root != null) visit(root);
  return (reads: reads, copies: unkeyed + keys.length);
}
