import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

/// One [LiquidGlassBatch] over the shell's pages and bottom bar, so the
/// persistent chrome shares a single backdrop read.
///
/// The engine caches the backdrop at the first member it draws, and every
/// later member filters that copy: a member cannot see glass of the batch,
/// nor anything painted after the first member. So the batch is opt-in:
/// only [SistrumChromeMember] subtrees join. Every other glass below it
/// (page content, sheets, dialogs on a tab navigator) reads on its own, and
/// glass that overlaps chrome (the header band under the controls) stays
/// out explicitly.
class SistrumChromeBatch extends StatelessWidget {
  const SistrumChromeBatch({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LiquidGlassBatch(
    child: Builder(
      // The package allocates the key; it is only read here.
      builder: (context) => _SistrumChromeBatchScope(
        backdropId: LiquidGlassBatch.backdropIdOf(context),
        child: child,
      ),
    ),
  );
}

class _SistrumChromeBatchScope extends InheritedWidget {
  const _SistrumChromeBatchScope({
    required this.backdropId,
    required super.child,
  });

  final int? backdropId;

  @override
  bool updateShouldNotify(_SistrumChromeBatchScope oldWidget) =>
      backdropId != oldWidget.backdropId;
}

/// Marks persistent chrome that joins [SistrumChromeBatch].
///
/// With [followRoute], the member reads on its own while its route is
/// covered or moving: two pages paint together then, and the incoming page
/// must not filter the outgoing page's copy. [join] false keeps it out for
/// the moment, e.g. bar buttons crossing the tabs while they fold.
class SistrumChromeMember extends StatefulWidget {
  const SistrumChromeMember({
    super.key,
    required this.child,
    this.followRoute = true,
    this.join = true,
  });

  final Widget child;
  final bool followRoute;
  final bool join;

  @override
  State<SistrumChromeMember> createState() => _SistrumChromeMemberState();
}

class _SistrumChromeMemberState extends State<SistrumChromeMember> {
  // Joining and leaving move the subtree under or out of an exclusion;
  // the key carries its state across.
  final _subtree = GlobalKey();
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
    final child = _SistrumChromeMemberScope(
      child: KeyedSubtree(key: _subtree, child: widget.child),
    );
    return widget.join && _settled
        ? child
        : LiquidGlassBatch.exclude(child: child);
  }
}

class _SistrumChromeMemberScope extends InheritedWidget {
  const _SistrumChromeMemberScope({required super.child});

  @override
  bool updateShouldNotify(_SistrumChromeMemberScope oldWidget) => false;
}

/// Whether glass at [context] sits in [SistrumChromeBatch] without being
/// chrome. It must then read on its own: wrap its lens in
/// [LiquidGlassBatch.exclude] and give its blur no key.
bool sistrumOutsideChromeBatch(BuildContext context) {
  final id = LiquidGlassBatch.backdropIdOf(context);
  if (id == null) return false;
  final chrome = context
      .dependOnInheritedWidgetOfExactType<_SistrumChromeBatchScope>();
  return chrome?.backdropId == id &&
      context.dependOnInheritedWidgetOfExactType<_SistrumChromeMemberScope>() ==
          null;
}

/// The key a plain blur at [context] pushes: the enclosing batch's, on
/// Impeller only (the package keys its own passes the same way), and never
/// for glass outside the chrome inside [SistrumChromeBatch].
int? sistrumBlurBackdropId(BuildContext context, {required bool impeller}) {
  if (!impeller || sistrumOutsideChromeBatch(context)) return null;
  return LiquidGlassBatch.backdropIdOf(context);
}

/// A backdrop blur that carries an integer backdrop key, so it can share a
/// read with the package's lenses. A null [backdropId] is a read of its own.
///
/// It is a [BackdropFilter] for finders and diagnostics; only the pushed
/// layer differs.
class SistrumBackdropBlur extends BackdropFilter {
  const SistrumBackdropBlur({
    super.key,
    required ui.ImageFilter super.filter,
    super.child,
    this.backdropId,
  });

  final int? backdropId;

  @override
  RenderBackdropFilter createRenderObject(BuildContext context) =>
      _RenderSistrumBackdropBlur(blur: filter!, backdropId: backdropId);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBackdropFilter renderObject,
  ) {
    (renderObject as _RenderSistrumBackdropBlur)
      ..blur = filter!
      ..backdropId = backdropId;
  }
}

class _RenderSistrumBackdropBlur extends RenderBackdropFilter {
  _RenderSistrumBackdropBlur({required ui.ImageFilter blur, int? backdropId})
    : _blur = blur,
      _backdropId = backdropId,
      super(filter: blur);

  final _layer = LayerHandle<SistrumBackdropLayer>();

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
    final layer = _layer.layer ??= SistrumBackdropLayer();
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

/// The engine pass of [SistrumBackdropBlur].
class SistrumBackdropLayer extends ContainerLayer {
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

/// Marks a package pass for [sistrumCountBackdropReads] (a lens's shader
/// pass, the scroll edge's blur): their layers are private to the package.
/// It adds no engine layer.
class SistrumBackdropReadMarker extends SingleChildRenderObjectWidget {
  const SistrumBackdropReadMarker({
    super.key,
    required this.backdropId,
    super.child,
  });

  final int? backdropId;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSistrumBackdropReadMarker(backdropId);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderSistrumBackdropReadMarker).backdropId = backdropId;
  }
}

class _RenderSistrumBackdropReadMarker extends RenderProxyBox {
  _RenderSistrumBackdropReadMarker(this._backdropId);

  final _layer = LayerHandle<SistrumBackdropReadMarkerLayer>();

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
    final layer = _layer.layer ??= SistrumBackdropReadMarkerLayer();
    layer.backdropId = _backdropId;
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }
}

/// See [SistrumBackdropReadMarker].
class SistrumBackdropReadMarkerLayer extends ContainerLayer {
  int? backdropId;
}

/// Backdrop reads in one composited frame: each unkeyed pass is a read, and
/// each shared key is one read however many passes use it.
@immutable
class SistrumBackdropReads {
  const SistrumBackdropReads({required this.own, required this.shared});

  /// Passes with a read of their own.
  final int own;

  /// Distinct shared keys.
  final int shared;

  int get total => own + shared;
}

/// Counts the reads under [root], the layer tree of the last frame.
SistrumBackdropReads sistrumCountBackdropReads(Layer? root) {
  var own = 0;
  final shared = <Object>{};
  void count(Object? key) => key == null ? own++ : shared.add(key);
  void visit(Layer layer) {
    switch (layer) {
      case SistrumBackdropLayer(filter: _?, :final backdropId):
        count(backdropId);
      case SistrumBackdropReadMarkerLayer(:final backdropId):
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
  return SistrumBackdropReads(own: own, shared: shared.length);
}
