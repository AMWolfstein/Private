import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_jobs.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_parsing.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_store.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_worker.dart';

/// Owns one file's analysis state: cache reads, analysis, spectrogram channel
/// switching and cancellation. It has no widget or BuildContext dependency, so
/// the card renders its state and the workflow is testable without a mount.
///
/// Every operation belongs to a request id. A newer request (a different file,
/// a forced refresh, a channel switch) makes the older one stop without
/// touching state, and [dispose] cancels whatever is still running.
final class AudioAnalysisController extends ChangeNotifier {
  AudioAnalysisController({
    required String filePath,
    String? codecHint,
    required AudioAnalysisArtifacts artifacts,
    required AudioAnalysisWorker Function(
      void Function(int requestId) checkRequest,
    )
    createWorker,
  }) : _filePath = filePath,
       _artifacts = artifacts,
       _unsupportedCodec = unsupportedAudioAnalysisCodecLabel(codecHint) {
    _worker = createWorker(_checkRequest);
  }

  static const supportedExtensions = {
    '.flac',
    '.mp3',
    '.m4a',
    '.mp4',
    '.aac',
    '.ac3',
    '.eac3',
    '.opus',
    '.ogg',
    '.wav',
    '.wma',
    '.mka',
    '.wv',
    '.ape',
    '.tta',
    '.aif',
    '.aiff',
  };

  /// Whether [path] has an extension the analyser can read.
  static bool supports(String path) {
    final lower = path.toLowerCase();
    return supportedExtensions.any(lower.endsWith);
  }

  final AudioAnalysisArtifacts _artifacts;
  late final AudioAnalysisWorker _worker;
  String _filePath;
  int _requestId = 0;
  bool _disposed = false;

  AudioAnalysisData? _data;
  bool _analyzing = false;
  bool _checkingCache = true;
  Object? _error;
  ui.Image? _spectrogramImage;
  int _spectrogramChannel = -1;
  bool _spectrogramChannelLoading = false;
  String? _unsupportedCodec;

  String get filePath => _filePath;
  AudioAnalysisData? get data => _data;
  bool get analyzing => _analyzing;
  bool get checkingCache => _checkingCache;
  Object? get error => _error;
  ui.Image? get spectrogramImage => _spectrogramImage;
  int get spectrogramChannel => _spectrogramChannel;
  bool get spectrogramChannelLoading => _spectrogramChannelLoading;
  String? get unsupportedCodec => _unsupportedCodec;

  /// Starts the cache lookup for the initial file. Unsupported codecs skip it.
  void start() {
    if (!supports(_filePath)) return;
    if (_unsupportedCodec == null) {
      unawaited(loadCached());
    } else {
      _checkingCache = false;
    }
  }

  /// Switches to [path]. Nothing is notified: the caller is still building.
  void changeFile(String path, {String? codecHint}) {
    _filePath = path;
    _requestId++;
    _worker.invalidate();
    _worker.cancelNative();
    _spectrogramImage?.dispose();
    _spectrogramImage = null;
    _spectrogramChannel = -1;
    _spectrogramChannelLoading = false;
    _data = null;
    _error = null;
    _analyzing = false;
    _unsupportedCodec = unsupportedAudioAnalysisCodecLabel(codecHint);
    _checkingCache = supports(path) && _unsupportedCodec == null;
    if (_checkingCache) unawaited(loadCached());
  }

  /// Shows the cached analysis and spectrogram for the current file, if any.
  Future<void> loadCached() async {
    final expectedPath = _filePath;
    final requestId = _requestId;
    final releaseCache = _artifacts.retain(expectedPath);
    bool isCurrent() => _isCurrent(expectedPath, requestId);

    try {
      final cached = await _artifacts.loadAnalysis(expectedPath);
      if (cached != null && isCurrent()) {
        final unsupported = unsupportedAudioAnalysisCodecLabel(cached.codec);
        if (unsupported != null) {
          await _artifacts.clearAnalysis(expectedPath);
          if (isCurrent()) {
            _update(() {
              _unsupportedCodec = unsupported;
              _checkingCache = false;
            });
          }
          return;
        }
        _update(() {
          _data = cached;
          _checkingCache = false;
        });
        var image = await _artifacts.loadSpectrogram(
          expectedPath,
          channel: _spectrogramChannel,
        );
        image ??= await _generateSpectrogram(
          expectedPath,
          analysis: cached,
          requestId: requestId,
        );
        if (isCurrent()) {
          _update(() {
            _spectrogramImage?.dispose();
            _spectrogramImage = image;
          });
        } else {
          image.dispose();
        }
        return;
      }
    } catch (_) {
      // Missing or unreadable cache entries fall back to the Analyze action.
    } finally {
      releaseCache();
      _artifacts.trim();
    }
    if (isCurrent()) {
      _update(() => _checkingCache = false);
    }
  }

  /// Analyses the current file, or re-analyses it after clearing the cache.
  Future<void> analyze({bool forceRefresh = false}) async {
    if (_analyzing) return;
    final sourcePath = _filePath;
    final releaseCache = _artifacts.retain(sourcePath);
    final requestId = ++_requestId;
    _worker.invalidate();
    _worker.cancelNative();
    _update(() {
      _analyzing = true;
      _spectrogramChannelLoading = false;
      _error = null;
      if (forceRefresh) {
        _spectrogramImage?.dispose();
        _spectrogramImage = null;
        _data = null;
        _spectrogramChannel = -1;
      }
    });

    try {
      if (forceRefresh) {
        await _artifacts.clearAnalysis(sourcePath);
      }
      final cached = forceRefresh
          ? null
          : await _artifacts.loadAnalysis(sourcePath);
      _checkRequest(requestId);
      AudioAnalysisData data;
      ui.Image? image;

      if (cached != null) {
        final unsupported = unsupportedAudioAnalysisCodecLabel(cached.codec);
        if (unsupported != null) {
          throw UnsupportedAudioAnalysisCodecException(unsupported);
        }
        data = cached;
        image = await _artifacts.loadSpectrogram(
          sourcePath,
          channel: _spectrogramChannel,
        );
      } else {
        final result = await _worker.analyze(sourcePath, requestId);
        data = result.data;
        image = result.spectrogramImage;
        await _artifacts.saveAnalysis(sourcePath, data);
        await _artifacts.saveSpectrogram(
          sourcePath,
          image,
          channel: _spectrogramChannel,
        );
      }

      image ??= await _generateSpectrogram(
        sourcePath,
        analysis: data,
        requestId: requestId,
      );

      if (_isCurrent(sourcePath, requestId)) {
        _update(() {
          _data = data;
          _spectrogramImage?.dispose();
          _spectrogramImage = image;
          _analyzing = false;
        });
      } else {
        image.dispose();
      }
    } on AudioAnalysisCancelled {
      // A newer request owns the state; cancelled native work is cleaned up.
    } on UnsupportedAudioAnalysisCodecException catch (e) {
      if (_isCurrent(sourcePath, requestId)) {
        _update(() {
          _unsupportedCodec = e.codecLabel;
          _error = null;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (_isCurrent(sourcePath, requestId)) {
        _update(() {
          _error = e;
          _analyzing = false;
        });
      }
    } finally {
      releaseCache();
      _artifacts.trim();
    }
  }

  /// Shows another channel's spectrogram. The previous one stays on failure.
  Future<void> changeChannel(int channel) async {
    final data = _data;
    if (data == null ||
        _spectrogramChannelLoading ||
        _analyzing ||
        channel == _spectrogramChannel ||
        channel < -1 ||
        channel >= data.channels) {
      return;
    }

    final previousChannel = _spectrogramChannel;
    final sourcePath = _filePath;
    final releaseCache = _artifacts.retain(sourcePath);
    final requestId = ++_requestId;
    _update(() {
      _spectrogramChannel = channel;
      _spectrogramChannelLoading = true;
    });

    ui.Image? image;
    try {
      image = await _artifacts.loadSpectrogram(sourcePath, channel: channel);
      if (image == null) {
        final artifact = await _worker.spectrogram(
          sourcePath,
          requestId: requestId,
          channel: channel,
          durationSeconds: data.duration,
          sampleRate: data.sampleRate,
          channels: data.channels,
        );
        image = artifact.image;
        await _artifacts.saveSpectrogram(sourcePath, image, channel: channel);
      }

      if (!_isCurrent(sourcePath, requestId)) {
        image.dispose();
        return;
      }
      _update(() {
        _spectrogramImage?.dispose();
        _spectrogramImage = image;
        _spectrogramChannelLoading = false;
      });
    } catch (_) {
      image?.dispose();
      if (_isCurrent(sourcePath, requestId)) {
        _update(() {
          _spectrogramChannel = previousChannel;
          _spectrogramChannelLoading = false;
        });
      }
    } finally {
      releaseCache();
      _artifacts.trim();
    }
  }

  /// Stops superseded work. The request id moves on, so nothing it returns
  /// is shown; native jobs are cancelled and awaited by the worker.
  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _requestId++;
    _worker.dispose();
    _worker.cancelNative();
    _spectrogramImage?.dispose();
    _spectrogramImage = null;
    super.dispose();
  }

  Future<ui.Image> _generateSpectrogram(
    String path, {
    required AudioAnalysisData analysis,
    required int requestId,
  }) async {
    _checkRequest(requestId);
    final channel = _spectrogramChannel;
    final artifact = await _worker.spectrogram(
      path,
      requestId: requestId,
      channel: channel,
      durationSeconds: analysis.duration,
      sampleRate: analysis.sampleRate,
      channels: analysis.channels,
    );
    await _artifacts.saveSpectrogram(path, artifact.image, channel: channel);
    return artifact.image;
  }

  bool _isCurrent(String path, int requestId) =>
      !_disposed && path == _filePath && requestId == _requestId;

  void _checkRequest(int requestId) {
    if (_disposed || requestId != _requestId) {
      throw const AudioAnalysisCancelled();
    }
  }

  void _update(VoidCallback change) {
    change();
    if (!_disposed) notifyListeners();
  }
}
