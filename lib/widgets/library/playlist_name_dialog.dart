import 'package:flutter/material.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';

/// Asks for the name of a new playlist. Returns the trimmed name, or null when
/// the dialog is cancelled.
Future<String?> showPlaylistNameDialog(BuildContext context) =>
    showAppDialog<String>(
      context: context,
      builder: (_) => const _PlaylistNameDialog(),
    );

/// The field's controller belongs to this State, so it is disposed only after
/// the dialog has left the tree. The dialog's exit animation still builds the
/// field, so disposing the controller when the dialog future completes fails.
class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog();

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() != true) return;
    Navigator.of(context).pop(_controller.text.trim());
  }

  @override
  Widget build(BuildContext context) {
    return AppAlertDialog(
      title: Text(context.l10n.collectionCreatePlaylist),
      content: Form(
        key: _formKey,
        child: TextFormField(
          controller: _controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: context.l10n.collectionPlaylistNameHint,
          ),
          validator: (value) {
            final trimmed = value?.trim() ?? '';
            if (trimmed.isEmpty) {
              return context.l10n.collectionPlaylistNameRequired;
            }
            return null;
          },
          onFieldSubmitted: (_) => _submit(),
        ),
      ),
      actions: [
        AppDialogAction(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.dialogCancel),
        ),
        AppDialogAction(
          filled: true,
          isDefault: true,
          onPressed: _submit,
          child: Text(context.l10n.actionCreate),
        ),
      ],
    );
  }
}
