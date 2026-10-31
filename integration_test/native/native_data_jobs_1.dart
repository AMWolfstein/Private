part of 'native_data_jobs_test.dart';

late Directory root;

void _registerNativeDataJobs1() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = null;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('native-data-jobs-');
  });
  tearDown(() async {
    await LibraryScanBridge.setLibraryCoverCacheDir('');
    await root.delete(recursive: true);
  });

  testWidgets(
    'palette ordered quantization matches pinned Material before init',
    (tester) async {
      for (final kind in ['opaque', 'mixed_alpha', 'same_bin']) {
        final random = math.Random(7);
        final rgba = Uint8List(112 * 112 * 4);
        for (var i = 0; i < rgba.length; i += 4) {
          for (var channel = 0; channel < 3; channel++) {
            rgba[i + channel] = kind == 'same_bin'
                ? 96 + random.nextInt(8)
                : random.nextInt(256);
          }
          rgba[i + 3] = kind == 'mixed_alpha'
              ? [0, 64, 255][random.nextInt(3)]
              : 255;
        }
        final old = await QuantizerCelebi().quantize(
          rgba.buffer.asUint32List(),
          128,
        );
        final expected = [
          for (final entry in old.colorToCount.entries)
            [entry.key, entry.value],
        ];
        final result = await _job('palette', {}, bytes: rgba);
        final colors = [
          for (final pair in result['colors'] as List)
            List<int>.from(pair as List),
        ];
        expect(colors, expected, reason: kind);
        expect(
          paletteSeedFromColorCounts(colors),
          paletteSeedFromColorCounts(expected),
        );
      }
    },
  );

  testWidgets(
    'AutoMix f64 detector and spectrum classifier preserve production results',
    (tester) async {
      final patterns = <String, Uint8List>{
        for (final bpm in [90.0, 120.0, 124.0, 160.0]) '$bpm': _drums(bpm),
        'silence': Uint8List(11025 * 24 * 2),
        'short': Uint8List(11025 * 5 * 2),
        'empty': Uint8List(0),
        'odd_tail': Uint8List.fromList([..._drums(120), 255]),
      };
      for (final entry in patterns.entries) {
        final file = await File(
          '${root.path}/${entry.key}.pcm',
        ).writeAsBytes(entry.value);
        final expected = analyzeAutoMixPcm(entry.value);
        final native = await _job('automix', {'path': file.path});
        expect(native['bpm'], expected.bpm, reason: entry.key);
        expect(native['phase'], closeTo(expected.phase, 1e-12));
        expect(native['confidence'], closeTo(expected.confidence, 1e-12));
        expect(native['first_sound'], closeTo(expected.firstSound, 1e-12));
      }
      const width = 400;
      const height = 800;
      const maximum = 96000.0;
      for (final kind in [
        'step',
        'noise_floor',
        'pilot',
        'tilt',
        'rolloff',
        'silence',
      ]) {
        for (final cutoff in [18000.0, 30000.0, maximum]) {
          final plane = Uint8List(width * height);
          for (var y = 0; y < height; y++) {
            final frequency = (height - y - 1) * maximum / height;
            for (var x = 0; x < width; x++) {
              final noise = (x * 13 + y * 7) % 16;
              var value = frequency <= cutoff ? 150 : 5;
              if (kind == 'noise_floor') {
                value = frequency <= cutoff ? 130 + noise : 70 + noise;
              }
              if (kind == 'pilot' && (frequency - 70000).abs() < 120) {
                value = 250;
              }
              if (kind == 'tilt') {
                value = (170 - frequency / maximum * 120).round();
              }
              if (kind == 'rolloff') {
                value =
                    (150 -
                            (frequency - cutoff + 6000).clamp(0, 12000) /
                                12000 *
                                145)
                        .round();
              }
              if (kind == 'silence') value = 0;
              plane[y * width + x] = value;
            }
          }
          final file = await File(
            '${root.path}/spectrum.gray',
          ).writeAsBytes(plane);
          final expected = estimateEffectiveSpectralCutoffHz(
            intensity: plane,
            width: width,
            height: height,
            maxFrequencyHz: maximum,
          );
          final result = await _job('spectral_cutoff', {
            'path': file.path,
            'width': width,
            'height': height,
            'max_frequency': maximum,
          });
          expect(result['cutoff'], expected, reason: '$kind/$cutoff');
        }
      }
    },
  );

  testWidgets('all lyric DTO fields match the existing production parser', (
    tester,
  ) async {
    expect(_lyricCases, hasLength(27));
    for (final (name, raw) in _lyricCases) {
      final expected = _lyricsDto(LyricsParser.parse(raw));
      final native = await _job(
        'parse_lyrics',
        {},
        bytes: Uint8List.fromList(utf8.encode(raw)),
      );
      expect(native, expected, reason: name);
      expect(
        _lyricsDto(await LyricsParser.parseAsyncNative(raw)),
        expected,
        reason: '$name public caller',
      );
    }
  });

  testWidgets(
    'streamed file hashing, playlist/listing parsers and M3U output use real bindings',
    (tester) async {
      final file = File('${root.path}/large.bin');
      final sink = file.openWrite();
      final chunk = List<int>.generate(64 * 1024, (i) => i % 251);
      for (var i = 0; i < 128; i++) {
        sink.add(chunk);
      }
      await sink.close();
      final expected = (await sha256.bind(file.openRead()).first).toString();
      expect(
        (await _job('hash_file', {'path': file.path}))['sha256'],
        expected,
      );
      final csv = await _job(
        'parse_playlist',
        {'format': 'csv', 'id_seed': 42},
        bytes: Uint8List.fromList(
          utf8.encode(
            'Track Name,Artist Name(s),Album Name,Track URI,ISRC\r\n"Song, ""One""",Artist,Album,spotify:track:abc,AAABC1200001\r\n',
          ),
        ),
      );
      expect(csv['tracks'], [
        {
          'id': 'abc',
          'name': 'Song, "One"',
          'artistName': 'Artist',
          'albumName': 'Album',
          'duration': 0,
          'coverUrl': null,
          'isrc': 'AAABC1200001',
        },
      ]);
      final m3u = await _job(
        'parse_playlist',
        {'format': 'm3u', 'id_seed': 42},
        bytes: Uint8List.fromList(
          utf8.encode(
            '#EXTM3U\r#EXTINF:180.5,Artist - Song - Mix\rfolder/a.flac\nMusic/02 Demo.flac',
          ),
        ),
      );
      expect((m3u['tracks'] as List).map((row) => (row as Map)['name']), [
        'Song - Mix',
        '02 Demo',
      ]);
      expect(((m3u['tracks'] as List).first as Map)['duration'], 181);
      final output = '${root.path}/export.m3u8';
      await _job('build_m3u', {
        'output_path': output,
        'entries': [
          {
            'name': 'Song',
            'artist': ' Artist ',
            'duration': 180,
            'path': 'folder/a.flac',
          },
          {
            'name': 'Unknown length',
            'artist': '',
            'duration': 0,
            'path': 'b.flac',
          },
        ],
      });
      expect(
        await File(output).readAsString(),
        '#EXTM3U\n#EXTINF:180,Artist - Song\nfolder/a.flac\n#EXTINF:-1,Unknown length\nb.flac\n',
      );
    },
  );

  testWidgets(
    'native SQLite import/snapshot and filesystem delta share the app schema',
    (tester) async {
      final media = await Directory('${root.path}/media').create();
      final first = await File(
        '${media.path}/first.flac',
      ).writeAsBytes(_flac());
      final downloadedPath = '${media.path}/downloaded.flac';
      final db = await openDatabase(
        '${root.path}/local_library.db',
        version: LibrarySchema.version,
        onCreate: (db, version) async {
          await LibrarySchema.create(db, version);
        },
      );
      addTearDown(db.close);
      await db.insert('library_sources', {
        'id': 'test-source',
        'path': media.path,
        'display_name': 'Fixture',
        'enabled': 1,
        'available': 1,
      });
      final common = {
        'library_path': db.path,
        'source_id': 'test-source',
        'expected_source_path': media.path,
        'platform': Platform.isAndroid ? 'android' : 'ios',
      };
      final firstRow = <String, dynamic>{
        'id': 'first',
        'trackName': ' CAFÉ İ 💫 ',
        'artistName': 'Artist',
        'albumName': 'Album',
        'filePath': first.path,
        'fileModTime': (await first.stat()).modified.millisecondsSinceEpoch,
        'scannedAt': '2026-10-06T12:00:00.000Z',
        'hasLyrics': true,
        'explicit': 1,
      };
      final ndjson = await File('${root.path}/scan.ndjson').writeAsString(
        [
          firstRow,
          {...firstRow, 'id': 'downloaded', 'filePath': downloadedPath},
        ].map(jsonEncode).join('\n'),
      );
      final full = await _job('library_full_import', {
        ...common,
        'ndjson_path': ndjson.path,
        'expected_count': 2,
        'error_count': 0,
      });
      expect(full['inserted'], 2);
      expect(
        (await db.query('library', where: 'id=?', whereArgs: ['first'])).single,
        LibraryRowMapper.encode(firstRow, sourceId: 'test-source'),
      );
      final changed = {...firstRow, 'trackName': 'Updated metadata'};
      final delta = await _job('library_incremental_import', {
        ...common,
        'delta': {
          'files': [changed],
          'removedUris': <String>[],
          'skippedCount': 0,
          'totalFiles': 1,
        },
      });
      expect(delta['committed'], true);
      expect(
        (await db.query(
          'library',
          where: 'id=?',
          whereArgs: ['first'],
        )).single['track_name'],
        'Updated metadata',
      );
      final snapshot = '${root.path}/snapshot.tsv';
      expect(
        (await _job('library_snapshot', {
          ...common,
          'snapshot_path': snapshot,
        }))['count'],
        2,
      );
      expect((await File(snapshot).readAsLines()).toSet(), {
        '${firstRow['fileModTime']}\t${first.path}',
        '${firstRow['fileModTime']}\t$downloadedPath',
      });

      await first.delete();
      final second = await File(
        '${media.path}/second.flac',
      ).writeAsBytes(_flac(title: 'Second native song'));
      final scanned = await _job('library_scan_incremental', {
        ...common,
        'folder_path': media.path,
        'snapshot_path': snapshot,
      });
      expect(scanned['committed'], true);
      final rows = await db.query('library');
      expect(rows, hasLength(1));
      expect(rows.single['file_path'], second.path);
      expect(rows.single['track_name'], 'Second native song');
    },
  );
}
