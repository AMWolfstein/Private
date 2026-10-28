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
  isrc: json['isrc'] as String?,
  duration: (json['duration'] as num).toInt(),
  trackNumber: (json['trackNumber'] as num?)?.toInt(),
  discNumber: (json['discNumber'] as num?)?.toInt(),
  totalDiscs: (json['totalDiscs'] as num?)?.toInt(),
  releaseDate: json['releaseDate'] as String?,
  source: json['source'] as String?,
  totalTracks: (json['totalTracks'] as num?)?.toInt(),
  composer: json['composer'] as String?,
  genre: json['genre'] as String?,
  label: json['label'] as String?,
  copyright: json['copyright'] as String?,
  comment: json['comment'] as String?,
  explicit: json['explicit'] as bool?,
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
  'isrc': instance.isrc,
  'duration': instance.duration,
  'trackNumber': instance.trackNumber,
  'discNumber': instance.discNumber,
  'totalDiscs': instance.totalDiscs,
  'releaseDate': instance.releaseDate,
  'source': instance.source,
  'totalTracks': instance.totalTracks,
  'composer': instance.composer,
  'genre': instance.genre,
  'label': instance.label,
  'copyright': instance.copyright,
  'comment': instance.comment,
  'explicit': instance.explicit,
};
