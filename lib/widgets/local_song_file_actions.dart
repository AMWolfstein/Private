import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:spotiflac_android/l10n/l10n.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/services/deleted_library_files.dart';
import 'package:spotiflac_android/services/ffmpeg_service.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/services/platform_bridge.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/mime_utils.dart';
import 'package:spotiflac_android/widgets/app_alert_dialog.dart';

bool isCueSong(LocalLibraryItem item) =>
    isCueVirtualPath(item.filePath) ||
    item.filePath.toLowerCase().endsWith('.cue') ||
    (item.format?.startsWith('cue+') ?? false);

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
  if (isCueVirtualPath(item.filePath)) {
    // A virtual row shares its backing CUE/audio with other tracks.
    await container.read(localLibraryProvider.notifier).removeItem(item.id);
    return true;
  }
  if (!await deleteFile(item.filePath)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(context.l10n.snackbarDeleteTracksFailed(1))),
      );
    }
    return false;
  }
  await removeDeletedLibraryFileEntries(container, [item.filePath]);
  return true;
}

/// Splits the backing CUE album into a user-selected local SAF folder.
/// All processing uses a private temporary directory; the source is untouched.
Future<void> splitLocalCue(BuildContext context, LocalLibraryItem item) async {
  Directory? staging;
  String? copiedAudio;
  final messenger = ScaffoldMessenger.of(context);
  void message(String text) {
    if (!context.mounted) return;
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(content: Text(text)));
  }

  try {
    final info = await PlatformBridge.parseCueSheet(
      stripCueTrackSuffix(item.filePath),
    );
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
    final destination = await PlatformBridge.pickSafTree();
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
    final paths = await FFmpegService.splitCueToTracks(
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
    var exported = 0;
    for (final path in paths ?? <String>[]) {
      if (coverPath != null && path.endsWith('.flac')) {
        await PlatformBridge.editFileMetadata(path, {'cover_path': coverPath});
      }
      final uri = await PlatformBridge.createSafFileFromPath(
        treeUri: tree,
        relativeDir: '',
        fileName: path.split(Platform.pathSeparator).last,
        mimeType: audioMimeTypeForPath(path),
        srcPath: path,
      );
      if (uri?.isNotEmpty == true) exported++;
    }
    if (context.mounted) {
      message(
        exported > 0
            ? context.l10n.cueSplitSuccess(exported)
            : context.l10n.cueSplitFailed,
      );
    }
  } catch (error) {
    if (context.mounted) message(context.l10n.cueSplitFailed);
  } finally {
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
