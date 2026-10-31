part of 'audio_analysis_widget.dart';

extension _AudioAnalysisCardStatePart1 on _AudioAnalysisCardState {
  void _checkAnalysisRequest(int requestId) {
    if (!mounted || requestId != _spectrogramRequestId) {
      throw const AudioAnalysisCancelled();
    }
  }

  void _cancelNativeAnalysis() {
    for (final request in _nativeAnalysisRequests) {
      unawaited(_cancelNativeAnalysisRequest(request));
    }
  }

  Future<void> _cancelNativeAnalysisRequest(String request) async {
    try {
      await NativeDataJobs.cancel(request);
    } catch (_) {
      // Await the owned worker before temp cleanup even if cancellation fails.
    }
  }

  bool get _isSupported {
    final lower = widget.filePath.toLowerCase();
    return _AudioAnalysisCardState._supportedExtensions.any(
      (ext) => lower.endsWith(ext),
    );
  }

  Future<void> _tryLoadFromCache() async {
    final expectedPath = widget.filePath;
    final requestId = _spectrogramRequestId;
    final releaseCache = audioAnalysisCacheBudget.retain(
      audioAnalysisCacheKey(expectedPath),
    );
    bool isCurrentRequest() =>
        mounted &&
        widget.filePath == expectedPath &&
        requestId == _spectrogramRequestId;

    try {
      final cached = await loadAudioAnalysisFromCache(expectedPath);
      if (cached != null && isCurrentRequest()) {
        final unsupported = unsupportedAudioAnalysisCodecLabel(cached.codec);
        if (unsupported != null) {
          await clearAudioAnalysisCache(expectedPath);
          if (isCurrentRequest()) {
            _rebuild(() {
              _unsupportedCodec = unsupported;
              _checkingCache = false;
            });
          }
          return;
        }
        _rebuild(() {
          _data = cached;
          _checkingCache = false;
        });
        var image = await loadSpectrogramFromCache(
          expectedPath,
          channel: _spectrogramChannel,
        );
        image ??= await _generateAndCacheSpectrogram(
          filePath: expectedPath,
          analysisData: cached,
          requestId: requestId,
        );
        if (isCurrentRequest()) {
          _rebuild(() {
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
      unawaited(trimAudioAnalysisCache());
    }
    if (isCurrentRequest()) {
      _rebuild(() => _checkingCache = false);
    }
  }

  Future<ui.Image> _generateAndCacheSpectrogram({
    String? filePath,
    AudioAnalysisData? analysisData,
    required int requestId,
  }) async {
    _checkAnalysisRequest(requestId);
    final sourcePath = filePath ?? widget.filePath;
    final data = analysisData ?? _data;
    final channel = _spectrogramChannel;
    final artifact = await _runner.generateSpectrogramForFile(
      sourcePath,
      requestId: requestId,
      channel: channel,
      durationSeconds: data?.duration,
      sampleRate: data?.sampleRate,
      channels: data?.channels,
    );
    await saveSpectrogramToCache(sourcePath, artifact.image, channel: channel);
    return artifact.image;
  }

  Future<void> _analyze({bool forceRefresh = false}) async {
    if (_analyzing) return;
    final sourcePath = widget.filePath;
    final releaseCache = audioAnalysisCacheBudget.retain(
      audioAnalysisCacheKey(sourcePath),
    );
    final requestId = ++_spectrogramRequestId;
    _analysisJobs.invalidate();
    _cancelNativeAnalysis();
    _rebuild(() {
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
        await clearAudioAnalysisCache(sourcePath);
      }

      final cached = forceRefresh
          ? null
          : await loadAudioAnalysisFromCache(sourcePath);
      _checkAnalysisRequest(requestId);
      AudioAnalysisData data;
      ui.Image? image;

      if (cached != null) {
        final unsupported = unsupportedAudioAnalysisCodecLabel(cached.codec);
        if (unsupported != null) {
          throw UnsupportedAudioAnalysisCodecException(unsupported);
        }
        data = cached;
        image = await loadSpectrogramFromCache(
          sourcePath,
          channel: _spectrogramChannel,
        );
      } else {
        final result = await _runner.runAnalysis(sourcePath, requestId);
        data = result.data;
        image = result.spectrogramImage;
        await saveAudioAnalysisToCache(sourcePath, data);
        await saveSpectrogramToCache(
          sourcePath,
          image,
          channel: _spectrogramChannel,
        );
      }

      image ??= await _generateAndCacheSpectrogram(
        filePath: sourcePath,
        analysisData: data,
        requestId: requestId,
      );

      if (mounted && requestId == _spectrogramRequestId) {
        _rebuild(() {
          _data = data;
          _spectrogramImage?.dispose();
          _spectrogramImage = image;
          _analyzing = false;
        });
      } else {
        image.dispose();
      }
    } on AudioAnalysisCancelled {
      // A new file/request owns the state; cancelled native work is cleaned up.
    } on UnsupportedAudioAnalysisCodecException catch (e) {
      if (mounted && requestId == _spectrogramRequestId) {
        _rebuild(() {
          _unsupportedCodec = e.codecLabel;
          _error = null;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted && requestId == _spectrogramRequestId) {
        _rebuild(() {
          _error = context.friendlyError(e);
          _analyzing = false;
        });
      }
    } finally {
      releaseCache();
      unawaited(trimAudioAnalysisCache());
    }
  }

  /// Renders the spectrogram with its axes and legend, then asks where to
  /// save it through the system file picker.
  Future<void> _saveSpectrogram() async {
    final data = _data;
    final shown = _spectrogramImage;
    if (data == null || shown == null || _savingSpectrogram) return;
    final l10n = context.l10n;
    final channel = _spectrogramChannel;
    final baseName = audioSpectrogramExportBaseName(
      widget.filePath,
      exportName: widget.exportName,
    );
    final fileName = channel < 0
        ? '${baseName}_spectrogram.png'
        : '${baseName}_spectrogram_ch${channel + 1}.png';
    // A channel switch disposes the shown image while this still renders.
    final image = shown.clone();
    _rebuild(() => _savingSpectrogram = true);
    try {
      final bytes = await renderAudioSpectrogramPng(
        image: image,
        title: baseName,
        sampleRate: data.sampleRate,
        duration: data.duration,
        details: [
          '${l10n.audioAnalysisSampleRate}: ${data.sampleRate} Hz',
          '${l10n.audioAnalysisNyquist}: '
              '${(data.sampleRate / 2000).toStringAsFixed(1)} kHz',
          if (channel >= 0) 'Ch ${channel + 1}',
        ],
      );
      final saved = await FilePicker.saveFile(
        fileName: fileName,
        bytes: bytes,
        mimeType: 'image/png',
        dialogTitle: l10n.audioAnalysisSaveSpectrogram,
      );
      if (saved == null || !mounted) return;
      final savedName = saved.scheme == 'file'
          ? p.basename(saved.toFilePath())
          : fileName;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(l10n.audioAnalysisSpectrogramSaved(savedName)),
          ),
        );
    } catch (e) {
      _log.e('Could not save the spectrogram: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(content: Text(l10n.audioAnalysisSpectrogramSaveFailed)),
        );
    } finally {
      image.dispose();
      if (mounted) _rebuild(() => _savingSpectrogram = false);
    }
  }

  Future<void> _changeSpectrogramChannel(int channel) async {
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
    final sourcePath = widget.filePath;
    final releaseCache = audioAnalysisCacheBudget.retain(
      audioAnalysisCacheKey(sourcePath),
    );
    final requestId = ++_spectrogramRequestId;
    _rebuild(() {
      _spectrogramChannel = channel;
      _spectrogramChannelLoading = true;
    });

    ui.Image? image;
    try {
      image = await loadSpectrogramFromCache(sourcePath, channel: channel);
      if (image == null) {
        final artifact = await _runner.generateSpectrogramForFile(
          sourcePath,
          requestId: requestId,
          channel: channel,
          durationSeconds: data.duration,
          sampleRate: data.sampleRate,
          channels: data.channels,
        );
        image = artifact.image;
        await saveSpectrogramToCache(sourcePath, image, channel: channel);
      }

      if (!mounted || requestId != _spectrogramRequestId) {
        image.dispose();
        return;
      }
      _rebuild(() {
        _spectrogramImage?.dispose();
        _spectrogramImage = image;
        _spectrogramChannelLoading = false;
      });
    } catch (_) {
      image?.dispose();
      if (mounted && requestId == _spectrogramRequestId) {
        _rebuild(() {
          _spectrogramChannel = previousChannel;
          _spectrogramChannelLoading = false;
        });
      }
    } finally {
      releaseCache();
      unawaited(trimAudioAnalysisCache());
    }
  }
}
