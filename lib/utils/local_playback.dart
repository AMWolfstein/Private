import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/local_library_provider.dart';
import 'package:spotiflac_android/providers/music_player_provider.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/widgets/app_snack_bar.dart';

/// Plays [track] from the local library when a matching file already exists on
/// disk.
///
/// Returns true when playback started (or when an error was surfaced to the
/// user), so callers can skip enqueueing a download; returns false when no
/// local copy is available.
Future<bool> playLocalIfAvailable(
  BuildContext context,
  WidgetRef ref,
  Track track,
) async {
  try {
    final isrc = track.isrc?.trim();
    final localItem = await ref
        .read(localLibraryProvider.notifier)
        .findExistingAsync(
          id: track.id,
          isrc: isrc,
          trackName: track.name,
          artistName: track.artistName,
        );

    if (localItem != null && await fileExists(localItem.filePath)) {
      await ref.read(musicPlayerControllerProvider).playLocal([localItem]);
      return true;
    }
  } catch (e) {
    if (context.mounted) showCannotOpenFileSnackBar(context, e);
    return true;
  }

  return false;
}
