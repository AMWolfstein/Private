import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/widgets/glass/chrome/app_chrome.dart';
import 'package:sistrum/widgets/selection/app_animated_selection_bar.dart';
import 'package:sistrum/widgets/selection/app_selection_panel_drag.dart';
import 'package:sistrum/l10n/l10n.dart';

/// Hosts selection bars above the shell navigation while keeping modal routes
/// above the bar. A raw entry in the root [Overlay] stays above routes pushed
/// later, which made download pickers appear behind the selection toolbar.
class SelectionOverlayHost extends StatefulWidget {
  const SelectionOverlayHost({super.key, required this.child});

  final Widget child;

  static _SelectionOverlayHostState? _maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<_SelectionOverlayHostState>();

  @override
  State<SelectionOverlayHost> createState() => _SelectionOverlayHostState();
}

class _SelectionOverlayHostState extends State<SelectionOverlayHost> {
  SelectionOverlayController? _owner;
  WidgetBuilder? _builder;

  bool owns(SelectionOverlayController owner) =>
      _owner == owner && _builder != null;

  void show(SelectionOverlayController owner, WidgetBuilder builder) {
    _update(() {
      _owner = owner;
      _builder = builder;
    });
  }

  void hide(SelectionOverlayController owner) {
    if (_owner != owner) return;
    _update(() {
      _owner = null;
      _builder = null;
    });
  }

  /// A screen can remove its bar from dispose while Flutter has locked the
  /// tree. Clear ownership immediately, then rebuild after that frame so the
  /// bar cannot outlive the screen or retain its disposed callbacks.
  void _update(VoidCallback change) {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase !=
        SchedulerPhase.persistentCallbacks) {
      setState(change);
      return;
    }
    change();
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final owner = _owner;
    final builder = _builder;
    // A root modal makes the shell route non-current. Removing the toolbar
    // while that route is covered both prevents visual overlap and avoids the
    // hidden toolbar intercepting taps during the modal transition. The stored
    // builder is kept so the selection returns if the modal is dismissed.
    final routeIsCurrent = ModalRoute.of(context)?.isCurrent ?? true;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (routeIsCurrent && owner != null && builder != null)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: KeyedSubtree(
              key: ObjectKey(owner),
              child: AnimatedSelectionBottomBar(
                child: Material(
                  color: Colors.transparent,
                  child: Builder(builder: builder),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Mounts a selection bar in [SelectionOverlayHost]. Screens rendered outside
/// the main shell (including isolated widget tests) retain a root-overlay
/// fallback.
class SelectionOverlayController {
  OverlayEntry? _entry;
  _SelectionOverlayHostState? _host;
  WidgetBuilder? _builder;

  bool get isVisible => _entry != null || (_host?.owns(this) ?? false);

  /// Shows the bar, or rebuilds it in place when already visible so the
  /// entrance animation does not replay on every selection change.
  void show(BuildContext context, WidgetBuilder builder) {
    if (!TickerMode.valuesOf(context).enabled) {
      hide();
      return;
    }

    _builder = builder;
    final host = SelectionOverlayHost._maybeOf(context);
    if (host != null) {
      _entry?.remove();
      _entry = null;
      if (_host != null && _host != host) {
        _host!.hide(this);
      }
      _host = host;
      host.show(this, builder);
      return;
    }

    _host?.hide(this);
    _host = null;
    if (_entry != null) {
      _entry!.markNeedsBuild();
      return;
    }
    _entry = OverlayEntry(
      builder: (overlayContext) => Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: AnimatedSelectionBottomBar(
          child: Material(
            color: Colors.transparent,
            child: _builder!(overlayContext),
          ),
        ),
      ),
    );
    Overlay.of(context, rootOverlay: true).insert(_entry!);
  }

  void hide() {
    _host?.hide(this);
    _host = null;
    _entry?.remove();
    _entry = null;
    _builder = null;
  }

  /// Call from the host `State.dispose`; an entry left in the root overlay
  /// outlives the screen that created it.
  void dispose() => hide();
}

/// Shared chrome for the multi-select bottom bar: rounded surface, drag
/// handle, close button, "N selected" header and select-all toggle.
/// The screen-specific action buttons go in [children].
class SelectionBottomBar extends StatelessWidget {
  const SelectionBottomBar({
    super.key,
    required this.selectedCount,
    required this.allSelected,
    required this.onClose,
    required this.onToggleSelectAll,
    required this.bottomPadding,
    required this.children,
    this.allSelectedLabel,
    this.tapToSelectLabel,
  });

  final int selectedCount;
  final bool allSelected;
  final VoidCallback onClose;
  final VoidCallback onToggleSelectAll;
  final double bottomPadding;
  final List<Widget> children;

  /// Overrides the default "All tracks selected" subtitle.
  final String? allSelectedLabel;

  /// Overrides the default "Tap tracks to select" subtitle.
  final String? tapToSelectLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final header = LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Tooltip(
            message: MaterialLocalizations.of(context).closeButtonTooltip,
            child: CupertinoButton(
              color: AppTheme.controlFill(context),
              borderRadius: BorderRadius.circular(28),
              padding: const EdgeInsets.all(12),
              onPressed: onClose,
              child: Icon(
                CupertinoIcons.xmark,
                color: colorScheme.onSurface,
                size: 24,
              ),
            ),
          ),
          const SizedBox(width: 12),

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // The count changes on every pick; announce it as it updates.
                Semantics(
                  liveRegion: true,
                  container: true,
                  child: Text(
                    context.l10n.selectionSelected(selectedCount),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  allSelected
                      ? allSelectedLabel ?? context.l10n.selectionAllSelected
                      : tapToSelectLabel ?? context.l10n.collectionTapToSelect,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),

          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
            child: CupertinoButton(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              onPressed: onToggleSelectAll,
              child: Text(
                allSelected
                    ? context.l10n.actionDeselect
                    : context.l10n.actionSelectAll,
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colorScheme.primary),
              ),
            ),
          ),
        ],
      ),
    );
    return AppSelectionPanelDrag(
      onClose: onClose,
      header: header,
      bottomPadding: bottomPadding,
      children: children,
      surfaceBuilder: (content) {
        {
          return AppGlassPanel.overlay(child: content);
        }
      },
    );
  }
}
