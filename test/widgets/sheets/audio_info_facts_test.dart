import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sistrum/l10n/app_localizations.dart';
import 'package:sistrum/core/models/settings.dart';
import 'package:sistrum/services/playback/core/music_playback_deck.dart';
import 'package:sistrum/widgets/sheets/audio_info_facts.dart';

AudioInfoFacts _facts(AppLocalizations l10n, Map<String, dynamic> metadata) =>
    AudioInfoFacts(
      l10n: l10n,
      metadata: metadata,
      path: '/music/song',
      fileSize: null,
      route: null,
      usb: const UsbAudioStatus(),
      processing: null,
      settings: const AppSettings(),
    );

void main() {
  final l10n = lookupAppLocalizations(const Locale('en'));

  test('a 24-bit 96 kHz FLAC is reported as hi-res lossless', () {
    final source = _facts(l10n, {
      'format': 'flac',
      'sample_rate': 96000,
      'bit_depth': 24,
    }).sections().first;
    expect(source.facts.first.label, l10n.audioInfoQuality);
    expect(source.facts.first.value, l10n.audioInfoHiResLossless);
    expect(source.facts.first.emphasis, isTrue);
  });

  test('a CD-quality FLAC is lossless but not hi-res', () {
    final source = _facts(l10n, {
      'format': 'flac',
      'sample_rate': 44100,
      'bit_depth': 16,
    }).sections().first;
    expect(source.facts.first.value, l10n.audioInfoLossless);
  });

  test('an MP3 is reported as lossy with its format in upper case', () {
    final facts = _facts(l10n, {
      'format': 'mp3',
      'bitrate': 320,
    }).sections().first.facts;
    expect(facts.first.value, l10n.audioInfoLossy);
    expect(facts.any((fact) => fact.value == 'MP3'), isTrue);
  });

  test('the sections start with the source and always include loudness', () {
    final sections = _facts(l10n, {'format': 'mp3'}).sections();
    expect(sections.first.title, l10n.audioInfoSource);
    expect(
      sections.map((section) => section.title),
      contains(l10n.audioInfoLoudness),
    );
  });
}
