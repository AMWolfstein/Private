import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_session.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_jobs.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_parsing.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_runner.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_store.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/primitives/app_content_card.dart';
import 'package:sistrum/widgets/primitives/app_choice_chip.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/utils/logging/logger.dart';
import 'package:sistrum/utils/text/string_utils.dart';

export 'package:sistrum/services/audio_analysis/audio_analysis_parsing.dart';

part 'audio_analysis_info_card.dart';
part 'audio_analysis_spectrogram.dart';

final _log = AppLogger('AudioAnalysis');

class AudioAnalysisCard extends StatefulWidget {
  final String filePath;
  final String? codecHint;

  /// Names the saved spectrogram image, such as "Artist - Title". Without
  /// it the name comes from [filePath].
  final String? exportName;

  const AudioAnalysisCard({
    super.key,
    required this.filePath,
    this.codecHint,
    this.exportName,
  });

  @override
  State<AudioAnalysisCard> createState() => _AudioAnalysisCardState();
}

class _AudioAnalysisCardState extends State<AudioAnalysisCard> {
  AudioAnalysisData? _data;
  bool _analyzing = false;
  bool _checkingCache = true;
  String? _error;
  ui.Image? _spectrogramImage;
  int _spectrogramChannel = -1;
  bool _spectrogramChannelLoading = false;
  int _spectrogramRequestId = 0;
  bool _savingSpectrogram = false;
  String? _unsupportedCodec;
  final _analysisJobs = AudioAnalysisJobs<FFmpegSession>(
    start: (arguments) async {
      final completed = Completer<FFmpegSession>();
      final session = await FFmpegKit.executeWithArgumentsAsync(
        arguments,
        completed.complete,
      );
      final id = session.getSessionId();
      if (id == null) {
        // Never pass null to cancel: FFmpegKit interprets it as cancel-all.
        await completed.future;
        throw StateError('Analysis session has no ID');
      }
      return (id: id, completed: completed.future);
    },
    cancel: (id) => FFmpegKit.cancel(id),
  );

  void _checkAnalysisRequest(int requestId) {
    if (!mounted || requestId != _spectrogramRequestId) {
      throw const AudioAnalysisCancelled();
    }
  }

  final _nativeAnalysisRequests = <String>{};

  late final _runner = AudioAnalysisRunner(
    jobs: _analysisJobs,
    nativeRequests: _nativeAnalysisRequests,
    checkRequest: _checkAnalysisRequest,
  );

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

  static const _supportedExtensions = {
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

  bool get _isSupported {
    final lower = widget.filePath.toLowerCase();
    return _supportedExtensions.any((ext) => lower.endsWith(ext));
  }

  @override
  void initState() {
    super.initState();
    _unsupportedCodec = unsupportedAudioAnalysisCodecLabel(widget.codecHint);
    if (_isSupported) {
      if (_unsupportedCodec == null) {
        _tryLoadFromCache();
      } else {
        _checkingCache = false;
      }
    }
  }

  @override
  void didUpdateWidget(covariant AudioAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath == widget.filePath &&
        oldWidget.codecHint == widget.codecHint) {
      return;
    }

    _spectrogramRequestId++;
    _analysisJobs.invalidate();
    _cancelNativeAnalysis();
    _spectrogramImage?.dispose();
    _spectrogramImage = null;
    _spectrogramChannel = -1;
    _spectrogramChannelLoading = false;
    _data = null;
    _error = null;
    _analyzing = false;
    _unsupportedCodec = unsupportedAudioAnalysisCodecLabel(widget.codecHint);
    _checkingCache = _isSupported && _unsupportedCodec == null;

    if (_checkingCache) {
      unawaited(_tryLoadFromCache());
    }
  }

  @override
  void dispose() {
    _spectrogramRequestId++;
    _analysisJobs.dispose();
    _cancelNativeAnalysis();
    _spectrogramImage?.dispose();
    super.dispose();
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
            setState(() {
              _unsupportedCodec = unsupported;
              _checkingCache = false;
            });
          }
          return;
        }
        setState(() {
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
          setState(() {
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
      setState(() => _checkingCache = false);
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
    setState(() {
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
        setState(() {
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
        setState(() {
          _unsupportedCodec = e.codecLabel;
          _error = null;
          _analyzing = false;
        });
      }
    } catch (e) {
      if (mounted && requestId == _spectrogramRequestId) {
        setState(() {
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
    setState(() => _savingSpectrogram = true);
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
      if (mounted) setState(() => _savingSpectrogram = false);
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
    setState(() {
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
      setState(() {
        _spectrogramImage?.dispose();
        _spectrogramImage = image;
        _spectrogramChannelLoading = false;
      });
    } catch (_) {
      image?.dispose();
      if (mounted && requestId == _spectrogramRequestId) {
        setState(() {
          _spectrogramChannel = previousChannel;
          _spectrogramChannelLoading = false;
        });
      }
    } finally {
      releaseCache();
      unawaited(trimAudioAnalysisCache());
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_isSupported) return const SizedBox.shrink();

    final cs = Theme.of(context).colorScheme;
    final l10n = context.l10n;

    if (_checkingCache) return const SizedBox.shrink();

    if (_unsupportedCodec != null) {
      return AppContentCard(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.audioAnalysisTitle,
                      style: TextStyle(
                        color: cs.onSurface,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${l10n.snackbarUnsupportedAudioFormat}: '
                      '$_unsupportedCodec',
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_analyzing) {
      final isRescan = _data != null || _spectrogramImage != null;
      return AppContentCard(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2.5),
                ),
                const SizedBox(height: 12),
                Text(
                  isRescan
                      ? l10n.audioAnalysisRescanning
                      : l10n.audioAnalysisAnalyzing,
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      );
    }

    if (_error != null) {
      return AppContentCard(
        preserveColor: true,
        color: cs.errorContainer,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: cs.onErrorContainer),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _error!,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, size: 20),
                tooltip: l10n.audioAnalysisRescan,
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                color: cs.onErrorContainer,
                onPressed: () => _analyze(forceRefresh: true),
              ),
            ],
          ),
        ),
      );
    }

    if (_data == null) {
      return AppContentCard(
        elevation: 0,
        color: settingsGroupColor(context),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          onTap: _analyze,
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.audioAnalysisTitle,
                        style: TextStyle(
                          color: cs.onSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        l10n.audioAnalysisDescription,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: cs.onSurfaceVariant),
              ],
            ),
          ),
        ),
      );
    }

    final data = _data!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _AudioInfoCard(
          data: data,
          onRescan: () => _analyze(forceRefresh: true),
        ),
        if (_spectrogramImage != null) ...[
          const SizedBox(height: 12),
          _SpectrogramView(
            image: _spectrogramImage!,
            sampleRate: data.sampleRate,
            maxFreq: data.sampleRate / 2,
            duration: data.duration,
            channels: data.channels,
            selectedChannel: _spectrogramChannel,
            channelLoading: _spectrogramChannelLoading,
            onChannelChanged: _changeSpectrogramChannel,
            onSave: _savingSpectrogram || _spectrogramChannelLoading
                ? null
                : _saveSpectrogram,
          ),
        ],
      ],
    );
  }
}
