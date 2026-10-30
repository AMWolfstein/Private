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
/// only [AppChromeMember] subtrees join. Every other glass below it
/// (page content, sheets, dialogs on a tab navigator) reads on its own, and
/// glass that overlaps chrome (the header band under the controls) stays
/// out explicitly.
class AppChromeBatch extends StatelessWidget {
  const AppChromeBatch({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LiquidGlassBatch(
    child: Builder(
      // The package allocates the key; it is only read here.
      builder: (context) => _AppChromeBatchScope(
        backdropId: LiquidGlassBatch.backdropIdOf(context),
        child: child,
      ),
    ),
  );
}

class _AppChromeBatchScope extends InheritedWidget {
  const _AppChromeBatchScope({required this.backdropId, required super.child});

  final int? backdropId;

  @override
  bool updateShouldNotify(_AppChromeBatchScope oldWidget) =>
      backdropId != oldWidget.backdropId;
}

/// Marks persistent chrome that joins [AppChromeBatch].
///
/// With [followRoute], the member reads on its own while its route is
/// covered or moving: two pages paint together then, and the incoming page
/// must not filter the outgoing page's copy. [join] false keeps it out for
/// the moment, e.g. bar buttons crossing the tabs while they fold.
class AppChromeMember extends StatefulWidget {
  const AppChromeMember({
    super.key,
    required this.child,
    this.followRoute = true,
    this.join = true,
  });

  final Widget child;
  final bool followRoute;
  final bool join;

  @override
  State<AppChromeMember> createState() => _AppChromeMemberState();
}

class _AppChromeMemberState extends State<AppChromeMember> {
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
    final child = _AppChromeMemberScope(
      child: KeyedSubtree(key: _subtree, child: widget.child),
    );
    return widget.join && _settled
        ? child
        : LiquidGlassBatch.exclude(child: child);
  }
}

class _AppChromeMemberScope extends InheritedWidget {
  const _AppChromeMemberScope({required super.child});

  @override
  bool updateShouldNotify(_AppChromeMemberScope oldWidget) => false;
}

/// Whether glass at [context] sits in [AppChromeBatch] without being
/// chrome. It must then read on its own: wrap its lens in
/// [LiquidGlassBatch.exclude] and give its blur no key.
bool appOutsideChromeBatch(BuildContext context) {
  final id = LiquidGlassBatch.backdropIdOf(context);
  if (id == null) return false;
  final chrome = context
      .dependOnInheritedWidgetOfExactType<_AppChromeBatchScope>();
  return chrome?.backdropId == id &&
      context.dependOnInheritedWidgetOfExactType<_AppChromeMemberScope>() ==
          null;
}

/// The key a plain blur at [context] pushes: the enclosing batch's, on
/// Impeller only (the package keys its own passes the same way), and never
/// for glass outside the chrome inside [AppChromeBatch].
int? appBlurBackdropId(BuildContext context, {required bool impeller}) {
  if (!impeller || appOutsideChromeBatch(context)) return null;
  return LiquidGlassBatch.backdropIdOf(context);
}

/// A backdrop blur that carries an integer backdrop key, so it can share a
/// read with the package's lenses. A null [backdropId] is a read of its own.
///
/// It is a [BackdropFilter] for finders and diagnostics; only the pushed
/// layer differs.
class AppBackdropBlur extends BackdropFilter {
  const AppBackdropBlur({
    super.key,
    required ui.ImageFilter super.filter,
    super.child,
    this.backdropId,
  });

  final int? backdropId;

  @override
  RenderBackdropFilter createRenderObject(BuildContext context) =>
      _RenderAppBackdropBlur(blur: filter!, backdropId: backdropId);

  @override
  void updateRenderObject(
    BuildContext context,
    RenderBackdropFilter renderObject,
  ) {
    (renderObject as _RenderAppBackdropBlur)
      ..blur = filter!
      ..backdropId = backdropId;
  }
}

class _RenderAppBackdropBlur extends RenderBackdropFilter {
  _RenderAppBackdropBlur({required ui.ImageFilter blur, int? backdropId})
    : _blur = blur,
      _backdropId = backdropId,
      super(filter: blur);

  final _layer = LayerHandle<AppBackdropLayer>();

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
    final layer = _layer.layer ??= AppBackdropLayer();
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

/// The engine pass of [AppBackdropBlur].
class AppBackdropLayer extends ContainerLayer {
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

/// Marks a package pass for [appCountBackdropReads] (a lens's shader
/// pass, the scroll edge's blur): their layers are private to the package.
/// It adds no engine layer.
class AppBackdropReadMarker extends SingleChildRenderObjectWidget {
  const AppBackdropReadMarker({
    super.key,
    required this.backdropId,
    super.child,
  });

  final int? backdropId;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderAppBackdropReadMarker(backdropId);

  @override
  void updateRenderObject(BuildContext context, RenderObject renderObject) {
    (renderObject as _RenderAppBackdropReadMarker).backdropId = backdropId;
  }
}

class _RenderAppBackdropReadMarker extends RenderProxyBox {
  _RenderAppBackdropReadMarker(this._backdropId);

  final _layer = LayerHandle<AppBackdropReadMarkerLayer>();

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
    final layer = _layer.layer ??= AppBackdropReadMarkerLayer();
    layer.backdropId = _backdropId;
    context.pushLayer(layer, super.paint, offset);
  }

  @override
  void dispose() {
    _layer.layer = null;
    super.dispose();
  }
}

/// See [AppBackdropReadMarker].
class AppBackdropReadMarkerLayer extends ContainerLayer {
  int? backdropId;
}

/// Backdrop reads in one composited frame: each unkeyed pass is a read, and
/// each shared key is one read however many passes use it.
@immutable
class AppBackdropReads {
  const AppBackdropReads({required this.own, required this.shared});

  /// Passes with a read of their own.
  final int own;

  /// Distinct shared keys.
  final int shared;

  int get total => own + shared;
}

/// Counts the reads under [root], the layer tree of the last frame.
AppBackdropReads appCountBackdropReads(Layer? root) {
  var own = 0;
  final shared = <Object>{};
  void count(Object? key) => key == null ? own++ : shared.add(key);
  void visit(Layer layer) {
    switch (layer) {
      case AppBackdropLayer(filter: _?, :final backdropId):
        count(backdropId);
      case AppBackdropReadMarkerLayer(:final backdropId):
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
  return AppBackdropReads(own: own, shared: shared.length);
}
