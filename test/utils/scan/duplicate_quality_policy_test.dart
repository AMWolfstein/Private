import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/services/library/database/library_database_models.dart';
import 'package:sistrum/utils/scan/duplicate_quality_policy.dart';

IsrcDuplicateEntry _entry(
  String id, {
  String filePath = '/music/track.flac',
  String? format,
  int? bitDepth,
  int? sampleRate,
  int? bitrate,
}) => IsrcDuplicateEntry(
  id: id,
  trackName: 'Track',
  artistName: 'Artist',
  albumName: 'Album',
  filePath: filePath,
  format: format,
  bitDepth: bitDepth,
  sampleRate: sampleRate,
  bitrate: bitrate,
);

void main() {
  group('duplicateFidelity', () {
    test('declared codec wins over the filename suffix', () {
      expect(
        duplicateFidelity(_entry('a', format: ' FLAC ', filePath: '/x.mp3')),
        DuplicateFidelity.lossless,
      );
      expect(
        duplicateFidelity(_entry('a', format: 'MP3', filePath: '/x.flac')),
        DuplicateFidelity.lossy,
      );
    });

    test('falls back to the filename suffix when codec is absent', () {
      expect(
        duplicateFidelity(_entry('a', filePath: '/music/a.WAV')),
        DuplicateFidelity.lossless,
      );
      expect(
        duplicateFidelity(_entry('a', filePath: '/music/a.opus')),
        DuplicateFidelity.lossy,
      );
    });

    test('ambiguous M4A containers and unknown codecs stay unknown', () {
      expect(
        duplicateFidelity(_entry('a', filePath: '/music/a.m4a')),
        DuplicateFidelity.unknown,
      );
      expect(
        duplicateFidelity(_entry('a', filePath: '/music/track')),
        DuplicateFidelity.unknown,
      );
    });
  });

  group('hasComparableDuplicateQuality', () {
    test('lossless needs both bit depth and sample rate', () {
      expect(
        hasComparableDuplicateQuality(
          _entry('a', bitDepth: 24, sampleRate: 96000),
        ),
        isTrue,
      );
      expect(
        hasComparableDuplicateQuality(_entry('a', sampleRate: 96000)),
        isFalse,
      );
      expect(
        hasComparableDuplicateQuality(
          _entry('a', bitDepth: 0, sampleRate: 96000),
        ),
        isFalse,
      );
    });

    test('lossy needs a measured bitrate, not sample rate', () {
      expect(
        hasComparableDuplicateQuality(
          _entry('a', filePath: '/a.mp3', sampleRate: 44100),
        ),
        isFalse,
      );
      expect(
        hasComparableDuplicateQuality(
          _entry('a', filePath: '/a.mp3', bitrate: 320000),
        ),
        isTrue,
      );
    });

    test('unknown codecs never authorise choosing a copy', () {
      expect(
        hasComparableDuplicateQuality(
          _entry(
            'a',
            filePath: '/a.m4a',
            bitDepth: 24,
            sampleRate: 96000,
            bitrate: 320000,
          ),
        ),
        isFalse,
      );
    });
  });

  group('compareDuplicateQuality', () {
    test('lossless sorts before lossy regardless of bitrate', () {
      final lossless = _entry(
        'z',
        filePath: '/a.flac',
        bitDepth: 16,
        sampleRate: 44100,
      );
      final lossy = _entry('a', filePath: '/a.mp3', bitrate: 999999);
      expect(compareDuplicateQuality(lossless, lossy), -1);
      expect(compareDuplicateQuality(lossy, lossless), 1);
    });

    test('lossless entries compare bit depth, then sample rate', () {
      final deep = _entry(
        'b',
        filePath: '/a.flac',
        bitDepth: 24,
        sampleRate: 44100,
      );
      final fast = _entry(
        'a',
        filePath: '/a.flac',
        bitDepth: 16,
        sampleRate: 192000,
      );
      expect(compareDuplicateQuality(deep, fast), -1);

      final highRate = _entry(
        'b',
        filePath: '/a.flac',
        bitDepth: 24,
        sampleRate: 96000,
      );
      expect(compareDuplicateQuality(highRate, deep), -1);
    });

    test('lossy entries compare bitrate before sample rate', () {
      final high = _entry(
        'b',
        filePath: '/a.mp3',
        bitrate: 320000,
        sampleRate: 44100,
      );
      final low = _entry(
        'a',
        filePath: '/a.mp3',
        bitrate: 128000,
        sampleRate: 48000,
      );
      expect(compareDuplicateQuality(high, low), -1);
    });

    test('equal quality falls back to the id for a stable order', () {
      final first = _entry('a', filePath: '/a.mp3', bitrate: 256000);
      final second = _entry('b', filePath: '/a.mp3', bitrate: 256000);
      expect(compareDuplicateQuality(first, second), lessThan(0));
      expect(compareDuplicateQuality(second, first), greaterThan(0));
    });
  });
}
