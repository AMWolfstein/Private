import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/controllers/metadata_editor_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/metadata_separators.dart';
import 'package:sistrum/services/metadata_cover_resources.dart';
import 'package:sistrum/services/metadata_persistence_service.dart';
import 'package:sistrum/theme/sistrum_theme.dart';
import 'package:sistrum/theme/sistrum_icons.dart';
import 'package:sistrum/widgets/app_action_button.dart';
import 'package:sistrum/widgets/app_bottom_sheet.dart';
import 'package:sistrum/widgets/app_snack_bar.dart';
import 'package:sistrum/widgets/app_switch.dart';
import 'package:sistrum/widgets/metadata_text_field.dart';

class EditMetadataSheet extends StatefulWidget {
  final ColorScheme colorScheme;
  final Map<String, String> initialValues;
  final String filePath;

  final int durationMs;
  final MetadataSeparators metadataSeparators;

  const EditMetadataSheet({
    super.key,
    required this.colorScheme,
    required this.initialValues,
    required this.filePath,

    required this.durationMs,
    this.metadataSeparators = const MetadataSeparators(),
  });

  @override
  State<EditMetadataSheet> createState() => _EditMetadataSheetState();
}

class _EditMetadataSheetState extends State<EditMetadataSheet> {
  static const _coverResizeDimensions = <int>[500, 1000, 1500, 2000, 3000];

  bool _saving = false;
  final _covers = MetadataCoverResources();
  late final _persistence = MetadataPersistenceService(covers: _covers);
  bool _showAdvanced = false;
  String? _selectedCoverPath;
  String? _selectedCoverTempDir;
  String? _selectedCoverName;
  String? _currentCoverPath;
  String? _currentCoverTempDir;
  bool _loadingCurrentCover = false;
  int? _coverMaxDimension;
  final Map<String, ({int width, int height, int bytes})> _coverDetails = {};
  final Set<String> _coverDetailLoads = {};
  final GlobalKey<ScaffoldMessengerState> _sheetMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  Future<void> _showCoverResolutionPicker() async {
    FocusScope.of(context).unfocus();
    final currentValue = _coverMaxDimension ?? 0;
    final selectedValue = await showModalBottomSheet<int>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerHigh,
      builder: (sheetContext) {
        final cs = Theme.of(sheetContext).colorScheme;
        final options = <({int value, String label})>[
          (
            value: 0,
            label: _originalCoverResolutionLabel(
              sheetContext.l10n.metadataOriginal,
            ),
          ),
          for (final dimension in _coverResizeDimensions)
            (value: dimension, label: '$dimension px'),
        ];
        return SafeArea(
          top: false,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.72,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
                  child: Text(
                    sheetContext.l10n.trackCoverResolution,
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _editorOptions(
                      children: [
                        for (var index = 0; index < options.length; index++)
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 20,
                                  vertical: 4,
                                ),
                                leading: Icon(
                                  CupertinoIcons.photo,
                                  color: options[index].value == currentValue
                                      ? cs.primary
                                      : cs.onSurfaceVariant,
                                ),
                                title: Text(options[index].label),
                                selected: options[index].value == currentValue,
                                selectedColor: cs.primary,
                                trailing: options[index].value == currentValue
                                    ? Icon(CupertinoIcons.checkmark)
                                    : null,
                                onTap: () => Navigator.pop(
                                  sheetContext,
                                  options[index].value,
                                ),
                              ),
                              if (index != options.length - 1)
                                Divider(
                                  height: 1,
                                  indent: 60,
                                  endIndent: 20,
                                  color: cs.outlineVariant.withValues(
                                    alpha: 0.3,
                                  ),
                                ),
                            ],
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || selectedValue == null) return;
    setState(() {
      _coverMaxDimension = selectedValue == 0 ? null : selectedValue;
    });
  }

  void _showSheetSnackBar(String message) {
    final snackBar = SnackBar(content: Text(message));
    final messenger = _sheetMessengerKey.currentState;
    if (messenger != null) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(snackBar);
      return;
    }
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
  }

  late final MetadataEditorController _form;

  bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;

  String _originalCoverResolutionLabel(String originalLabel) {
    final sourcePath = _selectedCoverPath ?? _currentCoverPath;
    final details = sourcePath == null ? null : _coverDetails[sourcePath];
    if (details == null) return originalLabel;
    return '$originalLabel · ${details.width} × ${details.height} px · '
        '${_formatCoverBytes(details.bytes)}';
  }

  String _formatCoverBytes(int bytes) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }

  Future<void> _loadCoverDetails(String path) async {
    if (_coverDetails.containsKey(path) || !_coverDetailLoads.add(path)) {
      return;
    }
    final details = await _covers.readDetails(path);
    if (!mounted) return;
    setState(() {
      _coverDetailLoads.remove(path);
      final isActivePath =
          path == _currentCoverPath || path == _selectedCoverPath;
      if (isActivePath && details != null) {
        _coverDetails[path] = details;
      }
    });
  }

  String _resolveImageExtension(String? ext, Uint8List? bytes) {
    final normalized = (ext ?? '').toLowerCase();
    if (normalized == 'png' ||
        normalized == 'jpg' ||
        normalized == 'jpeg' ||
        normalized == 'webp') {
      return normalized == 'jpeg' ? 'jpg' : normalized;
    }
    if (bytes != null && bytes.length >= 8) {
      if (bytes[0] == 0x89 &&
          bytes[1] == 0x50 &&
          bytes[2] == 0x4E &&
          bytes[3] == 0x47) {
        return 'png';
      }
      if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
        return 'jpg';
      }
      if (bytes.length >= 12 &&
          bytes[0] == 0x52 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x46 &&
          bytes[8] == 0x57 &&
          bytes[9] == 0x45 &&
          bytes[10] == 0x42 &&
          bytes[11] == 0x50) {
        return 'webp';
      }
    }
    return 'jpg';
  }

  Future<void> _cleanupSelectedCoverTemp() async {
    final directory = _selectedCoverTempDir;
    final path = _selectedCoverPath;
    _selectedCoverPath = null;
    _selectedCoverTempDir = null;
    _selectedCoverName = null;
    _coverDetails.remove(path);
    _coverDetailLoads.remove(path);
    await _covers.release(directory);
  }

  Future<void> _loadCurrentCoverPreview() async {
    if (_loadingCurrentCover) return;
    setState(() => _loadingCurrentCover = true);
    final preview = await _covers.extract(widget.filePath);
    if (!mounted) return;
    final oldDirectory = _currentCoverTempDir;
    _coverDetails.remove(_currentCoverPath);
    _coverDetailLoads.remove(_currentCoverPath);
    setState(() {
      _currentCoverPath = preview?.path;
      _currentCoverTempDir = preview?.tempDir;
      _loadingCurrentCover = false;
      if (preview?.details case final details?) {
        _coverDetails[preview!.path] = details;
      }
    });
    await _covers.release(oldDirectory);
  }

  Future<void> _pickCoverImage() async {
    try {
      final picked = await FilePicker.pickFile(type: FileType.image);
      if (picked == null || !mounted) return;
      final sourcePath = picked.path;
      final bytes = _hasValue(sourcePath) ? null : await picked.readAsBytes();
      if (!mounted) return;
      final extension = _resolveImageExtension(
        p.extension(picked.name).replaceFirst('.', ''),
        bytes,
      );
      final preview = await _covers.copyPicked(
        extension: extension,
        sourcePath: sourcePath,
        bytes: bytes,
      );
      if (!mounted) return;
      await _cleanupSelectedCoverTemp();
      if (!mounted) return;
      setState(() {
        _selectedCoverPath = preview.path;
        _selectedCoverTempDir = preview.tempDir;
        _selectedCoverName = picked.name;
      });
      unawaited(_loadCoverDetails(preview.path));
    } catch (e) {
      if (!mounted) return;
      _showSheetSnackBar(context.l10n.snackbarError(context.friendlyError(e)));
    }
  }

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
          metadata: _form.saveMetadata(
            separators: widget.metadataSeparators,
            onlyChanged: true,
          ),
          selectedCoverPath: _selectedCoverPath,
          currentCoverPath: _currentCoverPath,
          coverMaxDimension: _coverMaxDimension,
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
        MetadataSaveFailure.noCover => l10n.snackbarError(
          l10n.trackCoverNoEmbeddedArt,
        ),
        MetadataSaveFailure.resize => l10n.snackbarError(
          l10n.trackCoverResizeFailed,
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

  Widget _editorOptions({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Material(
        color: SistrumTheme.controlFill(context),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: Column(mainAxisSize: MainAxisSize.min, children: children),
      ),
    );
  }

  Widget _buildCoverEditor(ColorScheme cs) {
    final hasSelectedCover = _hasValue(_selectedCoverPath);
    final hasCurrentCover = _hasValue(_currentCoverPath);
    return _sectionCard(
      icon: Icons.image_outlined,
      title: context.l10n.editMetadataFieldCover,
      children: [
        if (_loadingCurrentCover)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (!hasCurrentCover && !hasSelectedCover)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              context.l10n.trackCoverNoEmbeddedArt,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ),
        Row(
          children: [
            Expanded(
              child: AppActionButton(
                outlined: true,
                glass: false,
                onPressed: _saving ? null : _pickCoverImage,
                icon: const Icon(Icons.image_outlined),
                label: Text(
                  hasSelectedCover
                      ? context.l10n.trackCoverReplace
                      : context.l10n.trackCoverPick,
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            if (hasSelectedCover) ...[
              const SizedBox(width: 8),
              IconButton(
                tooltip: context.l10n.trackCoverClearSelected,
                onPressed: _saving
                    ? null
                    : () async {
                        await _cleanupSelectedCoverTemp();
                        if (!mounted) return;
                        setState(() {});
                      },
                icon: const Icon(Icons.close),
              ),
            ],
          ],
        ),
        if (hasCurrentCover || hasSelectedCover) ...[
          const SizedBox(height: 12),
          Row(
            children: [
              if (hasCurrentCover)
                Expanded(
                  child: _buildCoverPreviewTile(
                    cs: cs,
                    path: _currentCoverPath!,
                    label: context.l10n.trackCoverCurrent,
                  ),
                ),
              if (hasCurrentCover && hasSelectedCover)
                const SizedBox(width: 12),
              if (hasSelectedCover)
                Expanded(
                  child: _buildCoverPreviewTile(
                    cs: cs,
                    path: _selectedCoverPath!,
                    label:
                        _selectedCoverName ?? context.l10n.trackCoverSelected,
                  ),
                ),
            ],
          ),
          if (hasSelectedCover) ...[
            const SizedBox(height: 8),
            Text(
              context.l10n.trackCoverReplaceNotice,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 12),
          _selectionField(
            label: context.l10n.trackCoverResolution,
            value: _coverMaxDimension == null
                ? _originalCoverResolutionLabel(context.l10n.metadataOriginal)
                : '${_coverMaxDimension!} px',
            enabled: !_saving,
            onTap: _showCoverResolutionPicker,
          ),
          Text(
            context.l10n.trackCoverResolutionHint,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildCoverPreviewTile({
    required ColorScheme cs,
    required String path,
    required String label,
  }) {
    final details = _coverDetails[path];
    final loadingDetails = _coverDetailLoads.contains(path);
    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: cs.shadow.withValues(alpha: 0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              File(path),
              height: 160,
              width: 160,
              fit: BoxFit.cover,
              cacheWidth: (160 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              cacheHeight: (160 * MediaQuery.devicePixelRatioOf(context))
                  .round(),
              filterQuality: FilterQuality.low,
              errorBuilder: (_, _, _) => Container(
                width: 160,
                height: 160,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.broken_image,
                  color: cs.onSurfaceVariant,
                  size: 32,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 3),
        if (details != null)
          Text(
            '${details.width} × ${details.height} px · '
            '${_formatCoverBytes(details.bytes)}',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          )
        else if (loadingDetails)
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: cs.primary,
            ),
          ),
      ],
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

  Widget _selectionField({
    required String label,
    required String value,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    final cs = widget.colorScheme;
    {
      return Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 6),
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
            CupertinoButton(
              color: metadataEditorFieldFill(context, cs),
              disabledColor: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
              onPressed: enabled ? onTap : null,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      value,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: enabled ? cs.onSurface : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    CupertinoIcons.chevron_up_chevron_down,
                    size: 16,
                    color: cs.primary,
                  ),
                ],
              ),
            ),
            const Divider(height: 0.5),
          ],
        ),
      );
    }
  }

  /// Titled section card. When [onHeaderTap] is set the header is a full-width
  /// tappable row (ripple clipped to the card) with an auto chevron.
  Widget _sectionCard({
    required IconData icon,
    required String title,
    required List<Widget> children,
    VoidCallback? onHeaderTap,
    bool expanded = true,
  }) {
    final cs = widget.colorScheme;
    final collapsible = onHeaderTap != null;
    const inset = 16.0;

    final headerRow = Semantics(
      // The whole row toggles the section; expose it as a button that reports
      // whether its fields are shown.
      button: collapsible,
      expanded: collapsible ? expanded : null,
      child: Row(
        children: [
          Icon(context.adaptiveIcon(icon), size: 20, color: cs.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: cs.onSurface,
              ),
            ),
          ),
          if (collapsible)
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 200),
              curve: Curves.easeOutCubic,
              child: Icon(
                CupertinoIcons.chevron_down,
                size: 22,
                color: cs.onSurfaceVariant,
              ),
            ),
        ],
      ),
    );

    final Widget header = collapsible
        ? InkWell(
            onTap: onHeaderTap,
            child: Padding(
              padding: EdgeInsets.fromLTRB(inset, 16, inset, 16),
              child: headerRow,
            ),
          )
        : Padding(
            padding: EdgeInsets.fromLTRB(inset, 16, inset, 8),
            child: headerRow,
          );

    final content = AnimatedSize(
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          if (children.isNotEmpty)
            Padding(
              padding: EdgeInsets.fromLTRB(inset, 0, inset, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: children,
              ),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: SistrumTheme.controlFill(context),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: DividerTheme(
          data: DividerTheme.of(
            context,
          ).copyWith(color: SistrumTheme.metadataDividerColor(context)),
          child: content,
        ),
      ),
    );
  }
}
