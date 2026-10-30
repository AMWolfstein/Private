import 'package:json_annotation/json_annotation.dart';

part 'track.g.dart';

@JsonSerializable()
class Track {
  final String id;
  final String name;
  final String artistName;
  final String albumName;
  final String? albumArtist;
  final String? artistId;
  final String? albumId;
  final String? coverUrl;
  final String? isrc;
  final int duration;
  final int? trackNumber;
  final int? discNumber;
  final int? totalDiscs;
  final String? releaseDate;

  final String? source;
  final int? totalTracks;
  final String? composer;
  final String? genre;
  final String? label;
  final String? copyright;
  final String? comment;

  final bool? explicit;

  const Track({
    required this.id,
    required this.name,
    required this.artistName,
    required this.albumName,
    this.albumArtist,
    this.artistId,
    this.albumId,
    this.coverUrl,
    this.isrc,
    required this.duration,
    this.trackNumber,
    this.discNumber,
    this.totalDiscs,
    this.releaseDate,

    this.source,
    this.totalTracks,
    this.composer,
    this.genre,
    this.label,
    this.copyright,
    this.comment,

    this.explicit,
  });

  factory Track.fromJson(Map<String, dynamic> json) => _$TrackFromJson(json);
  Map<String, dynamic> toJson() => _$TrackToJson(this);

  Track copyWith({
    String? id,
    String? name,
    String? artistName,
    String? albumName,
    String? albumArtist,
    String? artistId,
    String? albumId,
    String? coverUrl,
    String? isrc,
    int? duration,
    int? trackNumber,
    int? discNumber,
    int? totalDiscs,
    String? releaseDate,

    String? source,
    int? totalTracks,
    String? composer,
    String? genre,
    String? label,
    String? copyright,
    String? comment,

    bool? explicit,
  }) {
    return Track(
      id: id ?? this.id,
      name: name ?? this.name,
      artistName: artistName ?? this.artistName,
      albumName: albumName ?? this.albumName,
      albumArtist: albumArtist ?? this.albumArtist,
      artistId: artistId ?? this.artistId,
      albumId: albumId ?? this.albumId,
      coverUrl: coverUrl ?? this.coverUrl,
      isrc: isrc ?? this.isrc,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      discNumber: discNumber ?? this.discNumber,
      totalDiscs: totalDiscs ?? this.totalDiscs,
      releaseDate: releaseDate ?? this.releaseDate,

      source: source ?? this.source,
      totalTracks: totalTracks ?? this.totalTracks,
      composer: composer ?? this.composer,
      genre: genre ?? this.genre,
      label: label ?? this.label,
      copyright: copyright ?? this.copyright,
      comment: comment ?? this.comment,

      explicit: explicit ?? this.explicit,
    );
  }

  bool get isExplicit => explicit == true;
}
