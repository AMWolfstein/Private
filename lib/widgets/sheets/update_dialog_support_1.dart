part of 'update_dialog.dart';

class _UpdateDialogState extends State<UpdateDialog> {
  bool _isDownloading = false;
  double _progress = 0;
  String _statusText = '';
  static final RegExp _whatsNewPattern = RegExp(
    r"###?\s*What'?s\s*New\s*\n",
    caseSensitive: false,
  );
  static final RegExp _cutoffPattern = RegExp(
    r'\n---|\n###?\s*Downloads',
    caseSensitive: false,
  );
  static final RegExp _sectionPattern = RegExp(r'^#{1,3}\s*(.+)$');
  static final RegExp _listPattern = RegExp(r'^[-*]\s+(.+)$');
  static final RegExp _subListPattern = RegExp(r'^\s+[-*]\s+(.+)$');
  static final RegExp _boldPattern = RegExp(r'\*\*([^*]+)\*\*');
  static final RegExp _codePattern = RegExp(r'`([^`]+)`');

  bool get _opensReleasePage =>
      widget.updateInfo.installKind != UpdateInstallKind.apk;

  Future<void> _openReleasePage() async {
    final uri = Uri.parse(widget.updateInfo.downloadUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    if (mounted && !widget.forced) Navigator.pop(context);
  }

  static String _failureMessage(
    BuildContext context,
    ApkDownloadFailure reason,
  ) {
    final l10n = context.l10n;
    return switch (reason) {
      ApkDownloadFailure.invalidDigest ||
      ApkDownloadFailure.digestMismatch ||
      ApkDownloadFailure.invalidPayload => l10n.updateDownloadIntegrityFailed,
      ApkDownloadFailure.transfer ||
      ApkDownloadFailure.incompleteDownload ||
      ApkDownloadFailure.server => l10n.updateDownloadNetworkFailed,
      ApkDownloadFailure.invalidUrl ||
      ApkDownloadFailure.storageUnavailable => l10n.updateDownloadFailed,
    };
  }

  Future<void> _downloadAndInstall() async {
    if (_opensReleasePage) {
      await _openReleasePage();
      return;
    }
    final apkUrl = widget.updateInfo.apkDownloadUrl!;

    setState(() {
      _isDownloading = true;
      _progress = 0;
      _statusText = context.l10n.updateStartingDownload;
    });

    final notificationService = NotificationService();

    // Without a foreground service the download freezes when the screen
    // turns off; its notification then carries the progress.
    await notificationService.beginUpdateDownloadWork(
      version: widget.updateInfo.version,
    );
    final ApkDownloadResult result;
    try {
      result = await ApkDownloader.downloadApk(
        url: apkUrl,
        version: widget.updateInfo.version,
        expectedSha256: widget.updateInfo.apkSha256,
        onProgress: (received, total) {
          if (mounted) {
            setState(() {
              _progress = total > 0 ? received / total : 0;
              final receivedMB = formatMegabytes(received);
              final totalMB = formatMegabytes(total);
              _statusText = '$receivedMB / $totalMB MB';
            });
          }
          notificationService.showUpdateDownloadProgress(
            version: widget.updateInfo.version,
            received: received,
            total: total,
          );
        },
      );
    } finally {
      await notificationService.endBackgroundWork(
        NotificationService.updateDownloadWorkKind,
      );
    }

    if (result case ApkDownloaded(:final path)) {
      await notificationService.cancelUpdateNotification();

      await notificationService.showUpdateDownloadComplete(
        version: widget.updateInfo.version,
      );

      if (mounted) {
        if (widget.forced) {
          // Keep the mandatory dialog up behind the installer so backing out
          // of the install cannot bypass it; allow a retry.
          setState(() {
            _isDownloading = false;
            _statusText = '';
          });
        } else {
          Navigator.pop(context);
        }
      }

      final outcome = await ApkDownloader.installApk(path);
      if (outcome != ApkInstallOutcome.opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.updateInstallFailed)),
        );
      }
    } else if (result case ApkDownloadFailed(:final reason)) {
      await notificationService.cancelUpdateNotification();

      await notificationService.showUpdateDownloadFailed();

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _statusText = _failureMessage(context, reason);
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.updateFailedMessage)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return PopScope(
      canPop: !widget.forced,
      child: AppAlertDialog(
        icon: Icon(
          Icons.system_update_rounded,
          color: colorScheme.primary,
          size: 32,
        ),
        title: Text(
          widget.forced
              ? context.l10n.updateRequiredTitle
              : context.l10n.updateAvailable,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.forced
                  ? context.l10n.updateRequiredNotice(
                      widget.updateInfo.releasesBehind,
                    )
                  : context.l10n.updateNewVersionReady,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium?.copyWith(
                color: widget.forced
                    ? colorScheme.error
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: _VersionChip(
                    version: AppInfo.displayVersion,
                    label: context.l10n.updateCurrent,
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: 12),
                Icon(
                  Icons.arrow_forward_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: _VersionChip(
                    version: widget.updateInfo.version,
                    label: context.l10n.updateNew,
                    colorScheme: colorScheme,
                    isNew: true,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isDownloading) ...[
              Text(
                context.l10n.updateDownloading,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _progress,
                  minHeight: 6,
                  backgroundColor: colorScheme.surfaceContainerHighest,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      _statusText,
                      style: textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  Text(
                    '${(_progress * 100).toInt()}%',
                    style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ] else ...[
              Text(
                context.l10n.updateWhatsNew,
                style: textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 180),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    _formatChangelog(
                      widget.updateInfo.changelog,
                      context.l10n.updateSeeReleaseNotes,
                    ),
                    style: textTheme.bodySmall?.copyWith(height: 1.5),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!_isDownloading)
            AppDialogAction(
              filled: true,
              onPressed: _downloadAndInstall,
              child: Text(
                _opensReleasePage
                    ? context.l10n.updateViewRelease
                    : context.l10n.updateDownloadInstall,
              ),
            ),
          if (!widget.forced && !_isDownloading)
            AppDialogAction(
              onPressed: () {
                widget.onDisableUpdates();
                Navigator.pop(context);
              },
              child: Text(context.l10n.updateDontRemind),
            ),
          if (!widget.forced)
            AppDialogAction(
              onPressed: () {
                if (!_isDownloading) widget.onDismiss();
                Navigator.pop(context);
              },
              child: Text(
                _isDownloading
                    ? context.l10n.dialogCancel
                    : context.l10n.updateLater,
              ),
            ),
        ],
      ),
    );
  }

  String _formatChangelog(String changelog, String emptyFallback) {
    var content = changelog;

    final whatsNewMatch = _whatsNewPattern.firstMatch(content);
    if (whatsNewMatch != null) {
      content = content.substring(whatsNewMatch.end);
    }

    final cutoffMatch = _cutoffPattern.firstMatch(content);
    if (cutoffMatch != null) {
      content = content.substring(0, cutoffMatch.start);
    }

    final lines = content.split('\n');
    final formattedLines = <String>[];

    for (var line in lines) {
      line = line.trim();
      if (line.isEmpty) continue;

      final sectionMatch = _sectionPattern.firstMatch(line);
      if (sectionMatch != null) {
        final section = sectionMatch.group(1)?.trim();
        if (section != null && section.isNotEmpty) {
          if (formattedLines.isNotEmpty) formattedLines.add('');
          formattedLines.add(section);
        }
        continue;
      }

      final listMatch = _listPattern.firstMatch(line);
      if (listMatch != null) {
        var itemText = listMatch.group(1) ?? '';
        itemText = itemText.replaceAllMapped(
          _boldPattern,
          (m) => m.group(1) ?? '',
        );
        itemText = itemText.replaceAllMapped(
          _codePattern,
          (m) => m.group(1) ?? '',
        );
        formattedLines.add('• $itemText');
        continue;
      }

      final subListMatch = _subListPattern.firstMatch(line);
      if (subListMatch != null) {
        var itemText = subListMatch.group(1) ?? '';
        itemText = itemText.replaceAllMapped(
          _boldPattern,
          (m) => m.group(1) ?? '',
        );
        formattedLines.add('  - $itemText');
        continue;
      }
    }

    var formatted = formattedLines.join('\n').trim();
    if (formatted.length > 2000) {
      formatted = '${formatted.substring(0, 2000)}...';
    }

    return formatted.isEmpty ? emptyFallback : formatted;
  }
}
