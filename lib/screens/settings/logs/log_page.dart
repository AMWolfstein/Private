import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart' show ShareParams, SharePlus;
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/utils/logging/log_entry.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/primitives/app_sliver_header.dart';
import 'package:sistrum/widgets/primitives/app_search_field.dart';
import 'package:sistrum/utils/playback/ordered_range_selection.dart';
import 'package:sistrum/utils/layout/adaptive_layout.dart';
import 'package:sistrum/screens/settings/logs/log_entry_tile.dart';
import 'package:sistrum/services/platform/native_log_source.dart';

part 'log_page_1.dart';

class LogPage extends ConsumerStatefulWidget {
  const LogPage({super.key});

  @override
  ConsumerState<LogPage> createState() => _LogPageState();
}

class _LogPageState extends ConsumerState<LogPage> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _selectedLevel = 'ALL';
  String _searchQuery = '';
  bool _autoScroll = true;
  int _autoScrollGeneration = 0;
  bool _selectionMode = false;
  final Set<LogEntry> _selectedEntries = <LogEntry>{};
  LogEntry? _selectionAnchor;
  static const _nativeLogSource = NativeLogSource();
  List<LogEntry> _logcatEntries = const <LogEntry>[];
  bool _logcatLoading = false;
  int _logcatRequest = 0;

  // FULL shows this app's own logcat output (read when FULL is selected),
  // with no level restriction. ALL and the level filters apply to the
  // in-memory LogBuffer as before.
  final List<String> _levels = [
    'FULL',
    'ALL',
    'DEBUG',
    'INFO',
    'WARN',
    'ERROR',
  ];

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

  void _rebuild(VoidCallback fn) => setState(fn);

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final logs = _filteredLogs;

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
                        FilledButton.tonalIcon(
                          onPressed: () => _showLevelPicker(context),
                          icon: const Icon(Icons.arrow_drop_down, size: 20),
                          iconAlignment: IconAlignment.end,
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 40),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          label: Text(
                            _levelLabel(context, _selectedLevel),
                            style: TextStyle(
                              color: _levelFiltered
                                  ? _getLevelColor(_selectedLevel, colorScheme)
                                  : null,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
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
                title: _levelFiltered || _searchQuery.isNotEmpty
                    ? context.l10n.logEntriesFiltered(logs.length)
                    : context.l10n.logEntries(logs.length),
              ),
            ),

            SliverToBoxAdapter(
              child: _LogSummaryCard(logs: LogBuffer().entries),
            ),

            _fullSelected && _logcatLoading
                ? const SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  )
                : logs.isEmpty
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
                        return LogEntryTile(
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
