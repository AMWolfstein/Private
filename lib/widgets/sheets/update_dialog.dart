import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sistrum/core/constants/app_info.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/services/platform/notification_service.dart';
import 'package:sistrum/services/platform/update_checker.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/utils/text/string_utils.dart';
import 'package:sistrum/widgets/primitives/app_alert_dialog.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateDialog extends StatefulWidget {
  final UpdateInfo updateInfo;
  final VoidCallback onDismiss;
  final VoidCallback onDisableUpdates;

  /// When true the dialog cannot be dismissed: the installed version is too
  /// many releases behind and updating is mandatory.
  final bool forced;

  const UpdateDialog({
    super.key,
    required this.updateInfo,
    required this.onDismiss,
    required this.onDisableUpdates,
    this.forced = false,
  });

  @override
  State<UpdateDialog> createState() => _UpdateDialogState();
}

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

class _VersionChip extends StatelessWidget {
  final String version;
  final String label;
  final ColorScheme colorScheme;
  final bool isNew;

  const _VersionChip({
    required this.version,
    required this.label,
    required this.colorScheme,
    this.isNew = false,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: Theme.of(
            context,
          ).textTheme.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 4),
        Text(
          'v$version',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: isNew ? colorScheme.primary : colorScheme.onSurfaceVariant,
            fontWeight: isNew ? FontWeight.bold : FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateInfo updateInfo,
  required VoidCallback onDisableUpdates,
  bool forced = false,
}) {
  return showAppDialog<void>(
    context: context,
    barrierDismissible: !forced,
    builder: (context) => UpdateDialog(
      updateInfo: updateInfo,
      onDismiss: () {},
      onDisableUpdates: onDisableUpdates,
      forced: forced,
    ),
  );
}

final _log = AppLogger('ApkDownloader');

typedef ProgressCallback = void Function(int received, int total);

/// Why an update download stopped; each reason has its own message.
enum ApkDownloadFailure {
  invalidUrl,
  storageUnavailable,
  server,
  transfer,
  incompleteDownload,
  invalidPayload,
  invalidDigest,
  digestMismatch,
}

sealed class ApkDownloadResult {
  const ApkDownloadResult();
}

final class ApkDownloaded extends ApkDownloadResult {
  const ApkDownloaded(this.path);

  final String path;
}

final class ApkDownloadFailed extends ApkDownloadResult {
  const ApkDownloadFailed(this.reason);

  final ApkDownloadFailure reason;
}

/// Whether the system installer opened for a downloaded APK.
enum ApkInstallOutcome { opened, noInstaller, failed }

Future<String> _hashApkInBackground(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

class ApkDownloader {
  static const _streamIdleTimeout = Duration(seconds: 60);

  static Future<ApkDownloadResult> downloadApk({
    required String url,
    required String version,
    String? expectedSha256,
    ProgressCallback? onProgress,
    http.Client? client,
    Directory? downloadDirectory,
  }) async {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != 'https') {
      _log.e('Refusing to download from invalid or non-HTTPS URL');
      return const ApkDownloadFailed(ApkDownloadFailure.invalidUrl);
    }

    final ownedClient = client == null;
    final effectiveClient = client ?? http.Client();
    IOSink? sink;

    try {
      final dir = downloadDirectory ?? await getExternalStorageDirectory();
      if (dir == null) {
        _log.e('Could not get storage directory');
        return const ApkDownloadFailed(ApkDownloadFailure.storageUnavailable);
      }
      await dir.create(recursive: true);

      final safeVersion = version.replaceAll(RegExp(r'[^a-zA-Z0-9._-]'), '_');
      final finalFile = File(
        '${dir.path}${Platform.pathSeparator}Sistrum-$safeVersion.apk',
      );
      final partFile = File('${finalFile.path}.part');
      final metadataFile = File('${partFile.path}.json');
      final metadata = await _readResumeMetadata(metadataFile);

      var resumeOffset = 0;
      if (await partFile.exists() && metadata?['url'] == url) {
        resumeOffset = await partFile.length();
      } else {
        if (await partFile.exists()) await partFile.delete();
        if (await metadataFile.exists()) await metadataFile.delete();
      }

      final request = http.Request('GET', uri);
      if (resumeOffset > 0) {
        request.headers['Range'] = 'bytes=$resumeOffset-';
        final etag = metadata?['etag']?.toString() ?? '';
        if (etag.isNotEmpty) request.headers['If-Range'] = etag;
      }

      final response = await effectiveClient
          .send(request)
          .timeout(const Duration(seconds: 30));
      final isResume = resumeOffset > 0 && response.statusCode == 206;
      if (response.statusCode == 206 &&
          !_contentRangeStartsAt(response, resumeOffset)) {
        _log.w('Server returned an invalid Content-Range; clearing partial');
        await _discardPartial(partFile, metadataFile);
        return const ApkDownloadFailed(ApkDownloadFailure.server);
      }
      if (response.statusCode == 416) {
        _log.w('Server rejected the saved download range; clearing partial');
        await _discardPartial(partFile, metadataFile);
        return const ApkDownloadFailed(ApkDownloadFailure.server);
      }
      if (response.statusCode != 200 && response.statusCode != 206) {
        _log.e('Failed to download: ${response.statusCode}');
        return const ApkDownloadFailed(ApkDownloadFailure.server);
      }

      if (!isResume) resumeOffset = 0;
      final total = _responseTotalBytes(response, resumeOffset);
      await metadataFile.writeAsString(
        jsonEncode({
          'url': url,
          'etag': response.headers['etag'] ?? '',
          'total': total,
        }),
        flush: true,
      );

      sink = partFile.openWrite(
        mode: isResume ? FileMode.append : FileMode.writeOnly,
      );
      var received = resumeOffset;
      onProgress?.call(received, total);
      await for (final chunk in response.stream.timeout(_streamIdleTimeout)) {
        sink.add(chunk);
        received += chunk.length;
        onProgress?.call(received, total);
      }
      await sink.flush();
      await sink.close();
      sink = null;

      if (total > 0 && received != total) {
        _log.w('Incomplete APK download: $received/$total bytes');
        return const ApkDownloadFailed(ApkDownloadFailure.incompleteDownload);
      }
      if (!await _looksLikeApk(partFile)) {
        _log.e('Downloaded update is not a valid APK/ZIP payload');
        await _discardPartial(partFile, metadataFile);
        return const ApkDownloadFailed(ApkDownloadFailure.invalidPayload);
      }

      final expected = expectedSha256?.trim().toLowerCase() ?? '';
      if (expected.isNotEmpty) {
        if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(expected)) {
          _log.e('Release supplied an invalid SHA-256 digest');
          await _discardPartial(partFile, metadataFile);
          return const ApkDownloadFailed(ApkDownloadFailure.invalidDigest);
        }
        final actual = await _hashApk(partFile);
        if (actual != expected) {
          _log.e('APK SHA-256 verification failed');
          await _discardPartial(partFile, metadataFile);
          return const ApkDownloadFailed(ApkDownloadFailure.digestMismatch);
        }
      }

      if (await finalFile.exists()) await finalFile.delete();
      await partFile.rename(finalFile.path);
      if (await metadataFile.exists()) await metadataFile.delete();
      _log.i(
        'Downloaded verified update to ${finalFile.path}'
        '${expected.isEmpty ? ' (release digest unavailable)' : ''}',
      );
      return ApkDownloaded(finalFile.path);
    } catch (e) {
      _log.e('Update download paused after error: $e');
      return const ApkDownloadFailed(ApkDownloadFailure.transfer);
    } finally {
      try {
        await sink?.close();
      } catch (error) {
        _log.w('Failed to close partial update file: $error');
      } finally {
        if (ownedClient) effectiveClient.close();
      }
    }
  }

  static Future<String> _hashApk(File file) =>
      compute(_hashApkInBackground, file.path);

  static Future<Map<String, dynamic>?> _readResumeMetadata(File file) async {
    try {
      if (!await file.exists()) return null;
      final decoded = jsonDecode(await file.readAsString());
      return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
    } catch (_) {
      return null;
    }
  }

  static bool _contentRangeStartsAt(
    http.StreamedResponse response,
    int expected,
  ) {
    final value = response.headers['content-range'] ?? '';
    final match = RegExp(r'^bytes (\d+)-(\d+)/(\d+|\*)$').firstMatch(value);
    return match != null && int.tryParse(match.group(1)!) == expected;
  }

  static int _responseTotalBytes(
    http.StreamedResponse response,
    int resumeOffset,
  ) {
    final range = response.headers['content-range'] ?? '';
    final match = RegExp(r'/([0-9]+)$').firstMatch(range);
    final rangeTotal = match == null ? null : int.tryParse(match.group(1)!);
    return rangeTotal ??
        ((response.contentLength ?? 0) > 0
            ? resumeOffset + response.contentLength!
            : 0);
  }

  static Future<bool> _looksLikeApk(File file) async {
    try {
      if (await file.length() < 4) return false;
      final header = await file
          .openRead(0, 4)
          .fold<List<int>>(<int>[], (bytes, chunk) => bytes..addAll(chunk));
      return header.length == 4 &&
          header[0] == 0x50 &&
          header[1] == 0x4b &&
          header[2] == 0x03 &&
          header[3] == 0x04;
    } catch (_) {
      return false;
    }
  }

  static Future<void> _discardPartial(File part, File metadata) async {
    if (await part.exists()) await part.delete();
    if (await metadata.exists()) await metadata.delete();
  }

  static Future<ApkInstallOutcome> installApk(String filePath) async {
    try {
      final result = await OpenFilex.open(filePath);
      _log.i('Open result: ${result.type} - ${result.message}');
      return switch (result.type) {
        ResultType.done => ApkInstallOutcome.opened,
        ResultType.noAppToOpen => ApkInstallOutcome.noInstaller,
        _ => ApkInstallOutcome.failed,
      };
    } catch (e) {
      _log.e('Install error: $e');
      return ApkInstallOutcome.failed;
    }
  }
}
