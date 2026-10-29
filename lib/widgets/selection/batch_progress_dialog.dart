import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';

class _BatchProgress {
  final int current;
  final String? detail;
  const _BatchProgress({this.current = 0, this.detail});
}

/// A reusable progress dialog for local batch operations such as ReplayGain.
///
/// Uses a static [ValueNotifier] so callers do not need the dialog's
/// [BuildContext] to push updates – unlike `findAncestorStateOfType` which
/// fails because the dialog lives in a separate navigator route.
///
/// Usage:
/// ```dart
/// var cancelled = false;
/// late final VoidCallback dismissProgress;
/// dismissProgress = BatchProgressDialog.show(
///   context: context,
///   title: 'Applying ReplayGain...',
///   total: items.length,
///   icon: Icons.graphic_eq,
///   onCancel: () {
///     cancelled = true;
///     dismissProgress();
///   },
/// );
///
/// for (int i = 0; i < items.length; i++) {
///   if (cancelled) break;
///   BatchProgressDialog.update(current: i + 1, detail: items[i].name);
///   await doWork(items[i]);
/// }
///
/// dismissProgress();
/// ```
class BatchProgressDialog extends StatefulWidget {
  final String title;
  final int total;
  final IconData icon;
  final VoidCallback onCancel;
  final ValueNotifier<_BatchProgress> _progressNotifier;

  // ignore: prefer_const_constructors_in_immutables
  BatchProgressDialog._({
    required this.title,
    required this.total,
    required this.icon,
    required this.onCancel,
    required ValueNotifier<_BatchProgress> progressNotifier,
  }) : _progressNotifier = progressNotifier;

  static ValueNotifier<_BatchProgress>? _activeNotifier;
  static VoidCallback? _activeDismiss;

  /// Returns a dismissal callback owned by this dialog, not the top route.
  static VoidCallback show({
    required BuildContext context,
    required String title,
    required int total,
    required VoidCallback onCancel,
    IconData icon = Icons.transform,
  }) {
    _activeNotifier = ValueNotifier(const _BatchProgress());
    final notifier = _activeNotifier!;

    ModalRoute<void>? route;
    var dismissed = false;
    var cancelled = false;

    void dismissDialog() {
      if (dismissed) return;
      dismissed = true;
      if (identical(_activeNotifier, notifier)) {
        _activeNotifier = null;
        _activeDismiss = null;
      }
      final ownedRoute = route;
      if (ownedRoute != null && ownedRoute.isActive) {
        // A different route may now cover the dialog. Never pop that route.
        ownedRoute.navigator?.removeRoute(ownedRoute);
      }
    }

    void cancel() {
      if (dismissed || cancelled) return;
      cancelled = true;
      onCancel();
    }

    _activeDismiss = dismissDialog;
    showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        route = ModalRoute.of<void>(dialogContext);
        // Work can finish before the dialog's first frame is built.
        if (dismissed) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            final ownedRoute = route;
            if (ownedRoute != null && ownedRoute.isActive) {
              ownedRoute.navigator?.removeRoute(ownedRoute);
            }
          });
        }
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) cancel();
          },
          child: BatchProgressDialog._(
            title: title,
            total: total,
            icon: icon,
            onCancel: cancel,
            progressNotifier: notifier,
          ),
        );
      },
    ).whenComplete(() {
      // External route removal is cancellation too, unless we completed it.
      cancel();
      dismissDialog();
      notifier.dispose();
    });
    return dismissDialog;
  }

  static void update({required int current, String? detail}) {
    _activeNotifier?.value = _BatchProgress(current: current, detail: detail);
  }

  static void dismiss(BuildContext context) {
    _activeDismiss?.call();
  }

  @override
  State<BatchProgressDialog> createState() => _BatchProgressDialogState();
}

class _BatchProgressDialogState extends State<BatchProgressDialog> {
  @override
  void initState() {
    super.initState();
    widget._progressNotifier.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget._progressNotifier.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    final current = widget._progressNotifier.value.current;
    final detail = widget._progressNotifier.value.detail;
    final progress = widget.total > 0 ? current / widget.total : 0.0;

    return AppAlertDialog(
      backgroundColor: colorScheme.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 8),
          SizedBox(
            width: 64,
            height: 64,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CircularProgressIndicator(
                  value: progress > 0 ? progress : null,
                  strokeWidth: 4,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
                Icon(widget.icon, color: colorScheme.primary, size: 24),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Text(
            widget.title,
            style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '$current / ${widget.total}',
            style: textTheme.bodyMedium?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          if (detail != null && detail.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              detail,
              style: textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
            ),
          ],
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: progress > 0 ? progress : null,
              backgroundColor: colorScheme.surfaceContainerHighest,
              minHeight: 6,
            ),
          ),
        ],
      ),
      actions: [
        AppDialogAction(
          onPressed: widget.onCancel,
          child: Text(context.l10n.dialogCancel),
        ),
      ],
    );
  }
}
