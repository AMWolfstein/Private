import 'package:flutter/rendering.dart';

/// Counts the backdrop blurs in one composited layer tree: each one reads the
/// page behind it. Used by the performance HUD.
int appCountBackdropReads(Layer? root) {
  var reads = 0;
  void visit(Layer layer) {
    if (layer is BackdropFilterLayer) reads++;
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
  return reads;
}
