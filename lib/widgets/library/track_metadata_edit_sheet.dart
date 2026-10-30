import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/metadata_separators.dart';
import 'package:sistrum/services/library/browse/library_tag_credits.dart';
import 'package:sistrum/providers/metadata_editor_controller.dart';
import 'package:sistrum/services/library/metadata/metadata_cover_resources.dart';
import 'package:sistrum/theme/app_icons.dart';
import 'package:sistrum/theme/app_theme.dart';
import 'package:sistrum/services/library/metadata/track_metadata_persistence.dart';
import 'package:sistrum/widgets/primitives/app_action_button.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/primitives/app_snack_bar.dart';
import 'package:sistrum/widgets/primitives/app_switch.dart';
import 'package:sistrum/widgets/sheets/metadata_text_field.dart';

part 'track_metadata_edit_cover.dart';

class EditMetadataSheet extends StatefulWidget {
  final ColorScheme colorScheme;
  final Map<String, String> initialValues;
  final String filePath;

  final int durationMs;
  final MetadataSeparators metadataSeparators;
  final TagCreditRules tagCreditRules;

  const EditMetadataSheet({
    super.key,
    required this.colorScheme,
    required this.initialValues,
    required this.filePath,

    required this.durationMs,
    this.metadataSeparators = const MetadataSeparators(),
    this.tagCreditRules = const TagCreditRules(),
  });

  @override
  State<EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<EditMetadataSheet>
    with _MetadataCoverEditing {
  @override
  bool _saving = false;
  late final _persistence = MetadataPersistenceService(covers: _covers);
  bool _showAdvanced = false;
  late final MetadataEditorController _form;

  @override
  void initState() {
    super.initState();
    _form = MetadataEditorController(widget.initialValues);
    unawaited(_loadCurrentCoverPreview());
  }

  @override
  void dispose() {
    unawaited(_covers.dispose());
    _form.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final result = await _persistence.save(
        MetadataSaveRequest(
          filePath: widget.filePath,
          metadata: _form.buildMetadataTags(
            separators: widget.metadataSeparators,
            rules: widget.tagCreditRules,
            onlyChanged: true,
          ),
          selectedCoverPath: _selectedCoverPath,
          currentCoverPath: _currentCoverPath,
        ),
      );
      if (!mounted) return;
      if (result.failure == null) {
        Navigator.pop(context, true);
        return;
      }
      final l10n = context.l10n;
      _showSheetSnackBar(switch (result.failure!) {
        MetadataSaveFailure.backend => context.friendlyError(
          result.error,
          fallback: l10n.metadataSaveFailedFfmpeg,
        ),
        MetadataSaveFailure.ffmpeg => l10n.metadataSaveFailedFfmpeg,
        MetadataSaveFailure.storage => context.friendlyError(
          result.error,
          fallback: l10n.metadataSaveFailedStorage,
        ),
        MetadataSaveFailure.unexpected => l10n.snackbarError(
          context.friendlyError(result.error),
        ),
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = widget.colorScheme;

    return PopScope(
      canPop: !_saving,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.85,
          // While a save is running the sheet cannot be dragged away either:
          // the route no longer drags, and the content cannot reach its close
          // extent.
          minChildSize: _saving ? 0.85 : 0.5,
          maxChildSize: 0.95,
          shouldCloseOnMinExtent: !_saving,
          expand: false,
          builder: (context, scrollController) => AppScaffoldMessenger(
            key: _sheetMessengerKey,
            child: Scaffold(
              backgroundColor: Colors.transparent,
              resizeToAvoidBottomInset: false,
              body: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 12, bottom: 8),
                    child: const AppSheetHandle(),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.l10n.trackEditMetadata,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        if (_saving)
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            child: Semantics(
                              label: context.l10n.a11ySavingTrackDetails,
                              liveRegion: true,
                              excludeSemantics: true,
                              child: const SizedBox(
                                width: 22,
                                height: 22,
                                child: CupertinoActivityIndicator(),
                              ),
                            ),
                          )
                        else
                          AppActionButton(
                            onPressed: _save,
                            icon: const Icon(Icons.check, size: 18),
                            label: Text(context.l10n.dialogSave),
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 18,
                                vertical: 12,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                  Expanded(
                    child: ListView(
                      controller: scrollController,
                      padding: const EdgeInsets.fromLTRB(20, 6, 20, 24),
                      children: [
                        _buildCoverEditor(cs),
                        _sectionCard(
                          icon: Icons.info_outline,
                          title: context.l10n.trackMetadata,
                          children: [
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldTitle,
                              _form['title']!,
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldArtist,
                              _form['artist']!,
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldAlbum,
                              _form['album']!,
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldAlbumArtist,
                              _form['album_artist']!,
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldDate,
                              _form['date']!,
                              hint: context.l10n.editMetadataFieldDateHint,
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: MetadataTextField(
                                    cs,
                                    context.l10n.editMetadataFieldTrackNum,
                                    _form['track_number']!,
                                    keyboard: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: MetadataTextField(
                                    cs,
                                    context.l10n.editMetadataFieldTrackTotal,
                                    _form['total_tracks']!,
                                    keyboard: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            Row(
                              children: [
                                Expanded(
                                  child: MetadataTextField(
                                    cs,
                                    context.l10n.editMetadataFieldDiscNum,
                                    _form['disc_number']!,
                                    keyboard: TextInputType.number,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: MetadataTextField(
                                    cs,
                                    context.l10n.editMetadataFieldDiscTotal,
                                    _form['total_discs']!,
                                    keyboard: TextInputType.number,
                                  ),
                                ),
                              ],
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldGenre,
                              _form['genre']!,
                            ),
                            MetadataTextField(
                              cs,
                              context.l10n.editMetadataFieldIsrc,
                              _form['isrc']!,
                            ),
                          ],
                        ),
                        _sectionCard(
                          icon: Icons.lyrics_outlined,
                          title: context.l10n.trackLyrics,
                          children: [
                            MetadataTextField(
                              cs,
                              context.l10n.trackLyrics,
                              _form['lyrics']!,
                              maxLines: 8,
                              keyboard: TextInputType.multiline,
                            ),
                          ],
                        ),
                        _sectionCard(
                          icon: Icons.tune,
                          title: context.l10n.editMetadataAdvanced,
                          onHeaderTap: () =>
                              setState(() => _showAdvanced = !_showAdvanced),
                          expanded: _showAdvanced,
                          children: [
                            if (_showAdvanced) ...[
                              MetadataTextField(
                                cs,
                                context.l10n.editMetadataFieldLabel,
                                _form['label']!,
                              ),
                              MetadataTextField(
                                cs,
                                context.l10n.editMetadataFieldCopyright,
                                _form['copyright']!,
                              ),
                              MetadataTextField(
                                cs,
                                context.l10n.editMetadataFieldComposer,
                                _form['composer']!,
                              ),
                              MetadataTextField(
                                cs,
                                context.l10n.trackAlbumType,
                                _form['album_type']!,
                                hint:
                                    context.l10n.editMetadataFieldAlbumTypeHint,
                              ),
                              _switchField(
                                label: context.l10n.editMetadataFieldExplicit,
                                subtitle:
                                    context.l10n.editMetadataFieldExplicitHint,
                                value: _form.explicit,
                                onChanged: (value) =>
                                    setState(() => _form.explicit = value),
                              ),
                              MetadataTextField(
                                cs,
                                context.l10n.editMetadataFieldUpc,
                                _form['upc']!,
                                hint: context.l10n.editMetadataFieldUpcHint,
                                keyboard: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                  LengthLimitingTextInputFormatter(18),
                                ],
                              ),
                              MetadataTextField(
                                cs,
                                context.l10n.editMetadataFieldComment,
                                _form['comment']!,
                                maxLines: 3,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _switchField({
    required String label,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    final cs = widget.colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        children: [
          Material(
            color: metadataEditorFieldFill(context, cs),
            borderRadius: BorderRadius.circular(14),
            clipBehavior: Clip.antiAlias,
            child: AppSwitchListTile(
              adaptive: true,
              value: value,
              onChanged: onChanged,
              contentPadding: EdgeInsets.symmetric(horizontal: 4),
              title: Text(label, style: Theme.of(context).textTheme.bodyLarge),
              subtitle: Text(
                subtitle,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ),
          const Divider(height: 0.5),
        ],
      ),
    );
  }
}
