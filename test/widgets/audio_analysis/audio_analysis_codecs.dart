part of 'audio_analysis_spectrogram_test.dart';

void _registerAudioAnalysisCodecs() {
  group('audio analysis codec support', () {
    test('rejects AC-4 aliases unsupported by the bundled decoder', () {
      expect(isAudioAnalysisCodecSupported('ac4'), isFalse);
      expect(isAudioAnalysisCodecSupported('AC-4'), isFalse);
      expect(isAudioAnalysisCodecSupported('Dolby Atmos (AC_4)'), isFalse);
      expect(unsupportedAudioAnalysisCodecLabel('AC-4'), 'AC-4');
    });

    test('keeps supported codecs inside MP4 analyzable', () {
      expect(isAudioAnalysisCodecSupported('aac'), isTrue);
      expect(isAudioAnalysisCodecSupported('alac'), isTrue);
      expect(isAudioAnalysisCodecSupported('eac3'), isTrue);
      expect(isAudioAnalysisCodecSupported('E-AC-3'), isTrue);
      expect(isAudioAnalysisCodecSupported('flac'), isTrue);
      expect(isAudioAnalysisCodecSupported(null), isTrue);
    });
  });

  group('audio analysis cache', () {
    test('invalidates results from the previous cutoff estimator', () {
      expect(AudioAnalysisData.cacheVersion, 14);
    });

    test(
      'a truncated cached spectrogram decodes to null instead of hanging',
      () async {
        // 1x1 transparent PNG. Half of it is a valid header with a partial
        // IDAT, which is what an interrupted cache write leaves behind.
        final png = base64Decode(
          'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8'
          'BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
        );
        final decoded = await decodeCachedSpectrogramBytes(png);
        expect(decoded, isNotNull);
        decoded!.dispose();

        final truncated = Uint8List.sublistView(png, 0, png.length ~/ 2);
        final result = await decodeCachedSpectrogramBytes(
          truncated,
        ).timeout(const Duration(seconds: 5));
        expect(result, isNull);
      },
    );

    test('round-trips the source modification time used for invalidation', () {
      final data = AudioAnalysisData(
        filePath: '/music/song.flac',
        fileSize: 1024,
        fileModified: 1770000000123,
        sampleRate: 44100,
        channels: 2,
        bitsPerSample: 16,
        duration: 1.5,
        bitrate: 900000,
        bitDepth: '16-bit',
        dynamicRange: 12.5,
        peakAmplitude: 0.98,
        rmsLevel: 0.2,
        totalSamples: 66150,
      );

      final restored = AudioAnalysisData.fromJson(data.toJson());

      expect(restored.fileModified, 1770000000123);
      expect(restored.fileSize, 1024);
    });
  });

  group('audio level analysis', () {
    test('reads peak and RMS from the final astats overall summary', () {
      const logs = '''
[Parsed_astats_0] Channel: 1
[Parsed_astats_0] Peak level dB: -0.847144
[Parsed_astats_0] RMS level dB: -12.935500
[Parsed_astats_0] Channel: 2
[Parsed_astats_0] Peak level dB: -0.861847
[Parsed_astats_0] RMS level dB: -12.752564
[Parsed_astats_0] Overall
[Parsed_astats_0] Peak level dB: -0.847144
[Parsed_astats_0] RMS level dB: -12.843069
''';

      final summary = parseAudioAstatsSummary(logs);

      expect(summary, isNotNull);
      expect(summary!.peakDb, closeTo(-0.847144, 0.000001));
      expect(summary.rmsDb, closeTo(-12.843069, 0.000001));
    });

    test('rejects logs delivered without the final RMS metric', () {
      const incompleteLogs = '''
[Parsed_astats_0] Overall
[Parsed_astats_0] Peak level dB: -0.847144
''';

      expect(parseAudioAstatsSummary(incompleteLogs), isNull);
    });

    test('reads per-session metadata without depending on FFmpeg logs', () {
      const metadata = '''
lavfi.astats.1.Peak_level=-0.847144
lavfi.astats.1.RMS_level=-12.935500
lavfi.astats.1.Peak_count=2.000000
lavfi.astats.2.Peak_level=-0.861847
lavfi.astats.2.RMS_level=-12.752564
lavfi.astats.2.Peak_count=2.000000
lavfi.astats.Overall.Peak_level=-0.847144
lavfi.astats.Overall.RMS_level=-12.843069
lavfi.r128.I=-9.708
lavfi.r128.true_peak=0.907
''';

      final summary = parseAudioAnalysisMetadata(metadata);

      expect(summary, isNotNull);
      expect(summary!.peakDb, closeTo(-0.847144, 0.000001));
      expect(summary.rmsDb, closeTo(-12.843069, 0.000001));
      expect(summary.integratedLufs, closeTo(-9.708, 0.000001));
      expect(summary.truePeakDb, closeTo(-0.8476, 0.001));
      expect(summary.channelStats, hasLength(2));
      expect(summary.channelStats.first.channel, 1);
      expect(summary.channelStats.first.peakCount, 2);
    });

    test('keeps the analyzer independent from process-global log level', () {
      final arguments = buildAudioMetricsArguments(
        inputPath: 'source.flac',
        metadataPath: '/tmp/metrics.txt',
        durationSeconds: 203.94,
      );

      expect(arguments, isNot(contains('-v')));
      expect(arguments, isNot(contains('-loglevel')));
      expect(arguments.join(' '), contains('ametadata=print'));
      expect(arguments.join(' '), contains("aselect='gte(t,201.940)'"));
    });

    test('rejects incomplete per-session metadata instead of using zero', () {
      const metadata = 'lavfi.astats.Overall.Peak_level=-0.8';

      expect(parseAudioAnalysisMetadata(metadata), isNull);
    });
  });

  group('audio spectrogram filter', () {
    test('keeps source rate and uses a full-range float pipeline', () {
      final filter = buildAudioSpectrogramFilter();

      expect(filter, contains('[0:a:0]aformat=sample_fmts=fltp'));
      expect(filter, contains('s=1600x800'));
      expect(filter, contains('scale=log'));
      expect(filter, contains('fscale=lin'));
      expect(filter, contains('win_func=hann'));
      expect(filter, contains('drange=120'));
      expect(filter, contains('limit=0'));
      expect(filter, isNot(contains('pan=')));
      expect(filter, isNot(contains('aresample')));
    });

    test('can render one source channel without app-specific branching', () {
      final filter = buildAudioSpectrogramFilter(channel: 1);

      expect(filter, contains('[0:a:0]pan=mono|c0=c1,'));
      expect(filter, contains('aformat=sample_fmts=fltp'));
    });

    test('processes the complete source without resampling or downmixing', () {
      final arguments = buildAudioSpectrogramArguments(
        inputPath: 'source.flac',
        outputPath: 'spectrum.rgba',
      );

      expect(arguments, containsAllInOrder(['-i', 'source.flac']));
      expect(arguments, containsAllInOrder(['-frames:v', '1']));
      expect(arguments, containsAllInOrder(['-pix_fmt', 'rgba']));
      expect(arguments, isNot(contains('-t')));
      expect(arguments, isNot(contains('-ss')));
      expect(arguments, isNot(contains('-ar')));
      expect(arguments, isNot(contains('-ac')));
      expect(arguments, isNot(contains('-loglevel')));
    });

    test('bounds retained audio without making splice noise persistent', () {
      final filter = buildAudioSpectrogramFilter(
        durationSeconds: 600,
        sampleRate: 192000,
        channels: 2,
      );

      // The cutoff estimator uses temporal P90. Keep window boundaries far
      // below ten percent of its 400 columns so seam energy remains an outlier.
      expect(audioSpectrogramSampleWindowCount, 16);
      expect(
        audioSpectrogramSampleWindowCount,
        lessThan(audioSpectralAnalysisWidth * 0.10),
      );
      expect(filter, contains("aselect='lt(mod(t,37.500000000),"));
      expect(filter, contains('1.365333333'));
      expect(filter, contains('asetpts=N/SR/TB'));
      expect(filter, contains('aformat=sample_fmts=fltp'));
      expect(filter, isNot(contains('aresample')));
    });

    test('keeps short files continuous', () {
      final filter = buildAudioSpectrogramFilter(
        durationSeconds: 60,
        sampleRate: 44100,
        channels: 2,
      );

      expect(filter, isNot(contains('aselect=')));
      expect(filter, isNot(contains('asetpts=')));
    });

    test('accounts for a selected mono channel in the memory bound', () {
      final combined = buildAudioSpectrogramFilter(
        durationSeconds: 60,
        sampleRate: 192000,
        channels: 8,
      );
      final mono = buildAudioSpectrogramFilter(
        channel: 3,
        durationSeconds: 60,
        sampleRate: 192000,
        channels: 8,
      );

      expect(combined, contains('aselect='));
      expect(mono, contains('pan=mono|c0=c3'));
      expect(mono, contains('aselect='));
      expect(combined, isNot(equals(mono)));
    });

    test('renders a monotonic cutoff plane beside the display image', () {
      final arguments = buildAudioSpectrogramArguments(
        inputPath: 'source.flac',
        outputPath: 'spectrum.rgba',
        cutoffOutputPath: 'cutoff.gray',
      );
      final filter = arguments[arguments.indexOf('-filter_complex') + 1];

      expect(filter, contains('asplit=2'));
      expect(filter, contains('color=intensity'));
      expect(filter, contains('s=400x800'));
      expect(filter, contains('color=green'));
      expect(filter, contains('format=gray[cutoff]'));
      expect(
        arguments,
        containsAllInOrder(['-map', '[cutoff]', '-frames:v', '1']),
      );
      expect(
        arguments,
        containsAllInOrder(['-pix_fmt', 'gray', 'cutoff.gray']),
      );
    });
  });
}
