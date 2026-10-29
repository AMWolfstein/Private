import 'package:flutter/material.dart';
import 'package:sistrum/models/library_collections.dart';
import 'package:sistrum/navigation/app_screens.dart';
import 'package:sistrum/screens/library/library_collection_tracks_screen.dart';
import 'package:sistrum/screens/library/local_album_screen.dart';
import 'package:sistrum/screens/library/local_artist_screen.dart';
import 'package:sistrum/screens/now_playing_screen.dart';
import 'package:sistrum/services/library/library_database_models.dart';

/// The app's full pages, installed as [appScreensProvider].
class AppScreenBuilders implements AppScreens {
  const AppScreenBuilders();

  @override
  Widget artist({required String artistName, String? coverPath}) =>
      LocalArtistScreen(artistName: artistName, coverPath: coverPath);

  @override
  Widget album({
    required String albumName,
    required String artistName,
    String? coverPath,
    required List<LocalLibraryItem> tracks,
  }) => LocalAlbumScreen(
    albumName: albumName,
    artistName: artistName,
    coverPath: coverPath,
    tracks: tracks,
  );

  @override
  Widget collectionTracks({
    required LibraryCollectionMode mode,
    String? playlistId,
  }) => LibraryCollectionTracksScreen(mode: mode, playlistId: playlistId);

  @override
  Widget nowPlaying() => const NowPlayingScreen();
}
