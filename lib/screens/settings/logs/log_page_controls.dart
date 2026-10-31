part of 'log_page.dart';

extension _LogPageStatePart1 on _LogPageState {
  void _onLogUpdate() {
    if (mounted) {
      if (_selectionMode) {
        final currentEntries =
            (_fullSelected ? _logcatEntries : LogBuffer().entries).toSet();
        _selectedEntries.removeWhere(
          (entry) => !currentEntries.contains(entry),
        );
        if (_selectedEntries.isEmpty) {
          _selectionMode = false;
          _selectionAnchor = null;
        } else if (!_selectedEntries.contains(_selectionAnchor)) {
          _selectionAnchor = _selectedEntries.last;
        }
      }
      _rebuild(() {});
      if (_autoScroll && _scrollController.hasClients) {
        final generation = ++_autoScrollGeneration;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToLatestLog(generation);
        });
      }
    }
  }

  bool _canAutoScroll(int generation) =>
      mounted &&
      _autoScroll &&
      generation == _autoScrollGeneration &&
      _scrollController.hasClients;
  Future<void> _scrollToLatestLog(int generation) async {
    // A lazy, variable-height list estimates its unseen rows. Recheck the
    // extent after layout rather than stopping at the first estimated end.
    for (var correction = 0; correction < 8; correction++) {
      if (!_canAutoScroll(generation)) return;
      final position = _scrollController.position;
      if (position.pixels >= position.maxScrollExtent - 0.5) return;
      await _scrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
      await WidgetsBinding.instance.endOfFrame;
    }
  }

  void _toggleAutoScroll() {
    _rebuild(() => _autoScroll = !_autoScroll);
    _autoScrollGeneration++;
    if (!_autoScroll && _scrollController.hasClients) {
      // Cancel the current animation as well as any queued extent correction.
      _scrollController.jumpTo(_scrollController.position.pixels);
    }
  }

  bool get _levelFiltered =>
      _selectedLevel != 'ALL' && _selectedLevel != 'FULL';
  bool get _fullSelected => _selectedLevel == 'FULL';
  String _levelLabel(BuildContext context, String level) =>
      level == 'FULL' ? context.l10n.logFilterFull : level;
  void _selectLevel(String level) {
    final switchingSource = (level == 'FULL') != _fullSelected;
    _rebuild(() {
      _selectedLevel = level;
      if (level != 'FULL') {
        // Drop an in-flight logcat read so its result cannot land later.
        _logcatRequest++;
        _logcatLoading = false;
      }
      if (switchingSource) {
        _selectionMode = false;
        _selectedEntries.clear();
        _selectionAnchor = null;
      }
    });
    if (level == 'FULL') _loadAppLogcat();
  }

  Future<void> _loadAppLogcat() async {
    final request = ++_logcatRequest;
    _rebuild(() => _logcatLoading = true);
    final result = await _LogPageState._nativeLogSource.readAppLogcat();
    if (!mounted || request != _logcatRequest) return;
    var entries = <LogEntry>[];
    switch (result) {
      case NativeLogcatText(:final text):
        entries = parseAppLogcat(text, now: DateTime.now());
      case NativeLogcatUnavailable(:final reason):
        if (kDebugMode) debugPrint('Could not read app logcat: $reason');
    }
    _rebuild(() {
      _logcatEntries = entries;
      _logcatLoading = false;
      // Loaded rows are new objects, so an old selection cannot match them.
      _selectionMode = false;
      _selectedEntries.clear();
      _selectionAnchor = null;
    });
    if (_autoScroll && _scrollController.hasClients) {
      final generation = ++_autoScrollGeneration;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLatestLog(generation);
      });
    }
  }

  List<LogEntry> get _filteredLogs {
    if (_fullSelected) {
      final query = _searchQuery.toLowerCase();
      if (query.isEmpty) return _logcatEntries;
      return _logcatEntries
          .where(
            (entry) =>
                entry.message.toLowerCase().contains(query) ||
                entry.tag.toLowerCase().contains(query) ||
                (entry.error?.toLowerCase().contains(query) ?? false),
          )
          .toList();
    }
    return LogBuffer().filter(
      level: _levelFiltered ? _selectedLevel : null,
      search: _searchQuery.isEmpty ? null : _searchQuery,
    );
  }

  void _copyLogs() async {
    final logs = await LogBuffer().exportWithDeviceInfo();
    Clipboard.setData(ClipboardData(text: logs));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.logCopied),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _enterSelectionMode(LogEntry entry) {
    _rebuild(() {
      _selectionMode = true;
      _autoScroll = false;
      _autoScrollGeneration++;
      _selectedEntries.add(entry);
      _selectionAnchor = entry;
    });
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(_scrollController.position.pixels);
    }
  }

  void _toggleEntrySelection(LogEntry entry) {
    if (!_selectionMode) return;
    _rebuild(() {
      _selectionAnchor = toggleOrderedSelection(
        selected: _selectedEntries,
        target: entry,
      );
      if (_selectedEntries.isEmpty) _selectionMode = false;
    });
  }

  void _selectRangeTo(LogEntry entry) {
    _rebuild(() {
      _selectionMode = true;
      _autoScroll = false;
      _selectionAnchor = addOrderedSelectionRange(
        selected: _selectedEntries,
        visibleItems: _filteredLogs,
        target: entry,
        anchor: _selectionAnchor,
      );
    });
  }

  void _exitSelectionMode() {
    _rebuild(() {
      _selectionMode = false;
      _selectedEntries.clear();
      _selectionAnchor = null;
    });
  }

  void _toggleSelectAllVisible() {
    final visibleLogs = _filteredLogs;
    final allVisibleSelected =
        visibleLogs.isNotEmpty && visibleLogs.every(_selectedEntries.contains);
    _rebuild(() {
      if (allVisibleSelected) {
        _selectedEntries.removeAll(visibleLogs);
      } else {
        _selectedEntries.addAll(visibleLogs);
      }
      _selectionMode = _selectedEntries.isNotEmpty;
      _selectionAnchor = _selectedEntries.isEmpty
          ? null
          : allVisibleSelected
          ? _selectedEntries.last
          : visibleLogs.lastOrNull;
    });
  }

  Future<void> _copySelectedLogs() async {
    final selectedInUserOrder = _selectedEntries.toList(growable: false);
    if (selectedInUserOrder.isEmpty) return;
    await Clipboard.setData(
      ClipboardData(text: formatLogEntries(selectedInUserOrder)),
    );
    if (!mounted) return;
    _exitSelectionMode();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n.logCopied),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _shareLogs() async {
    final logs = await LogBuffer().exportWithDeviceInfo();
    SharePlus.instance.share(ShareParams(text: logs, subject: 'Sistrum Logs'));
  }

  void _shareSelectedLogs() {
    final selectedInUserOrder = _selectedEntries.toList(growable: false);
    if (selectedInUserOrder.isEmpty) return;
    SharePlus.instance.share(
      ShareParams(
        text:
            '$logExportPrivacyNotice\n\n${formatLogEntries(selectedInUserOrder)}',
        subject: 'Sistrum Logs',
      ),
    );
  }

  void _clearLogs() {
    showAppDialog<void>(
      context: context,
      builder: (context) => AppAlertDialog(
        title: Text(context.l10n.logClearLogsTitle),
        content: Text(context.l10n.logClearLogsMessage),
        actions: [
          AppDialogAction(
            isDefault: true,
            onPressed: () => Navigator.pop(context),
            child: Text(context.l10n.dialogCancel),
          ),
          AppDialogAction(
            filled: true,
            isDestructive: true,
            onPressed: () {
              _selectionMode = false;
              _selectedEntries.clear();
              _selectionAnchor = null;
              LogBuffer().clear();
              Navigator.pop(context);
            },
            child: Text(context.l10n.dialogClear),
          ),
        ],
      ),
    );
  }

  Future<void> _showLevelPicker(BuildContext context) async {
    final colorScheme = Theme.of(context).colorScheme;
    final level = await showAppBottomSheet<String>(
      context: context,
      title: context.l10n.logFilterLevel,
      builder: (sheetContext) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: SettingsGroup(
          children: [
            for (final level in _levels)
              SettingsItem(
                title: _levelLabel(context, level),
                trailing: level == _selectedLevel
                    ? Icon(Icons.check, color: colorScheme.primary)
                    : null,
                showDivider: level != _levels.last,
                onTap: () => Navigator.pop(sheetContext, level),
              ),
          ],
        ),
      ),
    );
    if (level != null && mounted) _selectLevel(level);
  }

  Color _getLevelColor(String level, ColorScheme colorScheme) {
    switch (level) {
      case 'ERROR':
      case 'FATAL':
        return colorScheme.error;
      case 'WARN':
        return Colors.orange;
      case 'INFO':
        return colorScheme.primary;
      case 'DEBUG':
      default:
        return colorScheme.onSurfaceVariant;
    }
  }
}
