import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/models/local_library_item.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/models/theme_settings.dart';
import 'package:sistrum/models/track.dart';
import 'package:sistrum/providers/library_collections_provider.dart';
import 'package:sistrum/services/library/library_database.dart';
import 'package:sistrum/navigation/detail_navigation.dart';
import 'package:sistrum/utils/audio_format_utils.dart';
import 'package:sistrum/utils/file_access.dart';
import 'package:sistrum/widgets/library/local_song_file_actions.dart';
import 'package:sistrum/utils/path_match_keys.dart';
import 'package:sistrum/utils/string_utils.dart';

void main() {
  group('Finalized SAF audio names', () {});

  group('file deletion', () {
    test('confirms a local file is absent before reporting success', () async {
      final tempDir = await Directory.systemTemp.createTemp(
        'sistrum-delete-test-',
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
        'sistrum-cue-suffix-',
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
      'lib/services/storage/app_state_database.dart',
    ).readAsStringSync();

    test('v6 drops the retired download queue and recent-access tables', () {
      expect(source, contains('const _dbVersion = 6;'));
      expect(source, contains('DROP TABLE IF EXISTS'));
      for (final table in [
        'download_queue_items',
        'recent_access_items',
        'hidden_recent_downloads',
        'recent_access_state',
      ]) {
        expect(source, contains("'$table'"));
      }
      expect(source, contains('media_json TEXT NOT NULL'));
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
    test('round-trips json', () {
      final track = Track.fromJson({
        'id': 'source-track-1',
        'name': 'Song',
        'artistName': 'Artist',
        'albumName': 'Album',
        'duration': 123456,
      });

      expect(track.toJson()['id'], 'source-track-1');
    });
  });

  group('AppSettings', () {
    test('provides stable defaults', () {
      const settings = AppSettings();

      expect(settings.toJson().containsKey('playerMode'), false);
    });

    test('copyWith updates values and retains untouched settings', () {
      const settings = AppSettings();

      final updated = settings.copyWith(localLibraryAutoScan: 'daily');
      expect(updated.localLibraryAutoScan, 'daily');
      expect(updated.glassQuality, settings.glassQuality);
    });

    test('round-trips json including local library settings', () {
      const settings = AppSettings(
        localLibraryAutoScan: 'daily',
        hasCompletedTutorial: true,
      );

      final decoded = AppSettings.fromJson(settings.toJson());

      expect(decoded.localLibraryAutoScan, 'daily');
      expect(decoded.hasCompletedTutorial, isTrue);
    });
  });

  test(
    'retired Library options are ignored by settings imports and exports',
    () {
      final settings = AppSettings.fromJson({
        'defaultLibraryView': 'albums',
        'libraryQualityLabelMode': 'bit_depth',
        'libraryFilterMode': 'singles',
      });
      expect(settings.libraryFilterMode, 'singles');
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
        appAccent: AppAccent.blue,
        useSystemFont: true,
      );

      final decoded = ThemeSettings.fromJson(settings.toJson());
      final copied = decoded.copyWith(themeMode: ThemeMode.light);

      expect(decoded, settings);
      expect(decoded.hashCode, settings.hashCode);
      expect(copied.themeMode, ThemeMode.light);
      expect(decoded.appAccent, AppAccent.blue);
      expect(copied.appAccent, AppAccent.blue);
      expect(decoded.useSystemFont, isTrue);
      expect(copied.useSystemFont, isTrue);
      expect(ThemeSettings.fromJson({}).useSystemFont, isFalse);
      expect(ThemeSettings.fromJson({}).appAccent, AppAccent.red);
      expect(
        ThemeSettings.fromJson({kAppAccentKey: 'unknown'}).appAccent,
        AppAccent.red,
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
      final keys = buildPathMatchKeys(' /Music/A%20Song.FLAC ');

      expect(keys, contains('/Music/A%20Song.FLAC'));
      expect(keys, contains('/Music/A Song.FLAC'));
      expect(keys, contains('file:///Music/A%2520Song.FLAC'));
      // POSIX paths are case-sensitive: lowercasing would collide A.flac/a.flac.
      expect(keys, isNot(contains('/music/a%20song.flac')));
      expect(keys, isNot(contains('/music/a song.flac')));
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
      final trackKeys = buildPathMatchKeys('$cue#track1');
      expect(trackKeys.any((key) => key.endsWith('Album.cue#track1')), isTrue);
      expect(trackKeys, isNot(contains('/storage/emulated/0/Music/Album.cue')));
      // The same document without a fragment still maps to its raw path.
      expect(
        buildPathMatchKeys(cue),
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
      expect(buildPathMatchKeys(safUri), contains(rawPath));
    });

    test('physical matching keeps coexisting audio formats distinct', () {
      const flac = '/storage/emulated/0/Music/Song.flac';
      const opus = '/storage/emulated/0/Music/Song.opus';

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
