import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotiflac_android/models/download_history.dart';
import 'package:spotiflac_android/models/settings.dart';
import 'package:spotiflac_android/models/theme_settings.dart';
import 'package:spotiflac_android/models/track.dart';
import 'package:spotiflac_android/providers/library_collections_provider.dart';
import 'package:spotiflac_android/services/library_database.dart';
import 'package:spotiflac_android/utils/artist_utils.dart';
import 'package:spotiflac_android/utils/audio_format_utils.dart';
import 'package:spotiflac_android/utils/file_access.dart';
import 'package:spotiflac_android/utils/mime_utils.dart';
import 'package:spotiflac_android/utils/path_match_keys.dart';
import 'package:spotiflac_android/utils/string_utils.dart';

void main() {
  group('Finalized SAF audio names', () {});

  group('file deletion', () {
    test('confirms a local file is absent before reporting success', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'spotiflac-delete-test-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}${Platform.pathSeparator}track.flac');
      await file.writeAsBytes([1, 2, 3]);

      expect(await deleteFile(file.path), isTrue);
      expect(await file.exists(), isFalse);
      expect(await deleteFile(file.path), isTrue);
    });

    test('refuses to delete a virtual CUE track path', () async {
      expect(await deleteFile('/music/album.cue#track01'), isFalse);
    });

    test('only a .cue base marks a virtual row', () {
      expect(isCueVirtualPath('/music/album.cue#track01'), isTrue);
      expect(isCueVirtualPath('/music/ALBUM.CUE#track12'), isTrue);
      expect(
        isCueVirtualPath('content://tree/album/song#track2.flac'),
        isFalse,
      );
      expect(isCueVirtualPath('content://tree/album/album.cue#track2'), isTrue);
      expect(isCueVirtualPath('/music/Song #track1'), isFalse);
      expect(isCueVirtualPath('/music/Song #track1.flac'), isFalse);
      expect(isCueBackedPath('/music/Song #track1.flac'), isFalse);
      expect(isCueBackedPath('/music/album.cue'), isTrue);
      expect(isCueBackedRow('/music/album.cue#track01', 'cue+flac'), isTrue);
      expect(isCueBackedRow('/music/album.cue', 'flac'), isTrue);
      expect(isCueBackedRow('/music/backing.flac', 'cue+flac'), isTrue);
      expect(isCueBackedRow('/music/song.flac', 'flac'), isFalse);
      expect(
        stripCueTrackSuffix('/music/album.cue#track01'),
        '/music/album.cue',
      );
      expect(
        stripCueTrackSuffix('/music/Song #track1.flac'),
        '/music/Song #track1.flac',
      );
    });

    test('a real file named with a #track suffix is not a CUE row', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'spotiflac-cue-suffix-',
      );
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });
      final file = File('${tempDir.path}${Platform.pathSeparator}Song #track1');
      await file.writeAsBytes([1, 2, 3]);

      expect(isCueVirtualPath(file.path), isFalse);
      expect(await fileExistenceByPath([file.path]), {file.path: true});
      expect(await deleteFile(file.path), isTrue);
      expect(await file.exists(), isFalse);
    });
  });

  group('local library incremental scan', () {
    test('rescans legacy metadata rows exactly once', () {
      expect(
        libraryIncrementalSnapshotModTime(
          storedModTime: 1234,
          storedScanVersion: 0,
        ),
        -1,
      );
      expect(
        libraryIncrementalSnapshotModTime(
          storedModTime: 1234,
          storedScanVersion: LibraryDatabase.audioMetadataScanVersion,
        ),
        1234,
      );
    });

    test('recognizes a retained external source index', () {
      final offlineSource = LocalLibrarySource(
        id: 'external-ssd',
        path: 'content://music/tree/SSD%3AMusic',
        displayName: 'SSD/Music',
        isRemovable: true,
        available: false,
        trackCount: 1200,
      );

      expect(offlineSource.isIndexed, isTrue);
      expect(offlineSource.available, isFalse);
      expect(offlineSource.copyWith(available: true).trackCount, 1200);
    });
  });

  group('ReplayGain metadata availability', () {
    test(
      'recognizes track or album gain including zero, but not peak alone',
      () {
        for (final value in ['0.00 dB', '-7.25 dB', ' +2.1 DB ', 0, -4.5]) {
          expect(
            metadataHasReplayGain({'replaygain_track_gain': value}),
            isTrue,
          );
          expect(
            metadataHasReplayGain({'replaygain_album_gain': value}),
            isTrue,
          );
        }
        for (final value in [null, '', 'dB', 'NaN', 'Infinity', 'not a gain']) {
          expect(
            metadataHasReplayGain({'replaygain_track_gain': value}),
            isFalse,
          );
        }
        expect(
          metadataHasReplayGain({'replaygain_track_peak': '0.99'}),
          isFalse,
        );
      },
    );

    test('history round-trip preserves known absence after removing gain', () {
      final item = DownloadHistoryItem(
        id: 'gain',
        trackName: 'Track',
        artistName: 'Artist',
        albumName: 'Album',
        filePath: '/music/track.flac',
        service: 'test',
        downloadedAt: DateTime.utc(2026),
        hasReplayGain: true,
        replayGainMetadataScanVersion: 1,
      );
      final tagged = DownloadHistoryItem.fromJson(item.toJson());
      expect(tagged.hasReplayGain, isTrue);
      final removed = DownloadHistoryItem.fromJson(
        tagged.copyWith(hasReplayGain: false).toJson(),
      );
      expect(removed.hasReplayGain, isFalse);
      expect(removed.replayGainMetadataScanVersion, 1);
      final legacy = item.toJson()
        ..remove('hasReplayGain')
        ..remove('replayGainMetadataScanVersion');
      expect(
        DownloadHistoryItem.fromJson(legacy).replayGainMetadataScanVersion,
        0,
      );
    });

    test('local scan flags survive serialization', () {
      final item = LocalLibraryItem.fromJson({
        'id': 'local-gain',
        'trackName': 'Track',
        'artistName': 'Artist',
        'albumName': 'Album',
        'filePath': '/music/track.flac',
        'scannedAt': DateTime.utc(2026).toIso8601String(),
        'replaygain_album_gain': '-6.2 dB',
        'hasLyrics': true,
      });
      expect(LocalLibraryItem.fromJson(item.toJson()).hasReplayGain, isTrue);
    });
  });

  group('missing lyrics filter', () {
    test(
      'requires a completed lyrics scan before treating false as missing',
      () {
        final predicate = confirmedMissingLyricsSqlPredicate(
          hasLyricsExpr: 'item.has_lyrics',
          lyricsKnownExpr: 'item.lyrics_scan_version >= 1',
        );

        expect(predicate, contains('item.lyrics_scan_version >= 1'));
        expect(predicate, contains('COALESCE(item.has_lyrics, 0) = 0'));
      },
    );
  });

  group('app state database migrations', () {
    final source = File(
      'lib/services/app_state_database.dart',
    ).readAsStringSync();

    test('v4 normalizes playback queue and scalar state', () {
      expect(source, contains('await _migratePlaybackSessionToV4(db);'));
      expect(source, contains('media_json TEXT NOT NULL'));
      expect(source, contains('position_ms INTEGER NOT NULL DEFAULT 0'));
      expect(source, contains('updatePlaybackSessionState'));
    });

    test('v5 drops the retired recent-access tables', () {
      expect(source, contains('const _dbVersion = 5;'));
      expect(source, contains('DROP TABLE IF EXISTS'));
      for (final table in [
        'recent_access_items',
        'hidden_recent_downloads',
        'recent_access_state',
      ]) {
        expect(source, contains("'$table'"));
      }
    });
  });

  group('quality variant filenames', () {
    test('uses measured lossless specifications instead of request labels', () {
      expect(
        buildQualityVariantFilenameLabel(
          detectedFormat: 'flac',
          bitDepth: 24,
          sampleRate: 96000,
          measuredQuality: 'LOSSLESS',
        ),
        '24bit-96kHz',
      );
      expect(
        buildQualityVariantFilenameLabel(
          detectedFormat: 'flac',
          measuredQuality: 'LOSSLESS',
        ),
        isNull,
      );
    });

    test('uses measured bitrate for lossy output', () {
      expect(
        buildQualityVariantFilenameLabel(
          detectedFormat: 'mp3',
          bitrateKbps: 320,
        ),
        '320kbps',
      );
      expect(
        buildQualityVariantFilenameLabel(
          detectedFormat: 'opus',
          measuredQuality: 'OPUS 256kbps',
        ),
        '256kbps',
      );
    });
  });

  group('Library collections', () {
    test('keeps playlist membership without eagerly loading track JSON', () {
      final playlist = UserPlaylistCollection(
        id: 'playlist-1',
        name: 'Playlist',
        createdAt: DateTime.utc(2026),
        updatedAt: DateTime.utc(2026),
        tracks: const [],
        previewCover: 'https://example.test/cover.jpg',
        tracksLoaded: false,
        trackKeys: {'track:a', 'track:b'},
      );

      expect(playlist.tracks, isEmpty);
      expect(playlist.tracksLoaded, isFalse);
      expect(playlist.trackCount, 2);
      expect(playlist.containsTrackKey('track:a'), isTrue);
      expect(playlist.previewCover, 'https://example.test/cover.jpg');

      final loaded = playlist.copyWith(
        tracks: [
          CollectionTrackEntry(
            key: 'track:a',
            track: const Track(
              id: 'a',
              name: 'A',
              artistName: 'Artist',
              albumName: 'Album',
              duration: 1000,
            ),
            addedAt: DateTime.utc(2026),
          ),
        ],
      );
      expect(loaded.tracksLoaded, isTrue);
      expect(loaded.trackCount, 1);
    });
  });

  group('Track', () {
    test('preserves a generic extension explicit flag', () {
      final track = Track.fromBackendMap({
        'id': 'extension-track-1',
        'name': 'Explicit Song',
        'artists': 'Artist',
        'album_name': 'Album',
        'duration_ms': 180000,
        'provider_id': 'extension.example',
        'explicit': true,
      });

      expect(track.source, 'extension.example');
      expect(track.explicit, isTrue);
      expect(track.isExplicit, isTrue);
    });

    test('preserves extension tagging metadata', () {
      final track = Track.fromBackendMap({
        'id': 'extension-track-1',
        'name': 'Song',
        'artists': 'Artist',
        'album_name': 'Album',
        'duration_ms': 180000,
        'genre': 'Pop',
        'label': 'Label',
        'copyright': 'Copyright',
        'composer': 'Composer',
        'comment': 'https://example.test/album/1',
        'explicit': true,
        'album_type': 'compilation',
        'upc': '0012345678901',
      });

      expect(track.genre, 'Pop');
      expect(track.label, 'Label');
      expect(track.copyright, 'Copyright');
      expect(track.composer, 'Composer');
      expect(track.comment, 'https://example.test/album/1');
      expect(track.toJson()['comment'], 'https://example.test/album/1');
      expect(track.explicit, isTrue);
      expect(track.albumType, 'compilation');
      expect(track.upc, '0012345678901');
      expect(track.toJson()['upc'], '0012345678901');
    });

    test('does not treat a playlist container name as a track album', () {
      final playlistTrack = Track.fromBackendMap({
        'id': 'playlist-track-1',
        'name': 'Song',
        'artists': 'Artist',
        'album_name': ' Road Trip ',
        'duration_ms': 180000,
      }, playlistName: 'road trip');
      final releaseTrack = Track.fromBackendMap({
        'id': 'playlist-track-2',
        'name': 'Song',
        'artists': 'Artist',
        'album_name': 'Real Album',
        'duration_ms': 180000,
      }, playlistName: 'Road Trip');

      expect(playlistTrack.albumName, isEmpty);
      expect(releaseTrack.albumName, 'Real Album');
    });

    test('exposes collection, source, and quality flags', () {
      const album = Track(
        id: 'album-1',
        name: 'Album',
        artistName: 'Artist',
        albumName: 'Album',
        duration: 0,
        itemType: 'album',
        source: 'extension.example',
        audioQuality: 'FLAC 1411kbps',
      );

      expect(album.isAlbumItem, isTrue);
      expect(album.isPlaylistItem, isFalse);
      expect(album.isArtistItem, isFalse);
      expect(album.isCollection, isTrue);
    });

    test('detects singles and eps case-insensitively', () {
      const single = Track(
        id: 'track-1',
        name: 'Song',
        artistName: 'Artist',
        albumName: 'Single',
        duration: 210000,
        albumType: 'SINGLE',
      );
      const ep = Track(
        id: 'track-2',
        name: 'Song 2',
        artistName: 'Artist',
        albumName: 'EP',
        duration: 180000,
        albumType: 'ep',
      );
      const album = Track(
        id: 'track-3',
        name: 'Song 3',
        artistName: 'Artist',
        albumName: 'Album',
        duration: 240000,
        albumType: 'album',
      );

      expect(single.isSingle, isTrue);
      expect(ep.isSingle, isTrue);
      expect(album.isSingle, isFalse);
    });

    test('round-trips json with service availability', () {
      final track = Track.fromJson({
        'id': 'source-track-1',
        'name': 'Song',
        'artistName': 'Artist',
        'albumName': 'Album',
        'duration': 123456,
        'availability': {'tidal': true, 'deezer': true, 'deezerId': '31337'},
      });

      expect(track.toJson()['id'], 'source-track-1');
    });
  });

  group('AppSettings', () {
    test('provides stable defaults', () {
      const settings = AppSettings();

      expect(settings.toJson().containsKey('playerMode'), false);
      expect(settings.localLibraryEnabled, isFalse);
    });

    test('copyWith updates values and retains untouched settings', () {
      const settings = AppSettings();

      final updated = settings.copyWith(localLibraryEnabled: true);
      expect(updated.localLibraryEnabled, isTrue);
      expect(updated.glassQuality, settings.glassQuality);
      expect(settings.localLibraryEnabled, isFalse);
    });

    test('round-trips json including local library settings', () {
      const settings = AppSettings(
        localLibraryEnabled: true,
        localLibraryPath: '/music',
        hasCompletedTutorial: true,
      );

      final decoded = AppSettings.fromJson(settings.toJson());

      expect(decoded.localLibraryEnabled, isTrue);
      expect(decoded.localLibraryPath, '/music');
      expect(decoded.hasCompletedTutorial, isTrue);
    });
  });

  test(
    'retired Library options are ignored by settings imports and exports',
    () {
      final settings = AppSettings.fromJson({
        'defaultLibraryView': 'albums',
        'libraryQualityLabelMode': 'bit_depth',
        'localLibraryEnabled': true,
        'localLibraryPath': '/music',
        'historyFilterMode': 'singles',
      });
      expect(settings.localLibraryEnabled, isTrue);
      expect(settings.localLibraryPath, '/music');
      expect(settings.historyFilterMode, 'singles');
      expect(settings.toJson(), isNot(contains('defaultLibraryView')));
      expect(settings.toJson(), isNot(contains('libraryQualityLabelMode')));
    },
  );

  test('legacy history layout imports ignore the retired preference', () {
    final settings = AppSettings.fromJson({'historyViewMode': 'list'});
    expect(settings.toJson().containsKey('historyViewMode'), isFalse);
  });

  group('ThemeSettings', () {
    test('serializes, deserializes, copies, and compares values', () {
      const settings = ThemeSettings(
        themeMode: ThemeMode.dark,
        mornyeAccent: MornyeAccent.blue,
        useSystemFont: true,
      );

      final decoded = ThemeSettings.fromJson(settings.toJson());
      final copied = decoded.copyWith(themeMode: ThemeMode.light);

      expect(decoded, settings);
      expect(decoded.hashCode, settings.hashCode);
      expect(copied.themeMode, ThemeMode.light);
      expect(decoded.mornyeAccent, MornyeAccent.blue);
      expect(copied.mornyeAccent, MornyeAccent.blue);
      expect(decoded.useSystemFont, isTrue);
      expect(copied.useSystemFont, isTrue);
      expect(ThemeSettings.fromJson({}).useSystemFont, isFalse);
      expect(ThemeSettings.fromJson({}).mornyeAccent, MornyeAccent.red);
      expect(
        ThemeSettings.fromJson({kMornyeAccentKey: 'unknown'}).mornyeAccent,
        MornyeAccent.red,
      );
      expect(
        ThemeSettings.fromJson({'theme_mode': 'invalid'}).themeMode,
        ThemeMode.system,
      );
      expect(
        ThemeSettings.fromJson({'theme_style': 'invalid'}).themeMode,
        ThemeMode.system,
      );
    });
  });

  group('artist utils', () {
    test('splits common artist separators and removes duplicates for tags', () {
      expect(splitArtistNames(' A, B & C feat. D x E with F '), [
        'A',
        'B',
        'C',
        'D',
        'E',
        'F',
      ]);
      expect(splitArtistTagValues('A, a & B'), ['A', 'B']);
      expect(splitArtistTagValues('   '), isEmpty);
      expect(shouldSplitVorbisArtistTags(artistTagModeSplitVorbis), isTrue);
      expect(shouldSplitVorbisArtistTags(artistTagModeJoined), isFalse);
    });

    // Shared with the Rust and Kotlin primary-artist tests; keep in sync.
    test('primary artist mode keeps the first credited artist', () {
      for (final (input, expected) in [
        ('Calle 24, Chino Pacas', 'Calle 24'),
        ('Calle 24 & Chino Pacas', 'Calle 24'),
        ('Artist A; Artist B', 'Artist A'),
        ('Artist A feat. Artist B', 'Artist A'),
        ('Artist A Feat Artist B', 'Artist A'),
        ('Artist A ft. Artist B', 'Artist A'),
        ('Artist A featuring Artist B', 'Artist A'),
        ('Artist A with Artist B', 'Artist A'),
        ('Artist A x Artist B', 'Artist A'),
        ('Artist A X Artist B', 'Artist A'),
        (' , Artist A, Artist B', 'Artist A'),
        ('Malcolm X', 'Malcolm X'),
        ('Artist Without Fear', 'Artist Without Fear'),
        ('Maxx', 'Maxx'),
        ('AC/DC', 'AC/DC'),
        ('  Various Artists  ', 'Various Artists'),
        ('', ''),
      ]) {
        expect(primaryArtistTagValue(input), expected, reason: input);
        expect(
          artistTagValueForMode(input, ' Primary '),
          expected,
          reason: input,
        );
      }
      for (final mode in [artistTagModeJoined, artistTagModeSplitVorbis]) {
        expect(artistTagValueForMode('A, B', mode), 'A, B');
      }
      expect(artistTagModes, contains(artistTagModePrimary));
      expect(
        artistTagModeForExistingTags(artistTagModePrimary),
        artistTagModeJoined,
      );
      expect(
        artistTagModeForExistingTags(artistTagModeSplitVorbis),
        artistTagModeSplitVorbis,
      );
    });

    test('primary artist mode rewrites every artist key spelling', () {
      final metadata = {
        'ARTIST': 'A, B',
        'album_artist': 'A & B',
        'ALBUM ARTIST': 'A feat. B',
        'albumArtist': 'A x B',
        'TITLE': 'A, B',
        'COMPOSER': 'A, B',
        'artist': '',
      };
      expect(applyArtistTagModeToMetadata(metadata, artistTagModePrimary), {
        'ARTIST': 'A',
        'album_artist': 'A',
        'ALBUM ARTIST': 'A',
        'albumArtist': 'A',
        'TITLE': 'A, B',
        'COMPOSER': 'A, B',
        'artist': '',
      });
      expect(
        identical(
          applyArtistTagModeToMetadata(metadata, artistTagModeJoined),
          metadata,
        ),
        isTrue,
      );
    });
  });

  group('audio format utils', () {
    test('normalizes lightweight library scan metadata for display probes', () {
      final normalized = normalizeScannedAudioMetadata({
        'trackName': 'Song',
        'artistName': 'Artist',
        'albumName': 'Album',
        'albumArtist': 'Album Artist',
        'releaseDate': '2026',
        'trackNumber': 2,
        'totalTracks': 10,
        'discNumber': 1,
        'totalDiscs': 2,
        'bitDepth': 24,
        'sampleRate': 96000,
        'bitrate': 1840,
        'albumType': 'album',
        'explicit': true,
        'upc': '4006381333931',
        'comment': 'https://media.example/album/1',
        'format': 'flac',
      });

      expect(normalized['title'], 'Song');
      expect(normalized['artist'], 'Artist');
      expect(normalized['album'], 'Album');
      expect(normalized['album_artist'], 'Album Artist');
      expect(normalized['date'], '2026');
      expect(normalized['track_number'], 2);
      expect(normalized['total_tracks'], 10);
      expect(normalized['disc_number'], 1);
      expect(normalized['total_discs'], 2);
      expect(normalized['bit_depth'], 24);
      expect(normalized['sample_rate'], 96000);
      expect(normalized['bitrate'], 1840);
      expect(normalized['album_type'], 'album');
      expect(normalized['explicit'], isTrue);
      expect(normalized['upc'], '4006381333931');
      expect(normalized['comment'], 'https://media.example/album/1');
      expect(normalized['audio_codec'], 'flac');
    });

    test('does not replace stored tags with filename scan fallbacks', () {
      final normalized = normalizeScannedAudioMetadata({
        'trackName': 'Filename fallback',
        'artistName': 'Unknown Artist',
        'albumName': 'Unknown Album',
        'metadataFromFilename': true,
        'format': 'flac',
      });

      expect(normalized['title'], isNull);
      expect(normalized['artist'], isNull);
      expect(normalized['album'], isNull);
      expect(normalized['audio_codec'], 'flac');
    });
  });

  group('string utils', () {
    test('normalizes optional strings and cover references', () {
      expect(normalizeOptionalString(null), isNull);
      expect(normalizeOptionalString(' null '), isNull);
      expect(normalizeOptionalString(' value '), 'value');
      expect(
        normalizeCoverReference('//cdn.example.test/a.jpg'),
        'https://cdn.example.test/a.jpg',
      );
      expect(
        normalizeCoverReference('https://example.test/a.jpg'),
        'https://example.test/a.jpg',
      );
      expect(
        normalizeCoverReference('/storage/music/a.jpg'),
        '/storage/music/a.jpg',
      );
      expect(normalizeCoverReference('relative/a.jpg'), isNull);
      expect(normalizeRemoteHttpUrl('file:///tmp/a.jpg'), isNull);
      expect(
        normalizeRemoteHttpUrl('http://example.test/a.jpg'),
        'http://example.test/a.jpg',
      );
    });

    test('formats display audio quality from strongest available source', () {
      expect(
        buildDisplayAudioQuality(
          bitrateKbps: 320,
          format: 'mp3',
          bitDepth: 24,
          sampleRate: 96000,
          storedQuality: 'LOSSLESS',
        ),
        'MP3 320kbps',
      );
      expect(
        buildDisplayAudioQuality(bitDepth: 24, sampleRate: 96000),
        '24-bit/96kHz',
      );
      expect(formatSampleRateKHz(44100), '44.1kHz');
      expect(buildDisplayAudioQuality(storedQuality: ' Hi-Res '), 'Hi-Res');
      expect(isPlaceholderQualityLabel('lossless'), isTrue);
      expect(isPlaceholderQualityLabel('FLAC 1411kbps'), isFalse);
    });
  });

  group('mime utils', () {
    test('maps known audio extensions and falls back to wildcard', () {
      expect(audioMimeTypeForPath('/music/song.FLAC'), 'audio/flac');
      expect(audioMimeTypeForPath('/music/song.m4a'), 'audio/mp4');
      expect(audioMimeTypeForPath('/music/song.mp3'), 'audio/mpeg');
      expect(audioMimeTypeForPath('/music/song.ogg'), 'audio/ogg');
      expect(audioMimeTypeForPath('/music/song.wav'), 'audio/wav');
      expect(audioMimeTypeForPath('/music/song.aac'), 'audio/aac');
      expect(audioMimeTypeForPath('/music/song'), 'audio/*');
      expect(audioMimeTypeForPath('/music/song.'), 'audio/*');
      expect(audioMimeTypeForPath('/music/song.txt'), 'audio/*');
    });
  });

  group('path match keys', () {
    test('builds normalized variants for local paths and file uris', () {
      final keys = buildPathMatchKeys('EXISTS: /Music/A%20Song.FLAC ');

      expect(keys, contains('/Music/A%20Song.FLAC'));
      expect(keys, contains('/Music/A Song.FLAC'));
      expect(keys, contains('file:///Music/A%2520Song.FLAC'));
      // POSIX paths are case-sensitive: lowercasing would collide A.flac/a.flac.
      expect(keys, isNot(contains('/music/a%20song.flac')));
      expect(keys, isNot(contains('/music/a song.flac')));
      expect(keys, contains('/Music/A%20Song'));
      expect(
        identical(buildPathMatchKeys('/Music/A%20Song.FLAC'), keys),
        isTrue,
      );
      expect(buildPathMatchKeys('   '), isEmpty);
    });

    test('normalizes windows-style separators', () {
      final keys = buildPathMatchKeys(r'C:\Music\Song.mp3');

      expect(keys, contains(r'C:\Music\Song.mp3'));
      expect(keys, contains('C:/Music/Song.mp3'));
      expect(keys, contains('c:/music/song.mp3'));
      expect(keys, contains('C:/Music/Song'));
    });

    test('only windows drive paths fold case', () {
      expect(
        physicalFilePathsMatch(r'C:\Music\A.flac', r'c:\music\a.flac'),
        isTrue,
      );
      expect(physicalFilePathsMatch('/Music/A.flac', '/Music/a.flac'), isFalse);
      expect(
        physicalFilePathsMatch(
          'content://p/tree/T/document/T%2FA.flac',
          'content://p/tree/T/document/T%2Fa.flac',
        ),
        isFalse,
      );
    });

    test('virtual SAF CUE tracks keep their #trackNN identity', () {
      const cue =
          'content://com.android.externalstorage.documents/'
          'tree/primary%3AMusic/document/primary%3AMusic%2FAlbum.cue';

      expect(physicalFilePathsMatch('$cue#track1', '$cue#track2'), isFalse);
      expect(physicalFilePathsMatch('$cue#track1', '$cue#track1'), isTrue);
      // A fragmented SAF URI is a virtual track, not the backing document.
      final trackKeys = buildPhysicalPathMatchKeys('$cue#track1');
      expect(trackKeys.any((key) => key.endsWith('Album.cue#track1')), isTrue);
      expect(trackKeys, isNot(contains('/storage/emulated/0/Music/Album.cue')));
      // The same document without a fragment still maps to its raw path.
      expect(
        buildPhysicalPathMatchKeys(cue),
        contains('/storage/emulated/0/Music/Album.cue'),
      );
    });

    test('matches a primary-storage SAF URI to its raw Android path', () {
      const safUri =
          'content://com.android.externalstorage.documents/'
          'tree/primary%3AMusic%2FFlac%20Songs/'
          'document/primary%3AMusic%2FFlac%20Songs%2FAdore%20You.m4a';
      const rawPath = '/storage/emulated/0/Music/Flac Songs/Adore You.m4a';

      expect(physicalFilePathsMatch(safUri, rawPath), isTrue);
      expect(buildPhysicalPathMatchKeys(safUri), contains(rawPath));
    });

    test('physical matching keeps coexisting audio formats distinct', () {
      const flac = '/storage/emulated/0/Music/Song.flac';
      const opus = '/storage/emulated/0/Music/Song.opus';

      expect(
        buildPathMatchKeys(flac),
        contains('/storage/emulated/0/Music/Song'),
      );
      expect(physicalFilePathsMatch(flac, opus), isFalse);
      expect(isPhysicalFileRetained(opus, [flac]), isFalse);
    });

    test('retains a shared SAF file during duplicate cleanup', () {
      const safUri =
          'content://com.android.externalstorage.documents/'
          'document/primary%3AMusic%2FSong.flac';

      expect(
        isPhysicalFileRetained('/storage/emulated/0/Music/Song.flac', [safUri]),
        isTrue,
      );
    });
  });
}
