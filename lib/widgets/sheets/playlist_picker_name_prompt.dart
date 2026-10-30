import 'package:flutter/material.dart';
import 'package:sistrum/widgets/library/playlist_name_dialog.dart';

/// Asks for a new playlist's name, starting from [playlistNamePrefill].
Future<String?> promptPlaylistName(
  BuildContext context,
  String? playlistNamePrefill,
) => showPlaylistNameDialog(context, prefill: playlistNamePrefill);
