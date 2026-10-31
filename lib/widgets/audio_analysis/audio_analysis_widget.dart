import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/cupertino.dart' show CupertinoIcons;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/core/theme/app_theme.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_controller.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_parsing.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_worker.dart';
import 'package:sistrum/services/audio_analysis/audio_analysis_store.dart';
import 'package:sistrum/widgets/settings/settings_group.dart';
import 'package:sistrum/widgets/primitives/app_content_card.dart';
import 'package:sistrum/widgets/primitives/app_choice_chip.dart';
import 'package:path/path.dart' as p;
import 'package:sistrum/l10n/l10n.dart';
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
  late final AudioAnalysisController _controller = AudioAnalysisController(
    filePath: widget.filePath,
    codecHint: widget.codecHint,
    artifacts: const ProcessAudioAnalysisArtifacts(),
    createWorker: (checkRequest) =>
        FfmpegAudioAnalysisWorker(checkRequest: checkRequest),
  );
  bool _savingSpectrogram = false;

  AudioAnalysisData? get _data => _controller.data;
  bool get _analyzing => _controller.analyzing;
  bool get _checkingCache => _controller.checkingCache;
  Object? get _error => _controller.error;
  ui.Image? get _spectrogramImage => _controller.spectrogramImage;
  int get _spectrogramChannel => _controller.spectrogramChannel;
  bool get _spectrogramChannelLoading => _controller.spectrogramChannelLoading;
  String? get _unsupportedCodec => _controller.unsupportedCodec;

  bool get _isSupported => AudioAnalysisController.supports(widget.filePath);

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    _controller.start();
  }

  @override
  void didUpdateWidget(covariant AudioAnalysisCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filePath == widget.filePath &&
        oldWidget.codecHint == widget.codecHint) {
      return;
    }
    _controller.changeFile(widget.filePath, codecHint: widget.codecHint);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    if (mounted) setState(() {});
  }

  void _rebuild(VoidCallback fn) => setState(fn);

  Future<void> _analyze({bool forceRefresh = false}) =>
      _controller.analyze(forceRefresh: forceRefresh);

  Future<void> _changeSpectrogramChannel(int channel) =>
      _controller.changeChannel(channel);

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
                  context.friendlyError(_error),
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
