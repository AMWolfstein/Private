import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/providers/local_library_provider.dart';
import 'package:sistrum/services/deleted_library_files.dart';
import 'package:sistrum/services/ffmpeg_cue.dart';
import 'package:sistrum/services/ffmpeg_models.dart';
import 'package:sistrum/services/library_database.dart';
import 'package:sistrum/services/library_database_models.dart';
import 'package:sistrum/services/platform_bridge.dart';
import 'package:sistrum/utils/file_access.dart';
import 'package:sistrum/utils/mime_utils.dart';
import 'package:sistrum/utils/path_match_keys.dart';
import 'package:sistrum/widgets/app_alert_dialog.dart';

bool isCueSong(LocalLibraryItem item) =>
    isCueBackedRow(item.filePath, item.format);

/// Splits of the same backing CUE sheet that are still running, keyed by the
/// sheet path, so a second tap cannot start a duplicate export.
final _cueSplitsInFlight = <String>{};

/// Exports [paths] to the picked SAF [tree] and returns how many files were
/// created. A cover embed failure on one file must not abort the remaining
/// exports.
@visibleForTesting
Future<int> exportCueSplitOutputs(
  List<String> paths, {
  required String tree,
  String? coverPath,
  Future<void> Function(String path, String coverPath)? embedCover,
  Future<String?> Function(String path)? createFile,
}) async {
  final embed =
      embedCover ??
      (path, cover) =>
          PlatformBridge.editFileMetadata(path, {'cover_path': cover});
  final create =
      createFile ??
      (path) => PlatformBridge.createSafFileFromPath(
        treeUri: tree,
        relativeDir: '',
        fileName: path.split(Platform.pathSeparator).last,
        mimeType: audioMimeTypeForPath(path),
        srcPath: path,
      );
  var exported = 0;
  for (final path in paths) {
    if (coverPath != null && path.endsWith('.flac')) {
      try {
        await embed(path, coverPath);
      } catch (_) {
        /* Artwork is optional; keep exporting the other tracks. */
      }
    }
    String? uri;
    try {
      uri = await create(path);
    } catch (_) {
      /* One rejected copy must not abort the remaining tracks. */
    }
    if (uri?.isNotEmpty == true) exported++;
  }
  return exported;
}

/// Canonical `<volume>:<relative path>` for a SAF tree or a removable-volume
/// storage path. The shared path-match keys only alias primary storage, and
/// older Android versions store a library source as a filesystem path.
String? _storageVolumeLocation(String value) {
  final uri = Uri.tryParse(value);
  if (uri != null && uri.scheme == 'content' && !uri.hasFragment) {
    final segments = uri.pathSegments;
    final treeIndex = segments.lastIndexOf('tree');
    if (treeIndex < 0 || treeIndex + 1 >= segments.length) return null;
    final documentId = segments.sublist(treeIndex + 1).join('/');
    final separator = documentId.indexOf(':');
    if (separator <= 0) return null;
    final volume = documentId.substring(0, separator).toLowerCase();
    if (volume == 'primary') return null;
    return '$volume:${_normalizeRelativePath(documentId.substring(separator + 1))}';
  }
  if (!value.startsWith('/')) return null;
  final match = RegExp(
    r'^/storage/([^/]+)(?:/(.*))?$',
  ).firstMatch(value.replaceAll('\\', '/'));
  if (match == null) return null;
  final volume = match.group(1)!.toLowerCase();
  if (volume == 'emulated' || volume == 'self') return null;
  return '$volume:${_normalizeRelativePath(match.group(2) ?? '')}';
}

String _normalizeRelativePath(String value) => value
    .replaceAll('\\', '/')
    .replaceAll(RegExp(r'^/+'), '')
    .replaceAll(RegExp(r'/+$'), '');

/// The library source whose folder contains the picked SAF [tree], if any.
///
/// A source can be stored as a filesystem path (older Android versions) while
/// the picker always returns a SAF tree URI, so both sides are reduced to
/// physical-path match keys (and removable-volume locations) instead of
/// comparing their literal strings.
@visibleForTesting
LocalLibrarySource? cueSplitDestinationSource(
  List<LocalLibrarySource> sources,
  String tree,
) {
  final treeKeys = buildPathMatchKeys(tree);
  final treeLocation = _storageVolumeLocation(tree);
  for (final source in sources) {
    if (source.path.isEmpty) continue;
    final matchedByKey = buildPathMatchKeys(source.path).any(
      (sourceKey) => treeKeys.any(
        (treeKey) =>
            treeKey == sourceKey ||
            treeKey.startsWith('$sourceKey/') ||
            treeKey.toLowerCase().startsWith('${sourceKey.toLowerCase()}%2f'),
      ),
    );
    if (matchedByKey) return source;
    final sourceLocation = _storageVolumeLocation(source.path);
    if (treeLocation != null && sourceLocation != null) {
      final sourcePrefix = sourceLocation.endsWith(':')
          ? sourceLocation
          : '$sourceLocation/';
      if (treeLocation == sourceLocation ||
          treeLocation.startsWith(sourcePrefix)) {
        return source;
      }
    }
  }
  return null;
}

/// Marks whether the split landed inside a library source and schedules a
/// rescan of that source.
@visibleForTesting
bool cueSplitHandleDestination(
  ProviderContainer container,
  String tree, {
  required int exported,
}) {
  if (exported <= 0) return false;
  final source = cueSplitDestinationSource(
    container.read(localLibraryProvider).sources,
    tree,
  );
  if (source == null) return false;
  if (source.enabled && source.available) {
    unawaited(
      container.read(localLibraryProvider.notifier).startSourceScan(source.id),
    );
  }
  return true;
}

/// Failures reported by the split plus outputs the export layer dropped.
@visibleForTesting
int cueSplitFailureCount(int? splitFailed, int splitPaths, int exported) =>
    (splitFailed ?? 0) + splitPaths - exported;

/// Snackbar text for a finished CUE split.
@visibleForTesting
String cueSplitResultMessage(
  AppLocalizations l10n,
  int exported,
  int failed,
  bool insideLibrary,
) {
  if (exported == 0) return l10n.cueSplitFailed;
  return [
    failed > 0
        ? l10n.cueSplitPartialSuccess(exported, failed)
        : l10n.cueSplitSuccess(exported),
    if (!insideLibrary) l10n.cueSplitSavedOutsideLibrary,
  ].join('\n');
}

Future<void> copyLocalSongPath(
  BuildContext context,
  LocalLibraryItem item,
) async {
  await Clipboard.setData(ClipboardData(text: item.filePath));
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.trackCopiedToClipboard)),
    );
  }
}

Future<void> shareLocalSong(BuildContext context, LocalLibraryItem item) async {
  final title = '${item.trackName} - ${item.artistName}';
  if (isContentUri(item.filePath)) {
    if (!await PlatformBridge.shareContentUri(item.filePath, title: title)) {
      throw StateError('Could not share the audio file');
    }
  } else {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(item.filePath)],
        text: title,
        sharePositionOrigin: context.findRenderObject() is RenderBox
            ? (context.findRenderObject() as RenderBox).localToGlobal(
                    Offset.zero,
                  ) &
                  (context.findRenderObject() as RenderBox).size
            : null,
      ),
    );
  }
}

Future<bool> deleteLocalSong(
  BuildContext context,
  LocalLibraryItem item,
) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final confirmed = await showAppDialog<bool>(
    context: context,
    builder: (dialogContext) => AppAlertDialog(
      title: Text(dialogContext.l10n.trackDeleteConfirmTitle),
      content: Text(dialogContext.l10n.trackDeleteConfirmMessage),
      actions: [
        AppDialogAction(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(dialogContext.l10n.dialogCancel),
        ),
        AppDialogAction(
          isDestructive: true,
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(dialogContext.l10n.dialogDelete),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  // A CUE row only drops its virtual row; the shared sheet and audio stay.
  final result = await deleteLocalLibraryTracks(container, [item]);
  final deleted = result.deletedCount > 0;
  if (!deleted && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.snackbarDeleteTracksFailed(1))),
    );
  }
  return deleted;
}

/// Splits the backing CUE album into a user-selected local SAF folder.
/// All processing uses a private temporary directory; the source is untouched.
Future<void> splitLocalCue(BuildContext context, LocalLibraryItem item) async {
  final cuePath = stripCueTrackSuffix(item.filePath);
  if (!_cueSplitsInFlight.add(cuePath)) {
    // A split of the same sheet is still running; tapping again must not start
    // a second FFmpeg job or write duplicate files.
    return;
  }
  Directory? staging;
  String? copiedAudio;
  final messenger = ScaffoldMessenger.of(context);
  void message(String text) {
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  try {
    final info = await PlatformBridge.parseCueSheet(cuePath);
    if (!context.mounted) return;
    final audioPath = info['audio_path'] as String? ?? '';
    final tracks = [
      for (final row in info['tracks'] as List? ?? [])
        CueSplitTrackInfo.fromJson(Map<String, dynamic>.from(row as Map)),
    ];
    if (info['error'] != null || audioPath.isEmpty || tracks.isEmpty) {
      message(context.l10n.cueSplitFailed);
      return;
    }
    final album = info['album'] as String? ?? item.albumName;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AppAlertDialog(
        title: Text(dialogContext.l10n.cueSplitConfirmTitle),
        content: Text(
          dialogContext.l10n.cueSplitConfirmMessage(album, tracks.length),
        ),
        actions: [
          AppDialogAction(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(dialogContext.l10n.dialogCancel),
          ),
          AppDialogAction(
            filled: true,
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(dialogContext.l10n.cueSplitButton),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final destination = await PlatformBridge.pickSafTree(
      onFailure: (message) {
        if (context.mounted) {
          messenger.showSnackBar(SnackBar(content: Text(message)));
        }
      },
    );
    final tree = destination?['tree_uri'] as String? ?? '';
    if (tree.isEmpty || !context.mounted) return;
    staging = await (await getTemporaryDirectory()).createTemp('cue_split_');
    var workingAudio = audioPath;
    if (isContentUri(audioPath)) {
      copiedAudio = await PlatformBridge.copyContentUriToTemp(audioPath);
      if (copiedAudio == null || copiedAudio.isEmpty) {
        throw StateError('Could not read CUE audio');
      }
      workingAudio = copiedAudio;
    }
    String? coverPath;
    final coverOutput = '${staging.path}/cover.jpg';
    try {
      final coverResult = await PlatformBridge.extractCoverToFile(
        workingAudio,
        coverOutput,
      );
      if (coverResult['error'] == null && await File(coverOutput).exists()) {
        coverPath = coverOutput;
      }
    } catch (_) {
      /* A CUE album can be split without artwork. */
    }
    final result = await FFmpegCue.splitCueToTracks(
      audioPath: workingAudio,
      outputDir: staging.path,
      tracks: tracks,
      albumMetadata: {
        'artist': info['artist'] as String? ?? item.artistName,
        'album': album,
        'genre': info['genre'] as String? ?? '',
        'date': info['date'] as String? ?? '',
      },
      coverPath: coverPath,
      onProgress: (current, total) {
        if (context.mounted) {
          message(context.l10n.cueSplitSplitting(current, total));
        }
      },
    );
    final splitPaths = result?.paths ?? const <String>[];
    final exported = await exportCueSplitOutputs(
      splitPaths,
      tree: tree,
      coverPath: coverPath,
    );
    // Outputs the export layer could not copy are failures too, so a partial
    // split never reports every track as saved.
    final failed = cueSplitFailureCount(
      result?.failed,
      splitPaths.length,
      exported,
    );
    var insideLibrary = false;
    if (context.mounted) {
      // Files written into an indexed folder only appear after a scan.
      insideLibrary = cueSplitHandleDestination(
        ProviderScope.containerOf(context, listen: false),
        tree,
        exported: exported,
      );
    }
    if (context.mounted) {
      message(
        cueSplitResultMessage(context.l10n, exported, failed, insideLibrary),
      );
    }
  } catch (error) {
    if (context.mounted) message(context.l10n.cueSplitFailed);
  } finally {
    _cueSplitsInFlight.remove(cuePath);
    if (copiedAudio != null) {
      try {
        await File(copiedAudio).delete();
      } catch (_) {}
    }
    if (staging != null) {
      try {
        await staging.delete(recursive: true);
      } catch (_) {}
    }
  }
}
