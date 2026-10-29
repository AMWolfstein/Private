import 'dart:math' as math;

import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/models/settings.dart';
import 'package:sistrum/services/playback/audio_route_info.dart';
import 'package:sistrum/services/playback/music_playback_deck.dart';
import 'package:sistrum/services/playback/playback_equalizer.dart';
import 'package:sistrum/services/playback/playback_handler.dart';
import 'package:sistrum/utils/int_utils.dart';
import 'package:sistrum/utils/string_utils.dart';

class AudioInfoSection {
  const AudioInfoSection(this.title, this.facts);

  final String title;
  final List<AudioInfoFact> facts;
}

class AudioInfoFact {
  const AudioInfoFact(this.label, this.value, {this.emphasis = false});

  final String label;
  final String value;
  final bool emphasis;
}

const _losslessFormats = {'flac', 'alac', 'wav', 'aiff', 'ape', 'wv', 'pcm'};

/// Derives the displayed facts; kept separate from widgets so the copied
/// report matches the sheet exactly.
class AudioInfoFacts {
  AudioInfoFacts({
    required this.l10n,
    required this.metadata,
    required this.path,
    required this.fileSize,
    required this.route,
    required this.usb,
    required this.processing,
    required this.settings,
  });

  final AppLocalizations l10n;
  final Map<String, dynamic> metadata;
  final String? path;
  final int? fileSize;
  final AudioRouteInfo? route;
  final UsbAudioStatus usb;
  final PlaybackProcessing? processing;
  final AppSettings settings;

  late final String format = (metadata['format'] ?? '').toString().trim();
  late final String codec = (metadata['audio_codec'] ?? '').toString().trim();
  late final int? sampleRate =
      readPositiveInt(metadata['sample_rate']) ?? route?.stream?.sampleRate;
  late final int? bitDepth =
      readPositiveInt(metadata['bit_depth']) ?? route?.stream?.pcmBits;
  late final int? channels =
      route?.stream?.channels ?? readPositiveInt(metadata['channels']);
  late final int? bitrateKbps =
      readPositiveInt(metadata['bitrate']) ??
      ((route?.stream?.bitrate ?? 0) > 0
          ? (route!.stream!.bitrate! / 1000).round()
          : null);
  late final int? durationSeconds = readPositiveInt(metadata['duration']);
  late final bool lossless =
      _losslessFormats.contains(format.toLowerCase()) ||
      _losslessFormats.contains(codec.toLowerCase());
  late final bool direct =
      (processing?.direct ?? false) && usb.reason == 'active';

  List<AudioInfoSection> sections() => [
    AudioInfoSection(l10n.audioInfoSource, _source()),
    if (_signal().isNotEmpty) AudioInfoSection(l10n.audioInfoSignal, _signal()),
    AudioInfoSection(l10n.audioInfoLoudness, _loudness()),
    AudioInfoSection(l10n.audioInfoProcessing, _processing()),
    if (_output().isNotEmpty) AudioInfoSection(l10n.audioInfoOutput, _output()),
  ];

  List<AudioInfoFact> _source() {
    final hiRes =
        lossless && ((bitDepth ?? 0) > 16 || (sampleRate ?? 0) > 48000);
    return [
      AudioInfoFact(
        l10n.audioInfoQuality,
        hiRes
            ? l10n.audioInfoHiResLossless
            : lossless
            ? l10n.audioInfoLossless
            : l10n.audioInfoLossy,
        emphasis: true,
      ),
      if (format.isNotEmpty)
        AudioInfoFact(l10n.audioInfoFormat, format.toUpperCase()),
      if (codec.isNotEmpty || route?.stream?.mime != null)
        AudioInfoFact(
          l10n.audioInfoCodec,
          [
            if (codec.isNotEmpty) codec.toUpperCase(),
            ?route?.stream?.mime,
          ].join(' · '),
        ),
      if (sampleRate != null)
        AudioInfoFact(l10n.audioInfoSampleRate, _khz(sampleRate!)),
      if (bitDepth != null)
        AudioInfoFact(l10n.audioInfoBitDepth, '$bitDepth-bit'),
      if (channels != null)
        AudioInfoFact(
          l10n.audioInfoChannels,
          l10n.audioInfoChannelCount(channels!),
        ),
      if (bitrateKbps != null)
        AudioInfoFact(
          l10n.audioInfoBitrate,
          '${_thousands(bitrateKbps!)} kbps',
        ),
      if (durationSeconds != null)
        AudioInfoFact(l10n.audioInfoDuration, formatClock(durationSeconds!)),
      if (fileSize != null)
        AudioInfoFact(l10n.audioInfoFileSize, formatBytes(fileSize!)),
      if (_pcmKbps case final pcm? when bitrateKbps != null)
        AudioInfoFact(
          l10n.audioInfoCompression,
          l10n.audioInfoCompressionValue(
            (bitrateKbps! / pcm * 100).toStringAsFixed(lossless ? 0 : 1),
          ),
        ),
      if (_location case final location?)
        AudioInfoFact(l10n.audioInfoLocation, location),
    ];
  }

  double? get _pcmKbps {
    final rate = sampleRate, bits = lossless ? bitDepth : 16, ch = channels;
    if (rate == null || bits == null || ch == null) return null;
    return rate * bits * ch / 1000;
  }

  String? get _location {
    final path = this.path;
    if (path == null || path.isEmpty) return null;
    if (path.startsWith('content://')) return l10n.audioInfoLocationShared;
    if (path.startsWith('/')) return l10n.audioInfoLocationLocal;
    return null;
  }

  List<AudioInfoFact> _signal() => [
    if (_pcmKbps case final pcm? when lossless)
      AudioInfoFact(l10n.audioInfoPcmRate, '${_thousands(pcm.round())} kbps'),
    if (sampleRate != null)
      AudioInfoFact(
        l10n.audioInfoFrequencyRange,
        l10n.audioInfoFrequencyRangeValue(_khz(sampleRate! ~/ 2)),
      ),
    if (bitDepth case final bits? when lossless)
      AudioInfoFact(l10n.audioInfoDynamicRange, '${(6.02 * bits).round()} dB'),
  ];

  List<AudioInfoFact> _loudness() {
    final tags = [
      (l10n.audioInfoTrackGain, metadata['replaygain_track_gain'], false),
      (l10n.audioInfoTrackPeak, metadata['replaygain_track_peak'], true),
      (l10n.audioInfoAlbumGain, metadata['replaygain_album_gain'], false),
      (l10n.audioInfoAlbumPeak, metadata['replaygain_album_peak'], true),
    ];
    final facts = [
      for (final (label, raw, peak) in tags)
        if (_number(raw) case final value?)
          AudioInfoFact(label, peak ? _peak(value) : _db(value)),
    ];
    final gain = processing?.normalizationGain ?? 1;
    final String normalization;
    if (!settings.playbackNormalization) {
      normalization = l10n.audioInfoOff;
    } else if (direct || settings.usbBitPerfect) {
      normalization = l10n.audioInfoBypassed;
    } else if (gain > 0 && gain != 1) {
      normalization = l10n.audioInfoApplied(
        _db(20 * math.log(gain) / math.ln10),
      );
    } else {
      normalization = l10n.audioInfoOn;
    }
    return [
      if (facts.isEmpty)
        AudioInfoFact(l10n.audioInfoTrackGain, l10n.audioInfoNoGainTags),
      ...facts,
      AudioInfoFact(l10n.libraryPlaybackNormalization, normalization),
    ];
  }

  List<AudioInfoFact> _processing() {
    final route = this.route;
    final String signalPath;
    if (direct && usb.driver == 'usb_direct') {
      signalPath = l10n.audioInfoPathDirect;
    } else if (direct && usb.driver == 'aaudio_exclusive') {
      signalPath = l10n.audioInfoPathExclusive;
    } else {
      signalPath = l10n.audioInfoPathSystem;
    }
    final equalizer = playbackEqualizer.value;
    final eq = !equalizer.enabled
        ? l10n.audioInfoOff
        : direct
        ? l10n.audioInfoBypassed
        : playbackEqualizerError.value != null
        ? playbackEqualizerError.value!
        : [
            l10n.audioInfoOn,
            l10n.audioInfoBands(equalizer.gains.length),
            if (equalizer.inputGain != 0)
              '${l10n.equalizerPreamp} ${_db(equalizer.inputGain)}',
            if (equalizer.compressor) l10n.equalizerCompressor,
          ].join(' · ');
    final rate = processing?.autoMixRate ?? 1;
    final decoder = route?.stream?.decoder;
    return [
      AudioInfoFact(l10n.audioInfoPlayer, l10n.audioInfoPlayerValue),
      AudioInfoFact(l10n.audioInfoSignalPath, signalPath),
      AudioInfoFact(l10n.equalizerTitle, eq),
      if (!direct && decoder != null)
        AudioInfoFact(
          l10n.audioInfoDecoder,
          [
            decoder,
            if (route?.stream?.hardwareDecoder case final hardware?)
              hardware ? l10n.audioInfoHardware : l10n.audioInfoSoftware,
          ].join(' · '),
        ),
      AudioInfoFact(
        'AutoMix',
        settings.autoMix && !settings.usbBitPerfect
            ? l10n.audioInfoOn
            : l10n.audioInfoOff,
      ),
      if ((rate - 1).abs() > 0.001)
        AudioInfoFact(l10n.audioInfoTempo, '${rate.toStringAsFixed(3)}×'),
      if (_resampling case final value?)
        AudioInfoFact(l10n.audioInfoResampling, value),
      AudioInfoFact(
        l10n.audioInfoBitPerfect,
        _bitPerfect
            ? l10n.audioInfoBitPerfectActive
            : l10n.audioInfoBitPerfectNo,
        emphasis: _bitPerfect,
      ),
    ];
  }

  // A preferred mixer format is configuration, not proof of active playback.
  bool get _bitPerfect => direct;

  int? get _outputRate {
    if (direct) return usb.sampleRate;
    return route?.device?.mixerSampleRate ?? route?.mixerSampleRate;
  }

  String? get _resampling {
    final source = sampleRate, output = _outputRate;
    if (source == null || output == null) return null;
    if (_bitPerfect || source == output) return l10n.audioInfoResamplingNone;
    return '${_khz(source)} → ${_khz(output)}';
  }

  List<AudioInfoFact> _output() {
    final route = this.route;
    final device = route?.device;
    final bufferMs = route?.bufferMs;
    final volume = route?.volume;
    return [
      if (device != null)
        AudioInfoFact(
          l10n.audioInfoDevice,
          [
            l10n.audioInfoDeviceType(device.type),
            if (direct && usb.device?.isNotEmpty == true)
              usb.device!
            else if (device.name.isNotEmpty)
              device.name,
          ].join(' · '),
        ),
      if (_outputRate case final rate?)
        AudioInfoFact(l10n.audioInfoOutputRate, _khz(rate)),
      if (direct && usb.bitDepth != null)
        AudioInfoFact(
          l10n.audioInfoOutputFormat,
          [
            '${usb.bitDepth}-bit',
            if (usb.transport != 'pcm') usb.transport.toUpperCase(),
          ].join(' · '),
        )
      else if (device?.mixerBitDepth case final bits?)
        AudioInfoFact(l10n.audioInfoOutputFormat, '$bits-bit'),
      if (device != null && route?.platform == 'android')
        AudioInfoFact(
          l10n.audioInfoDeviceRates,
          device.sampleRates.isEmpty
              ? l10n.audioInfoAnyRate
              : device.sampleRates.map(_khz).join(', '),
        ),
      if (device != null && (device.bitDepths.isNotEmpty || device.floatOutput))
        AudioInfoFact(
          l10n.audioInfoDeviceFormats,
          [
            for (final bits in device.bitDepths)
              if (bits != 32 || !device.floatOutput) '$bits-bit',
            if (device.floatOutput) '32-bit float',
          ].join(', '),
        ),
      if (route?.outputChannels case final count?)
        AudioInfoFact(
          l10n.audioInfoChannels,
          l10n.audioInfoChannelCount(count),
        ),
      if (bufferMs != null)
        AudioInfoFact(
          l10n.audioInfoBuffer,
          [
            '${bufferMs.toStringAsFixed(1)} ms',
            if (route?.framesPerBuffer case final frames?) '$frames frames',
          ].join(' · '),
        ),
      if (route?.outputLatencyMs case final latency?)
        AudioInfoFact(
          l10n.audioInfoLatency,
          '${latency.toStringAsFixed(1)} ms',
        ),
      if (route?.lowLatency case final supported?)
        AudioInfoFact(l10n.audioInfoLowLatency, _supported(supported)),
      if (route?.proAudio case final supported?)
        AudioInfoFact(l10n.audioInfoProAudio, _supported(supported)),
      if (route?.spatialAvailable != null || route?.spatialEnabled != null)
        AudioInfoFact(
          l10n.audioInfoSpatial,
          route?.spatialAvailable == false
              ? l10n.audioInfoUnavailable
              : route?.spatialEnabled == true
              ? l10n.audioInfoOn
              : l10n.audioInfoOff,
        ),
      if (route?.headTracking == true)
        AudioInfoFact(l10n.audioInfoHeadTracking, l10n.audioInfoSupported),
      if (route?.fixedVolume == true || direct)
        AudioInfoFact(l10n.nowPlayingVolume, l10n.audioInfoFixedVolume)
      else if (volume != null)
        AudioInfoFact(
          l10n.nowPlayingVolume,
          route?.maxVolume != null
              ? '${volume.round()} / ${route!.maxVolume}'
              : '${(volume * 100).round()}%',
        ),
    ];
  }

  String _supported(bool value) =>
      value ? l10n.audioInfoSupported : l10n.audioInfoNotSupported;
}

String _khz(int hz) {
  final khz = hz / 1000;
  final text = khz == khz.roundToDouble()
      ? khz.toStringAsFixed(0)
      : khz.toStringAsFixed(khz * 10 == (khz * 10).roundToDouble() ? 1 : 2);
  return '$text kHz';
}

String _thousands(int value) {
  final digits = value.toString();
  final buffer = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
    buffer.write(digits[i]);
  }
  return buffer.toString();
}

/// Signed decibels with a true minus sign.
String _db(double value) {
  final text = value.abs().toStringAsFixed(2);
  if (value.abs() < 0.005) return '0.00 dB';
  return '${value < 0 ? '−' : '+'}$text dB';
}

/// A linear sample peak with its level in dBFS.
String _peak(double value) {
  if (value <= 0) return value.toStringAsFixed(6);
  final dbfs = 20 * math.log(value) / math.ln10;
  return '${value.toStringAsFixed(6)} · ${_db(dbfs).replaceFirst(' dB', ' dBFS')}';
}

/// Reads tag values such as "-6.52 dB" or "0.988831".
final _numberPattern = RegExp(r'[-+]?\d+(?:\.\d+)?');

double? _number(Object? raw) {
  if (raw is num) return raw.toDouble();
  final match = _numberPattern.firstMatch(raw?.toString() ?? '');
  return match == null ? null : double.tryParse(match[0]!);
}
