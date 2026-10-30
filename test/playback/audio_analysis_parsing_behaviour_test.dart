import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_parsing.dart';

const _notDetected = 'Not detected';

void main() {
  group('spectral cutoff label', () {
    test(
      'missing, non-finite and non-positive cutoffs show the not-detected label',
      () {
        for (final cutoff in <double?>[
          null,
          0,
          -1,
          double.nan,
          double.infinity,
        ]) {
          expect(
            formatAudioAnalysisSpectralCutoff(
              cutoff,
              notDetectedLabel: _notDetected,
            ),
            _notDetected,
            reason: '$cutoff',
          );
        }
      },
    );

    test('cutoffs below 1 kHz are rounded to whole hertz', () {
      expect(
        formatAudioAnalysisSpectralCutoff(
          440.4,
          notDetectedLabel: _notDetected,
        ),
        '440 Hz',
      );
      expect(
        formatAudioAnalysisSpectralCutoff(
          440.6,
          notDetectedLabel: _notDetected,
        ),
        '441 Hz',
      );
    });

    test('cutoffs from 1 kHz are shown in kHz with one decimal place', () {
      expect(
        formatAudioAnalysisSpectralCutoff(1000, notDetectedLabel: _notDetected),
        '1.0 kHz',
      );
      expect(
        formatAudioAnalysisSpectralCutoff(
          16000,
          notDetectedLabel: _notDetected,
        ),
        '16.0 kHz',
      );
      expect(
        formatAudioAnalysisSpectralCutoff(
          19500,
          notDetectedLabel: _notDetected,
        ),
        '19.5 kHz',
      );
    });
  });

  group('codec support', () {
    test('missing or blank codec names are treated as supported', () {
      for (final codec in <String?>[null, '', '   ']) {
        expect(isAudioAnalysisCodecSupported(codec), isTrue, reason: '$codec');
        expect(unsupportedAudioAnalysisCodecLabel(codec), isNull);
      }
    });

    test('AC-4 is rejected in every spelling used as a standalone token', () {
      for (final codec in ['ac4', 'AC-4', 'ac_4', 'AC 4', 'Dolby AC-4']) {
        expect(isAudioAnalysisCodecSupported(codec), isFalse, reason: codec);
        expect(unsupportedAudioAnalysisCodecLabel(codec), 'AC-4');
      }
    });

    test('other codecs that look similar remain supported', () {
      for (final codec in ['aac', 'alac', 'eac3', 'flac', 'mp4', 'mp3']) {
        expect(isAudioAnalysisCodecSupported(codec), isTrue, reason: codec);
        expect(unsupportedAudioAnalysisCodecLabel(codec), isNull);
      }
    });

    test('the unsupported codec exception carries the label to display', () {
      const error = UnsupportedAudioAnalysisCodecException('AC-4');
      expect(error.codecLabel, 'AC-4');
      expect(error, isA<Exception>());
    });
  });

  group('total sample estimate', () {
    test('a positive nb_samples value wins over the timing fields', () {
      expect(
        estimateAudioTotalSamples(
          props: {'nb_samples': 441000, 'duration_ts': 1, 'time_base': '1/1'},
          duration: 99,
          sampleRate: 44100,
          channels: 2,
        ),
        441000,
      );
      expect(
        estimateAudioTotalSamples(
          props: {'nb_samples': '441000'},
          duration: 0,
          sampleRate: 44100,
          channels: 2,
        ),
        441000,
      );
    });

    test('a zero nb_samples falls back to duration_ts and time_base', () {
      expect(
        estimateAudioTotalSamples(
          props: {
            'nb_samples': '0',
            'duration_ts': '96000',
            'time_base': '1/48000',
          },
          duration: 0,
          sampleRate: 48000,
          channels: 2,
        ),
        96000,
      );
    });

    test('a fractional time base converts duration_ts into seconds', () {
      expect(
        estimateAudioTotalSamples(
          props: {'duration_ts': 180000, 'time_base': '1/90000'},
          duration: 0,
          sampleRate: 44100,
          channels: 2,
        ),
        88200,
      );
    });

    test('an unusable time base falls back to the reported duration', () {
      for (final timeBase in ['0/1', '1/0', '90000', 'a/b', '']) {
        expect(
          estimateAudioTotalSamples(
            props: {'duration_ts': 180000, 'time_base': timeBase},
            duration: 2.5,
            sampleRate: 44100,
            channels: 2,
          ),
          110250,
          reason: timeBase,
        );
      }
    });

    test(
      'without any timing fields the duration times sample rate is used',
      () {
        expect(
          estimateAudioTotalSamples(
            props: const {},
            duration: 2.5,
            sampleRate: 44100,
            channels: 2,
          ),
          110250,
        );
      },
    );

    test('returns zero when neither duration nor sample rate is usable', () {
      expect(
        estimateAudioTotalSamples(
          props: const {},
          duration: 0,
          sampleRate: 44100,
          channels: 2,
        ),
        0,
      );
      expect(
        estimateAudioTotalSamples(
          props: const {},
          duration: 3,
          sampleRate: 0,
          channels: 2,
        ),
        0,
      );
    });
  });

  group('stored bit depth', () {
    test('lossless codecs that store their bit depth are recognised', () {
      for (final codec in [
        'flac',
        'alac',
        'wavpack',
        'ape',
        'tta',
        'pcm_s16le',
        'pcm_s24le',
        'pcm_f32le',
      ]) {
        expect(audioCodecHasStoredBitDepth(codec), isTrue, reason: codec);
      }
    });

    test('lossy codecs and an empty name have no stored bit depth', () {
      for (final codec in ['', 'mp3', 'aac', 'opus', 'vorbis']) {
        expect(audioCodecHasStoredBitDepth(codec), isFalse, reason: codec);
      }
    });
  });

  group('labels', () {
    test('normalized labels are trimmed and placeholders become empty', () {
      expect(normalizeAudioAnalysisLabel('  Dolby Digital  '), 'Dolby Digital');
      for (final placeholder in ['', '   ', 'unknown', 'UNKNOWN', ' N/A ']) {
        expect(
          normalizeAudioAnalysisLabel(placeholder),
          '',
          reason: placeholder,
        );
      }
    });

    test('codec label combines the short name with its long description', () {
      expect(
        formatAudioCodecLabel('mp3', 'MPEG audio layer 3'),
        'MP3 (MPEG audio layer 3)',
      );
      expect(
        formatAudioCodecLabel('  mp3  ', ' MPEG audio layer 3 '),
        'MP3 (MPEG audio layer 3)',
      );
    });

    test(
      'codec label shows only the upper-case short name when the long name adds nothing',
      () {
        expect(formatAudioCodecLabel('opus', ''), 'OPUS');
        expect(formatAudioCodecLabel('opus', 'unknown'), 'OPUS');
        expect(formatAudioCodecLabel('OPUS', 'opus'), 'OPUS');
      },
    );

    test('codec label without a short name uses the long name or nothing', () {
      expect(
        formatAudioCodecLabel('', 'Advanced Audio Coding'),
        'Advanced Audio Coding',
      );
      expect(formatAudioCodecLabel('', 'N/A'), '');
      expect(formatAudioCodecLabel('  ', ' unknown '), '');
    });

    test('container label prefers the long name', () {
      expect(
        formatAudioContainerLabel('mov,mp4,m4a,3gp,3g2,mj2', 'QuickTime / MOV'),
        'QuickTime / MOV',
      );
      expect(formatAudioContainerLabel('ogg', ' Ogg '), 'Ogg');
    });

    test('container label falls back to the upper-case short name', () {
      expect(formatAudioContainerLabel('flac', ''), 'FLAC');
      expect(formatAudioContainerLabel('mp3', 'unknown'), 'MP3');
      expect(formatAudioContainerLabel('  wav ', 'N/A'), 'WAV');
      expect(formatAudioContainerLabel('', 'N/A'), '');
    });
  });

  test('the library barrel also exposes the log parser', () {
    final summary = parseAudioAstatsSummary(
      'Overall\n'
      'Peak level dB: -1.0\n'
      'RMS level dB: -14.5\n'
      'Peak level dB: -0.5\n'
      'RMS level dB: -12.0\n',
    );
    expect(summary?.peakDb, -0.5);
    expect(summary?.rmsDb, -12.0);
  });
}
