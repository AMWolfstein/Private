part of 'album_detail_header.dart';

extension _AlbumDetailHeaderPart1 on AlbumDetailHeader {
  /// Shrinks long titles so up to three lines fit the header.
  double _titleFontSize() {
    final length = title.trim().length;
    if (length > 45) return 18;
    if (length > 30) return 21;
    return 24;
  }
}
