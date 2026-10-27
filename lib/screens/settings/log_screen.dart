import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sistrum/providers/settings_provider.dart';
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/utils/logger.dart';
import 'package:sistrum/widgets/settings_group.dart';
import 'package:sistrum/widgets/app_sliver_header.dart';
import 'package:sistrum/widgets/app_search_field.dart';
import 'package:sistrum/utils/ordered_range_selection.dart';
import 'package:sistrum/utils/adaptive_layout.dart';

class LogScreen extends ConsumerStatefulWidget {
  const LogScreen({super.key});

  @override
  ConsumerState<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends ConsumerState<LogScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _selectedLevel = 'ALL';
  String _searchQuery = '';
  bool _autoScroll = true;
  int _autoScrollGeneration = 0;
  bool _selectionMode = false;
  final Set<LogEntry> _selectedEntries = <LogEntry>{};
  LogEntry? _selectionAnchor;

  final List<String> _levels = ['ALL', 'DEBUG', 'INFO', 'WARN', 'ERROR'];

  @override
  void initState() {
    super.initState();
    LogBuffer().addListener(_onLogUpdate);
    LogBuffer().startGoLogPolling();
  }

  @override
  void dispose() {
    _autoScrollGeneration++;
    LogBuffer().removeListener(_onLogUpdate);
    LogBuffer().stopGoLogPolling();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onLogUpdate() {
    if (mounted) {
      if (_selectionMode) {
        final currentEntries = LogBuffer().entries.toSet();
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
      setState(() {});
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
    setState(() => _autoScroll = !_autoScroll);
    _autoScrollGeneration++;
    if (!_autoScroll && _scrollController.hasClients) {
      // Cancel the current animation as well as any queued extent correction.
      _scrollController.jumpTo(_scrollController.position.pixels);
    }
  }

  List<LogEntry> get _filteredLogs {
    return LogBuffer().filter(
      level: _selectedLevel,
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
    setState(() {
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
    setState(() {
      _selectionAnchor = toggleOrderedSelection(
        selected: _selectedEntries,
        target: entry,
      );
      if (_selectedEntries.isEmpty) _selectionMode = false;
    });
  }

  void _selectRangeTo(LogEntry entry) {
    setState(() {
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
    setState(() {
      _selectionMode = false;
      _selectedEntries.clear();
      _selectionAnchor = null;
    });
  }

  void _toggleSelectAllVisible() {
    final visibleLogs = _filteredLogs;
    final allVisibleSelected =
        visibleLogs.isNotEmpty && visibleLogs.every(_selectedEntries.contains);
    setState(() {
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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logs = _filteredLogs;
    final settings = ref.watch(settingsProvider);

    return PopScope(
      canPop: !_selectionMode,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectionMode) _exitSelectionMode();
      },
      child: Scaffold(
        body: CustomScrollView(
          controller: _scrollController,
          slivers: [
            AppSliverHeader.page(
              title: _selectionMode
                  ? context.l10n.selectionSelected(_selectedEntries.length)
                  : context.l10n.logTitle,
              leading: _selectionMode
                  ? IconButton(
                      tooltip: MaterialLocalizations.of(
                        context,
                      ).closeButtonTooltip,
                      icon: const Icon(Icons.close),
                      onPressed: _exitSelectionMode,
                    )
                  : null,
              actions: _selectionMode
                  ? [
                      IconButton(
                        icon: Icon(
                          logs.isNotEmpty &&
                                  logs.every(_selectedEntries.contains)
                              ? Icons.deselect
                              : Icons.select_all,
                        ),
                        tooltip:
                            logs.isNotEmpty &&
                                logs.every(_selectedEntries.contains)
                            ? context.l10n.actionDeselect
                            : context.l10n.actionSelectAll,
                        onPressed: _toggleSelectAllVisible,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: context.l10n.logCopyLogs,
                        onPressed: _selectedEntries.isEmpty
                            ? null
                            : _copySelectedLogs,
                      ),
                      IconButton(
                        icon: const Icon(Icons.share),
                        tooltip: context.l10n.logShareLogs,
                        onPressed: _selectedEntries.isEmpty
                            ? null
                            : _shareSelectedLogs,
                      ),
                    ]
                  : [
                      IconButton(
                        icon: Icon(
                          _autoScroll
                              ? Icons.vertical_align_bottom
                              : Icons.vertical_align_center,
                        ),
                        tooltip: _autoScroll
                            ? context.l10n.logAutoScrollOn
                            : context.l10n.logAutoScrollOff,
                        onPressed: _toggleAutoScroll,
                      ),
                      IconButton(
                        icon: const Icon(Icons.copy),
                        tooltip: context.l10n.logCopyLogs,
                        onPressed: _copyLogs,
                      ),
                      PopupMenuButton<String>(
                        icon: const Icon(Icons.more_vert),
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).showMenuTooltip,
                        onSelected: (value) {
                          switch (value) {
                            case 'share':
                              _shareLogs();
                              break;
                            case 'clear':
                              _clearLogs();
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          PopupMenuItem(
                            value: 'share',
                            child: ListTile(
                              leading: const Icon(Icons.share),
                              title: Text(context.l10n.logShareLogs),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                          PopupMenuItem(
                            value: 'clear',
                            child: ListTile(
                              leading: const Icon(Icons.delete_outline),
                              title: Text(context.l10n.logClearLogs),
                              contentPadding: EdgeInsets.zero,
                            ),
                          ),
                        ],
                      ),
                    ],
            ),

            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  SettingsSwitchItem(
                    icon: Icons.bug_report,
                    title: context.l10n.optionsDetailedLogging,
                    subtitle: settings.enableLogging
                        ? context.l10n.optionsDetailedLoggingOn
                        : context.l10n.optionsDetailedLoggingOff,
                    value: settings.enableLogging,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setEnableLogging(value),
                    showDivider: false,
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: context.l10n.logFilterSection,
              ),
            ),
            SliverToBoxAdapter(
              child: SettingsGroup(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.filter_list,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                context.l10n.logFilterLevel,
                                style: Theme.of(context).textTheme.bodyLarge,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                context.l10n.logFilterBySeverity,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        DropdownButton<String>(
                          value: _selectedLevel,
                          underline: const SizedBox(),
                          items: _levels.map((level) {
                            return DropdownMenuItem(
                              value: level,
                              child: Text(
                                level,
                                style: TextStyle(
                                  color: level == 'ALL'
                                      ? colorScheme.onSurface
                                      : _getLevelColor(level, colorScheme),
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            );
                          }).toList(),
                          onChanged: (value) {
                            if (value != null) {
                              setState(() => _selectedLevel = value);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    indent: 56,
                    endIndent: 20,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: AppSearchField(
                      controller: _searchController,
                      // Scrolls over the plain page: tint, no backdrop.
                      samplesBackdrop: false,
                      hintText: context.l10n.logSearchHint,
                      clearTooltip: context.l10n.logClearSearch,
                      onClear: () => setState(() => _searchQuery = ''),
                      onChanged: (value) =>
                          setState(() => _searchQuery = value),
                    ),
                  ),
                ],
              ),
            ),

            SliverToBoxAdapter(
              child: SettingsSectionHeader(
                title: _selectedLevel != 'ALL' || _searchQuery.isNotEmpty
                    ? context.l10n.logEntriesFiltered(logs.length)
                    : context.l10n.logEntries(logs.length),
              ),
            ),

            SliverToBoxAdapter(
              child: _LogSummaryCard(logs: LogBuffer().entries),
            ),

            logs.isEmpty
                ? SliverToBoxAdapter(
                    child: SettingsGroup(
                      children: [
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 48),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.article_outlined,
                                size: 48,
                                color: colorScheme.onSurfaceVariant.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                context.l10n.logNoLogsYet,
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                context.l10n.logNoLogsYetSubtitle,
                                style: Theme.of(context).textTheme.bodyMedium
                                    ?.copyWith(
                                      color: colorScheme.onSurfaceVariant
                                          .withValues(alpha: 0.7),
                                    ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                : SliverLayoutBuilder(
                    builder: (context, constraints) => SliverSettingsGroup(
                      margin: EdgeInsets.symmetric(
                        horizontal:
                            16 + wideInsetForWidth(constraints.crossAxisExtent),
                        vertical: 4,
                      ),
                      itemCount: logs.length,
                      itemBuilder: (context, index) {
                        final log = logs[index];
                        return _LogEntryTile(
                          entry: log,
                          levelColor: _getLevelColor(log.level, colorScheme),
                          showDivider: index < logs.length - 1,
                          selectionMode: _selectionMode,
                          selected: _selectedEntries.contains(log),
                          onTap: () => _toggleEntrySelection(log),
                          onLongPress: () => _selectionMode
                              ? _selectRangeTo(log)
                              : _enterSelectionMode(log),
                        );
                      },
                    ),
                  ),

            const SliverToBoxAdapter(child: SizedBox(height: 32)),
          ],
        ),
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final Color levelColor;
  final bool showDivider;
  final bool selectionMode;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  const _LogEntryTile({
    required this.entry,
    required this.levelColor,
    this.showDivider = true,
    required this.selectionMode,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isError = entry.level == 'ERROR' || entry.level == 'FATAL';

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          container: true,
          selected: selected,
          onTap: selectionMode ? onTap : null,
          onLongPress: onLongPress,
          child: InkWell(
            excludeFromSemantics: true,
            onTap: selectionMode ? onTap : null,
            onLongPress: onLongPress,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: selected
                    ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                    : isError
                    ? colorScheme.errorContainer.withValues(alpha: 0.2)
                    : null,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        entry.formattedTime,
                        style: TextStyle(
                          fontSize: 11,
                          fontFamily: 'monospace',
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: levelColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          entry.level,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: levelColor,
                          ),
                        ),
                      ),
                      if (entry.isFromGo) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 4,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.teal.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Native',
                            style: const TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              color: Colors.teal,
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          entry.tag,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (selectionMode) ...[
                        const SizedBox(width: 8),
                        Icon(
                          selected
                              ? Icons.check_circle
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: selected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    entry.previewMessage,
                    style: TextStyle(
                      fontSize: 13,
                      fontFamily: 'monospace',
                      color: colorScheme.onSurface,
                      height: 1.4,
                    ),
                  ),
                  if (entry.previewError != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      entry.previewError!,
                      style: TextStyle(
                        fontSize: 12,
                        fontFamily: 'monospace',
                        color: colorScheme.error,
                        height: 1.3,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
        if (showDivider)
          Divider(
            height: 1,
            indent: 20,
            endIndent: 20,
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
          ),
      ],
    );
  }
}

class _LogSummaryCard extends StatelessWidget {
  final List<LogEntry> logs;
  const _LogSummaryCard({required this.logs});
  @override
  Widget build(BuildContext context) {
    final count = logs
        .where((log) => log.level == 'ERROR' || log.level == 'FATAL')
        .length;
    if (count == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Card(
        child: ListTile(
          leading: const Icon(Icons.warning_amber_rounded),
          title: Text(context.l10n.logIssueSummary),
          subtitle: Text(context.l10n.logTotalErrors(count)),
        ),
      ),
    );
  }
}
