import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
// The package's own host mechanism for one batch spread over subtrees that
// no single widget can wrap (its scaffold uses it the same way). The package
// version is pinned, so these internal names are stable.
// ignore: implementation_imports
import 'package:liquid_glass_easy/src/widgets/lens/liquid_glass_batch.dart'
    show
        LiquidGlassBatchBackdropLayer,
        LiquidGlassBatchScope,
        liquidGlassAllocateBackdropId;

/// The shell's persistent chrome, split by what may overlap.
///
/// The engine caches the backdrop at the first member of a group that it
/// draws, and every later member filters that copy. A member therefore
/// cannot see glass of its own group, nor anything painted after the first
/// member. Two groups keep every overlap apart:
enum MornyeBackdropGroup {
  /// The header backing band, the tab bar capsule and the mini player.
  surface,

  /// The header back circle and action capsule, and the collapsed bar's side
  /// buttons. They float over the band and, while folding, over the tabs.
  controls,
}

/// Hands out one backdrop key per [MornyeBackdropGroup] for the chrome below
/// it, so blur passes and lenses of a group share one read of the page.
class MornyeBackdropGroups extends StatefulWidget {
  const MornyeBackdropGroups({super.key, required this.child});

  final Widget child;

  @override
  State<MornyeBackdropGroups> createState() => _MornyeBackdropGroupsState();
}

class _MornyeBackdropGroupsState extends State<MornyeBackdropGroups> {
  // Allocated from the package's namespace, so they never collide with a
  // LiquidGlassBatch or a framework BackdropGroup.
  late final _ids = [
    for (final _ in MornyeBackdropGroup.values) liquidGlassAllocateBackdropId(),
  ];

  @override
  Widget build(BuildContext context) =>
      _MornyeBackdropGroupsScope(ids: _ids, child: widget.child);
}

class _MornyeBackdropGroupsScope extends InheritedWidget {
  const _MornyeBackdropGroupsScope({required this.ids, required super.child});

  final List<int> ids;

  @override
  bool updateShouldNotify(_MornyeBackdropGroupsScope oldWidget) =>
      !identical(ids, oldWidget.ids);
}

/// Puts the glass in [child] on [group]'s shared backdrop read.
///
/// Outside [MornyeBackdropGroups] it changes nothing. With [followRoute],
/// the member reads on its own while its route is covered or moving: two
/// pages of one navigator paint together then, and the incoming page must
/// not filter the outgoing page's copy.
class MornyeBackdropGroupMember extends StatefulWidget {
  const MornyeBackdropGroupMember({
    super.key,
    required this.group,
    required this.child,
    this.followRoute = true,
  });

  final MornyeBackdropGroup group;
  final Widget child;
  final bool followRoute;

  @override
  State<MornyeBackdropGroupMember> createState() =>
      _MornyeBackdropGroupMemberState();
}

class _MornyeBackdropGroupMemberState extends State<MornyeBackdropGroupMember> {
  ModalRoute<Object?>? _route;
  bool _settled = true;

  bool get _routeSettled {
    final route = _route;
    if (route == null) return true;
    return route.isCurrent &&
        (route.animation?.status ?? AnimationStatus.completed) ==
            AnimationStatus.completed &&
        (route.secondaryAnimation?.status ?? AnimationStatus.dismissed) ==
            AnimationStatus.dismissed;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = widget.followRoute ? ModalRoute.of(context) : null;
    if (!identical(route, _route)) {
      _unlisten();
      _route = route;
      route?.animation?.addStatusListener(_onStatus);
      route?.secondaryAnimation?.addStatusListener(_onStatus);
    }
    _settled = _routeSettled;
  }

  void _onStatus(AnimationStatus _) {
    final settled = _routeSettled;
    if (settled != _settled && mounted) setState(() => _settled = settled);
  }

  void _unlisten() {
    _route?.animation?.removeStatusListener(_onStatus);
    _route?.secondaryAnimation?.removeStatusListener(_onStatus);
  }

  @override
  void dispose() {
    _unlisten();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_MornyeBackdropGroupsScope>();
    if (scope == null) return widget.child;
    return LiquidGlassBatchScope(
      backdropId: _settled ? scope.ids[widget.group.index] : null,
      child: widget.child,
    );
  }
}

/// A backdrop blur that carries an integer backdrop key, so it can share a
/// read with the package's lenses. A null [backdropId] is a read of its own.
///
/// It is a [BackdropFilter] for finders and diagnostics; only the pushed
/// layer differs.
class MornyeBackdropBlur extends BackdropFilter {
  const MornyeBackdropBlur({
    super.key,
    required ui.ImageFilter super.filter,
    super.child,
    this.backdropId,
  });

  final int? backdropId;

  @override
  RenderBackdropFilter createRenderObject(BuildContext context) =>
      _RenderMornyeBackdropBlur(blur: filter!, backdropId: backdropId);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBackdropFilter renderObject,
  ) {
    (renderObject as _RenderMornyeBackdropBlur)
      ..blur = filter!
      ..backdropId = backdropId;
  }
}

class _RenderMornyeBackdropBlur extends RenderBackdropFilter {
  _RenderMornyeBackdropBlur({required ui.ImageFilter blur, int? backdropId})
    : _blur = blur,
      _backdropId = backdropId,
      super(filter: blur);

  final _layer = LayerHandle<MornyeBackdropLayer>();

  ui.ImageFilter _blur;
  set blur(ui.ImageFilter value) {
    if (value == _blur) return;
    _blur = value;
    markNeedsPaint();
  }

  int? _backdropId;
  set backdropId(int? value) {
    if (value == _backdropId) return;
    _backdropId = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      _layer.layer = null;
      return;
    }
    final layer = _layer.layer ??= MornyeBackdropLayer();
    layer
      ..filter = _blur
      ..backdropId = _backdropId;
    context.pushLayer(
      layer,
      (context, offset) => context.paintChild(child, offset),
      offset,
    );
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }
}

/// The engine pass of [MornyeBackdropBlur].
class MornyeBackdropLayer extends ContainerLayer {
  ui.ImageFilter? _filter;
  ui.ImageFilter? get filter => _filter;
  set filter(ui.ImageFilter? value) {
    if (value == _filter) return;
    _filter = value;
    markNeedsAddToScene();
  }

  int? _backdropId;
  int? get backdropId => _backdropId;
  set backdropId(int? value) {
    if (value == _backdropId) return;
    _backdropId = value;
    // The key is baked into the engine layer; never reuse one across keys.
    engineLayer = null;
    markNeedsAddToScene();
  }

  @override
  void addToScene(ui.SceneBuilder builder) {
    final filter = _filter;
    if (filter == null) {
      addChildrenToScene(builder);
      return;
    }
    engineLayer = builder.pushBackdropFilter(
      filter,
      oldLayer: engineLayer as ui.BackdropFilterEngineLayer?,
      backdropId: _backdropId,
    );
    addChildrenToScene(builder);
    builder.pop();
  }
}

/// Marks a package lens's shader pass for [mornyeCountBackdropReads]; the
/// lens layer itself is private. It adds no engine layer.
class MornyeBackdropReadMarker extends SingleChildRenderObjectWidget {
  const MornyeBackdropReadMarker({
    super.key,
    required this.backdropId,
    super.child,
  });

  final int? backdropId;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMornyeBackdropReadMarker(backdropId);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderMornyeBackdropReadMarker).backdropId = backdropId;
  }
}

class _RenderMornyeBackdropReadMarker extends RenderProxyBox {
  _RenderMornyeBackdropReadMarker(this._backdropId);

  final _layer = LayerHandle<MornyeBackdropReadMarkerLayer>();

  int? _backdropId;
  set backdropId(int? value) {
    if (value == _backdropId) return;
    _backdropId = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => child != null;

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) {
      _layer.layer = null;
      return;
    }
    final layer = _layer.layer ??= MornyeBackdropReadMarkerLayer();
    layer.backdropId = _backdropId;
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }
}

/// See [MornyeBackdropReadMarker].
class MornyeBackdropReadMarkerLayer extends ContainerLayer {
  int? backdropId;
}

/// Backdrop reads in one composited frame: each unkeyed pass is a read, and
/// each shared key is one read however many passes use it.
@immutable
class MornyeBackdropReads {
  const MornyeBackdropReads({required this.own, required this.shared});

  /// Passes with a read of their own.
  final int own;

  /// Distinct shared keys.
  final int shared;

  int get total => own + shared;
}

/// Counts the reads under [root], the layer tree of the last frame.
MornyeBackdropReads mornyeCountBackdropReads(Layer? root) {
  var own = 0;
  final shared = <Object>{};
  void count(Object? key) => key == null ? own++ : shared.add(key);
  void visit(Layer layer) {
    switch (layer) {
      case MornyeBackdropLayer(filter: _?, :final backdropId):
        count(backdropId);
      case MornyeBackdropReadMarkerLayer(:final backdropId):
        count(backdropId);
      case LiquidGlassBatchBackdropLayer(filter: _?, :final backdropId):
        count(backdropId);
      case BackdropFilterLayer(:final backdropKey):
        count(backdropKey);
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
  return MornyeBackdropReads(own: own, shared: shared.length);
}
