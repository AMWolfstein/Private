part of 'audio_analysis_spectrogram_test.dart';

void _registerAudioAnalysisCutoffs() {
  group('effective spectral cutoff', () {
    const width = 200;
    const height = 800;
    const nyquist = 96000.0;

    test('preserves exact cutoffs across noisy and transient spectra', () {
      // Captured from the estimator before sharing sorted percentile windows.
      // Cover sharp/gradual limits, full-band slopes, noise and stepped bands
      // at several resolutions and Nyquist frequencies.
      const expected = <int, double>{
        3: 5290.322580645161,
        7: 5406.25,
        11: 5403.508771929824,
        15: 5395.0,
        31: 14952.65625,
        47: 16305.0,
        63: 32610.0,
        79: 65220.0,
        83: 5032.258064516129,
        87: 5156.25,
        91: 5162.907268170426,
        95: 5155.0,
        111: 14291.15625,
        127: 15585.0,
        143: 31230.0,
        159: 62340.0,
        175: 8000.0,
        191: 22050.0,
        207: 24000.0,
        223: 48000.0,
        239: 96000.0,
        255: 8000.0,
        271: 22050.0,
        287: 24000.0,
        303: 48000.0,
        319: 96000.0,
        335: 5795.0,
        351: 16055.15625,
        367: 17505.0,
        383: 35010.0,
        399: 70020.0,
      };
      for (final entry in expected.entries) {
        final spectrum = _noisySpectrum(entry.key);
        expect(
          estimateEffectiveSpectralCutoffHz(
            intensity: spectrum.intensity,
            width: spectrum.width,
            height: spectrum.height,
            maxFrequencyHz: spectrum.maxFrequencyHz,
          ),
          entry.value,
          reason: 'spectrum ${entry.key}',
        );
      }
    });

    test('ignores a narrow ultrasonic pilot above a 22 kHz music band', () {
      final intensity = _blankIntensity(width, height, value: 12);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
        lowHz: 0,
        highHz: 22000,
        intensity: 220,
      );
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
        lowHz: 53880,
        highHz: 54120,
        intensity: 255,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(21000, 23500));
    });

    test('ignores sparse broadband seams below the temporal P90 budget', () {
      const sourceNyquist = 24000.0;
      final intensity = _blankIntensity(width, height, value: 12);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: sourceNyquist,
        lowHz: 0,
        highHz: 20000,
        intensity: 100,
      );
      // Model discontinuities between distributed excerpts. Their columns are
      // bright at every frequency, but occupy only six percent of the image.
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: sourceNyquist,
        lowHz: 0,
        highHz: sourceNyquist,
        intensity: 255,
        startColumn: 0,
        endColumn: 12,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: sourceNyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(19400, 20600));
    });

    test('rejects a low noise floor above a 15.8 kHz bandwidth edge', () {
      const cdNyquist = 22050.0;
      final intensity = _blankIntensity(width, height, value: 42);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
        lowHz: 0,
        highHz: 15800,
        intensity: 100,
      );
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
        lowHz: 15800,
        highHz: cdNyquist,
        intensity: 85,
        startColumn: 0,
        endColumn: 10,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(15300, 16300));
    });

    test(
      'finds a 15 kHz edge below elevated noise and a persistent 18.7 kHz line',
      () {
        const cdNyquist = 22050.0;
        final intensity = _blankIntensity(width, height, value: 30);
        _paintFrequencyBand(
          intensity,
          width: width,
          height: height,
          maxFrequencyHz: cdNyquist,
          lowHz: 0,
          highHz: 15000,
          intensity: 39,
        );
        _paintFrequencyBand(
          intensity,
          width: width,
          height: height,
          maxFrequencyHz: cdNyquist,
          lowHz: 18600,
          highHz: 18800,
          intensity: 220,
        );

        final cutoff = estimateEffectiveSpectralCutoffHz(
          intensity: intensity,
          width: width,
          height: height,
          maxFrequencyHz: cdNyquist,
        );

        expect(cutoff, isNotNull);
        expect(cutoff!, inInclusiveRange(14500, 15500));
      },
    );

    test('retains a genuine broadband cutoff around 18.7 kHz', () {
      const cdNyquist = 22050.0;
      final intensity = _blankIntensity(width, height, value: 18);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
        lowHz: 0,
        highHz: 18700,
        intensity: 100,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(18200, 19200));
    });

    test('ignores a tonal drop before a gradual 22 kHz bandwidth limit', () {
      const hiresNyquist = 48000.0;
      final intensity = _blankIntensity(width, height, value: 46);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: hiresNyquist,
        lowHz: 0,
        highHz: 4000,
        intensity: 120,
      );
      _paintFrequencySlope(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: hiresNyquist,
        lowHz: 4000,
        highHz: 20000,
        lowIntensity: 115,
        highIntensity: 75,
      );
      _paintFrequencySlope(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: hiresNyquist,
        lowHz: 20000,
        highHz: 23500,
        lowIntensity: 75,
        highIntensity: 46,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: hiresNyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(20500, 22500));
    });

    test('retains genuine broadband ultrasonic content', () {
      final intensity = _blankIntensity(width, height, value: 10);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
        lowHz: 0,
        highHz: 48000,
        intensity: 180,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
      );

      expect(cutoff, isNotNull);
      expect(cutoff!, inInclusiveRange(47000, 49500));
    });

    test('reports Nyquist for full-bandwidth content', () {
      final intensity = _blankIntensity(width, height, value: 180);

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
      );

      expect(cutoff, nyquist);
    });

    test(
      'reports Nyquist for full-band music with a natural spectral tilt',
      () {
        const cdNyquist = 22050.0;
        final intensity = _blankIntensity(width, height);
        _paintNaturalSpectralTilt(
          intensity,
          width: width,
          height: height,
          lowFrequencyIntensity: 140,
          nyquistIntensity: 26,
        );

        final cutoff = estimateEffectiveSpectralCutoffHz(
          intensity: intensity,
          width: width,
          height: height,
          maxFrequencyHz: cdNyquist,
        );

        expect(cutoff, cdNyquist);
      },
    );

    test('reports Nyquist for low-contrast full-band spectral tilt', () {
      const cdNyquist = 22050.0;
      final intensity = _blankIntensity(width, height);
      _paintNaturalSpectralTilt(
        intensity,
        width: width,
        height: height,
        lowFrequencyIntensity: 39,
        nyquistIntensity: 30,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
      );

      expect(cutoff, cdNyquist);
    });

    test('reports Nyquist for an extended gentle high-frequency rolloff', () {
      const cdNyquist = 22050.0;
      final intensity = _blankIntensity(width, height);
      const segments = <(double, double, int, int)>[
        (0, 4000, 113, 104),
        (4000, 6000, 104, 96),
        (6000, 15000, 96, 91),
        (15000, 16000, 91, 87),
        (16000, 17000, 87, 84),
        (17000, 18500, 84, 82),
        (18500, 19000, 82, 78),
        (19000, 20000, 78, 73),
        (20000, 21000, 73, 70),
        (21000, cdNyquist, 70, 69),
      ];
      for (final segment in segments) {
        _paintFrequencySlope(
          intensity,
          width: width,
          height: height,
          maxFrequencyHz: cdNyquist,
          lowHz: segment.$1,
          highHz: segment.$2,
          lowIntensity: segment.$3,
          highIntensity: segment.$4,
        );
      }

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: cdNyquist,
      );

      expect(cutoff, cdNyquist);
    });

    test('does not report an isolated line as a broadband cutoff', () {
      final intensity = _blankIntensity(width, height);
      _paintFrequencyBand(
        intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
        lowHz: 53880,
        highHz: 54120,
        intensity: 255,
      );

      final cutoff = estimateEffectiveSpectralCutoffHz(
        intensity: intensity,
        width: width,
        height: height,
        maxFrequencyHz: nyquist,
      );

      expect(cutoff, isNull);
    });

    test('rejects invalid or incomplete images', () {
      expect(
        estimateEffectiveSpectralCutoffHz(
          intensity: Uint8List(0),
          width: 1,
          height: 1,
          maxFrequencyHz: nyquist,
        ),
        isNull,
      );
    });
  });
}
