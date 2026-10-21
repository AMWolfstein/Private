part of 'queue_tab.dart';

enum _CollectionEntryType { loved, favoriteArtists, playlist }

class _CollectionEntry {
  final _CollectionEntryType type;
  final int playlistIndex;

  const _CollectionEntry._(this.type, [this.playlistIndex = -1]);

  static _CollectionEntry playlist(int index) =>
      _CollectionEntry._(_CollectionEntryType.playlist, index);
}
