import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path_provider/path_provider.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_cache.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_log_parsing.dart';
import 'package:sistrum/services/native/media_file_bridge.dart';

/// Persisted analysis results and their cached spectrogram images, shared by
/// the analysis card and its tests.

class AudioAnalysisData {
  static const cacheVersion = 14;

  final String filePath;
  final int fileSize;
  final int fileModified;
  final String codec;
  final String container;
  final String decodedSampleFormat;
  final int sampleRate;
  final int channels;
  final String channelLayout;
  final int bitsPerSample;
  final double duration;
  final int bitrate;
  final String bitDepth;
  final double dynamicRange;
  final double peakAmplitude;
  final double rmsLevel;
  final double? integratedLufs;
  final double? truePeakDb;
  final int clippingSamples;
  final double? spectralCutoffHz;
  final List<ChannelAnalysisStats> channelStats;
  final int totalSamples;

  const AudioAnalysisData({
    required this.filePath,
    required this.fileSize,
    this.fileModified = 0,
    this.codec = '',
    this.container = '',
    this.decodedSampleFormat = '',
    required this.sampleRate,
    required this.channels,
    this.channelLayout = '',
    required this.bitsPerSample,
    required this.duration,
    required this.bitrate,
    required this.bitDepth,
    required this.dynamicRange,
    required this.peakAmplitude,
    required this.rmsLevel,
    this.integratedLufs,
    this.truePeakDb,
    this.clippingSamples = 0,
    this.spectralCutoffHz,
    this.channelStats = const [],
    required this.totalSamples,
  });

  Map<String, dynamic> toJson() => {
    'filePath': filePath,
    'cacheVersion': cacheVersion,
    'fileSize': fileSize,
    'fileModified': fileModified,
    'codec': codec,
    'container': container,
    'decodedSampleFormat': decodedSampleFormat,
    'sampleRate': sampleRate,
    'channels': channels,
    'channelLayout': channelLayout,
    'bitsPerSample': bitsPerSample,
    'duration': duration,
    'bitrate': bitrate,
    'bitDepth': bitDepth,
    'dynamicRange': dynamicRange,
    'peakAmplitude': peakAmplitude,
    'rmsLevel': rmsLevel,
    'integratedLufs': integratedLufs,
    'truePeakDb': truePeakDb,
    'clippingSamples': clippingSamples,
    'spectralCutoffHz': spectralCutoffHz,
    'channelStats': channelStats.map((stats) => stats.toJson()).toList(),
    'totalSamples': totalSamples,
  };

  factory AudioAnalysisData.fromJson(Map<String, dynamic> json) {
    return AudioAnalysisData(
      filePath: json['filePath'] as String,
      fileSize: json['fileSize'] as int,
      fileModified: (json['fileModified'] as num?)?.toInt() ?? 0,
      codec: json['codec']?.toString() ?? '',
      container: json['container']?.toString() ?? '',
      decodedSampleFormat: json['decodedSampleFormat']?.toString() ?? '',
      sampleRate: json['sampleRate'] as int,
      channels: json['channels'] as int,
      channelLayout: json['channelLayout']?.toString() ?? '',
      bitsPerSample: json['bitsPerSample'] as int,
      duration: (json['duration'] as num).toDouble(),
      bitrate: json['bitrate'] as int,
      bitDepth: json['bitDepth'] as String,
      dynamicRange: (json['dynamicRange'] as num).toDouble(),
      peakAmplitude: (json['peakAmplitude'] as num).toDouble(),
      rmsLevel: (json['rmsLevel'] as num).toDouble(),
      integratedLufs: (json['integratedLufs'] as num?)?.toDouble(),
      truePeakDb: (json['truePeakDb'] as num?)?.toDouble(),
      clippingSamples: (json['clippingSamples'] as num?)?.toInt() ?? 0,
      spectralCutoffHz: (json['spectralCutoffHz'] as num?)?.toDouble(),
      channelStats:
          (json['channelStats'] as List?)
              ?.whereType<Map<dynamic, dynamic>>()
              .map((item) => ChannelAnalysisStats.fromJson(item))
              .toList() ??
          const [],
      totalSamples: json['totalSamples'] as int,
    );
  }
}

/// Decodes a cached spectrogram image, returning null when the bytes are not a
/// complete image.
///
/// `decodeImageFromList` reports a truncated PNG as an unhandled async error
/// and never completes its callback, so the cache path must use a codec whose
/// failure can be caught (and the damaged file dropped).
Future<ui.Image?> decodeCachedSpectrogramBytes(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      return (await codec.getNextFrame()).image;
    } finally {
      codec.dispose();
    }
  } catch (_) {
    return null;
  }
}

// Cache bundles keyed by a hash of the source path.
Future<void> clearAudioAnalysisCache(String filePath) async {
  try {
    final dir = await _cacheDir();
    final key = audioAnalysisCacheKey(filePath);
    final jsonFile = File('${dir.path}/$key.json');
    if (await jsonFile.exists()) {
      await jsonFile.delete();
    }
    await for (final entity in dir.list()) {
      if (entity is! File) continue;
      final name = entity.path.replaceAll('\\', '/').split('/').last;
      final isCombined = name == '$key.png';
      final isChannel = name.startsWith('${key}_ch') && name.endsWith('.png');
      if (isCombined || isChannel) {
        await entity.delete();
      }
    }
  } catch (_) {}
}

String audioAnalysisCacheKey(String filePath) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(filePath)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0x7FFFFFFFFFFFFFFF;
  }
  return hash.toRadixString(16);
}

Future<Directory> _cacheDir() async {
  final appSupport = await getApplicationSupportDirectory();
  final dir = Directory('${appSupport.path}/audio_analysis_cache');
  if (!await dir.exists()) {
    await dir.create(recursive: true);
  }
  return dir;
}

final audioAnalysisCacheBudget = AudioAnalysisCache();

Future<void> trimAudioAnalysisCache() async {
  try {
    await audioAnalysisCacheBudget.trim(await _cacheDir());
  } catch (_) {
    // Cache maintenance must not interrupt the selected track's analysis.
  }
}

Future<AudioAnalysisData?> loadAudioAnalysisFromCache(String filePath) async {
  try {
    final dir = await _cacheDir();
    final key = audioAnalysisCacheKey(filePath);
    final file = File('${dir.path}/$key.json');
    if (!await file.exists()) return null;

    final json = Map<String, dynamic>.from(
      jsonDecode(await file.readAsString()) as Map,
    );
    if (json['cacheVersion'] != AudioAnalysisData.cacheVersion) {
      return null;
    }
    final cachedSize = json['fileSize'] as int;
    final cachedModified = (json['fileModified'] as num?)?.toInt() ?? 0;

    if (!filePath.startsWith('content://')) {
      final stat = await File(filePath).stat();
      if (stat.size != cachedSize) return null;
      if (cachedModified > 0 &&
          stat.modified.millisecondsSinceEpoch != cachedModified) {
        return null;
      }
    } else {
      final stat = await MediaFileBridge.safStat(filePath);
      final currentSize = (stat['size'] as num?)?.toInt() ?? 0;
      if (currentSize > 0 && currentSize != cachedSize) return null;
      final currentModified = (stat['modified'] as num?)?.toInt() ?? 0;
      if (cachedModified > 0 &&
          currentModified > 0 &&
          currentModified != cachedModified) {
        return null;
      }
    }

    final data = AudioAnalysisData.fromJson(json);
    await file.setLastModified(DateTime.now());
    return data;
  } catch (_) {
    return null;
  }
}

Future<void> saveAudioAnalysisToCache(
  String filePath,
  AudioAnalysisData data,
) async {
  try {
    final dir = await _cacheDir();
    final key = audioAnalysisCacheKey(filePath);
    final file = File('${dir.path}/$key.json');
    final json = data.toJson();
    json['fileModified'] = await _sourceModified(filePath);
    await file.writeAsString(jsonEncode(json));
  } catch (_) {}
}

Future<int> _sourceModified(String filePath) async {
  try {
    if (filePath.startsWith('content://')) {
      final stat = await MediaFileBridge.safStat(filePath);
      return (stat['modified'] as num?)?.toInt() ?? 0;
    }
    return (await File(filePath).stat()).modified.millisecondsSinceEpoch;
  } catch (_) {
    return 0;
  }
}

Future<void> saveSpectrogramToCache(
  String filePath,
  ui.Image image, {
  required int channel,
}) async {
  try {
    final dir = await _cacheDir();
    final key = audioAnalysisCacheKey(filePath);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData != null) {
      final file = File(
        '${dir.path}/${_spectrogramCacheFileName(key, channel)}',
      );
      await file.writeAsBytes(byteData.buffer.asUint8List());
      await audioAnalysisCacheBudget.trim(dir);
    }
  } catch (_) {}
}

String _spectrogramCacheFileName(String key, int channel) =>
    channel < 0 ? '$key.png' : '${key}_ch$channel.png';

Future<ui.Image?> loadSpectrogramFromCache(
  String filePath, {
  required int channel,
}) async {
  File? file;
  try {
    final dir = await _cacheDir();
    final key = audioAnalysisCacheKey(filePath);
    file = File('${dir.path}/${_spectrogramCacheFileName(key, channel)}');
    if (!await file.exists()) return null;

    final image = await decodeCachedSpectrogramBytes(await file.readAsBytes());
    if (image != null) return image;
    // A truncated PNG (app killed during the write) must not wedge the card:
    // drop it so the next analysis regenerates it.
    try {
      await file.delete();
    } catch (_) {
      // The cache trim retries an unreadable entry later.
    }
    return null;
  } catch (_) {
    if (file != null) {
      try {
        await file.delete();
      } catch (_) {
        // The cache trim retries an unreadable entry later.
      }
    }
    return null;
  }
}
