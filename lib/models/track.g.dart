// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'track.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

Track _$TrackFromJson(Map<String, dynamic> json) => Track(
  id: json['id'] as String,
  name: json['name'] as String,
  artistName: json['artistName'] as String,
  albumName: json['albumName'] as String,
  albumArtist: json['albumArtist'] as String?,
  artistId: json['artistId'] as String?,
  albumId: json['albumId'] as String?,
  coverUrl: json['coverUrl'] as String?,
  headerVideoUrl: json['headerVideoUrl'] as String?,
  isrc: json['isrc'] as String?,
  previewUrl: json['previewUrl'] as String?,
  duration: (json['duration'] as num).toInt(),
  trackNumber: (json['trackNumber'] as num?)?.toInt(),
  discNumber: (json['discNumber'] as num?)?.toInt(),
  totalDiscs: (json['totalDiscs'] as num?)?.toInt(),
  releaseDate: json['releaseDate'] as String?,
  source: json['source'] as String?,
  albumType: json['albumType'] as String?,
  totalTracks: (json['totalTracks'] as num?)?.toInt(),
  composer: json['composer'] as String?,
  genre: json['genre'] as String?,
  label: json['label'] as String?,
  copyright: json['copyright'] as String?,
  comment: json['comment'] as String?,
  itemType: json['itemType'] as String?,
  audioQuality: json['audioQuality'] as String?,
  explicit: json['explicit'] as bool?,
  upc: json['upc'] as String?,
);

Map<String, dynamic> _$TrackToJson(Track instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'artistName': instance.artistName,
  'albumName': instance.albumName,
  'albumArtist': instance.albumArtist,
  'artistId': instance.artistId,
  'albumId': instance.albumId,
  'coverUrl': instance.coverUrl,
  'headerVideoUrl': instance.headerVideoUrl,
  'isrc': instance.isrc,
  'previewUrl': instance.previewUrl,
  'duration': instance.duration,
  'trackNumber': instance.trackNumber,
  'discNumber': instance.discNumber,
  'totalDiscs': instance.totalDiscs,
  'releaseDate': instance.releaseDate,
  'source': instance.source,
  'albumType': instance.albumType,
  'totalTracks': instance.totalTracks,
  'composer': instance.composer,
  'genre': instance.genre,
  'label': instance.label,
  'copyright': instance.copyright,
  'comment': instance.comment,
  'itemType': instance.itemType,
  'audioQuality': instance.audioQuality,
  'explicit': instance.explicit,
  'upc': instance.upc,
};
