import 'package:sistrum/core/models/local_library_item.dart';
import 'package:sistrum/core/models/playable_media.dart';

PlayableMedia playableFromLocal(LocalLibraryItem item) {
  String? art;
  final cover = item.coverPath;
  // A legacy remote URL is not artwork here: keep it out of playback state.
  if (cover != null && cover.trim().isNotEmpty && !cover.startsWith('http')) {
    art = cover.startsWith('content://') ? cover : Uri.file(cover).toString();
  }
  return PlayableMedia(
    id: item.id,
    source: item.filePath,
    title: item.trackName,
    artist: item.artistName,
    album: item.albumName,
    artUri: art,
    duration: (item.duration != null && item.duration! > 0)
        ? Duration(seconds: item.duration!)
        : null,
    bitDepth: item.bitDepth,
    sampleRate: item.sampleRate,
    bitrate: item.bitrate,
    format: item.format,
    explicit: item.explicit,
    genre: item.genre,
  );
}
