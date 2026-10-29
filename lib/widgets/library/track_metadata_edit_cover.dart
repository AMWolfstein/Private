part of 'track_metadata_edit_sheet.dart';

/// Cover picker and preview state for [EditMetadataSheet], with its cover
/// editor and section-card builders. Kept in the sheet's library through
/// `part of` so it can share the sheet state's private members.
mixin _MetadataCoverEditing on State<EditMetadataSheet> {
  bool get _saving;

  final _covers = MetadataCoverResources();
  String? _selectedCoverPath;
  String? _selectedCoverTempDir;
  String? _selectedCoverName;
  String? _currentCoverPath;
  String? _currentCoverTempDir;
  bool _loadingCurrentCover = false;
  final Map<String, ({int width, int height, int bytes})> _coverDetails = {};
  final Set<String> _coverDetailLoads = {};
  final GlobalKey<ScaffoldMessengerState> _sheetMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

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

  bool _hasValue(String? value) => value != null && value.trim().isNotEmpty;

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
        color: AppTheme.controlFill(context),
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: DividerTheme(
          data: DividerTheme.of(
            context,
          ).copyWith(color: AppTheme.metadataDividerColor(context)),
          child: content,
        ),
      ),
    );
  }
}
