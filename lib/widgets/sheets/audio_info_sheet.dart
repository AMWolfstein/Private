import 'package:sistrum/services/native/media_file_bridge.dart';
import 'package:sistrum/services/playback/playback_equalizer.dart';
import 'dart:io';

import 'package:flutter/cupertino.dart' show CupertinoButton;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sistrum/providers/player_metadata_controller.dart';
import 'package:sistrum/l10n/l10n.dart';
import 'package:sistrum/services/playback/audio_route_info.dart';
import 'package:sistrum/services/playback/music_playback_deck.dart';
import 'package:sistrum/services/playback/music_player_service.dart';
import 'package:sistrum/theme/app_tokens.dart';
import 'package:sistrum/widgets/primitives/app_bottom_sheet.dart';
import 'package:sistrum/widgets/audio_analysis/audio_analysis_widget.dart';
import 'package:sistrum/widgets/settings/settings_item_rows.dart';
import 'package:sistrum/widgets/sheets/app_audio_info_fact_rows.dart';
import 'package:sistrum/widgets/sheets/audio_info_facts.dart';

/// Technical details of the playing track, from the file through the
/// processing chain to the output device.
Future<void> showAudioInfoSheet(
  BuildContext context, {
  required PlayerMetadataController metadata,
}) => showAppBottomSheet<void>(
  context: context,
  title: context.l10n.audioInfoTitle,
  subtitle: metadata.qualityLabel,
  maxHeightFactor: 0.9,
  useRootNavigator: true,
  builder: (context) => _AudioInfoSheet(metadata: metadata),
);

class _AudioInfoSheet extends StatefulWidget {
  const _AudioInfoSheet({required this.metadata});

  final PlayerMetadataController metadata;

  @override
  State<_AudioInfoSheet> createState() => _AudioInfoSheetState();
}

class _AudioInfoSheetState extends State<_AudioInfoSheet> {
  final _controller = ScrollController();
  AudioRouteInfo? _route;
  int? _fileSize;
  String? _loadedPath;
  int _loadGeneration = 0;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    widget.metadata.addListener(_load);
    _load();
  }

  @override
  void dispose() {
    widget.metadata.removeListener(_load);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final path = widget.metadata.filePath;
    if (path == _loadedPath && (_loading || _route != null)) return;
    final generation = ++_loadGeneration;
    _loadedPath = path;
    _loading = true;
    _route = null;
    _fileSize = null;
    final results = await Future.wait<Object?>([
      readAudioRouteInfo(path: path),
      _sizeOf(path),
    ]);
    if (!mounted || generation != _loadGeneration) return;
    setState(() {
      _loading = false;
      _route = results[0] as AudioRouteInfo?;
      _fileSize = results[1] as int?;
    });
  }

  static Future<int?> _sizeOf(String? path) async {
    if (path == null || path.isEmpty) return null;
    try {
      if (path.startsWith('content://')) {
        final size = (await MediaFileBridge.safStat(path))['size'];
        return size is num && size > 0 ? size.toInt() : null;
      }
      if (!path.startsWith('/')) return null;
      return await File(path).length();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([
      widget.metadata,
      usbAudioStatus,
      playbackEqualizer,
      playbackEqualizerError,
    ]),
    builder: (context, _) {
      final facts = AudioInfoFacts(
        l10n: context.l10n,
        metadata: widget.metadata.metadata ?? const {},
        path: widget.metadata.filePath,
        fileSize: _fileSize,
        route: _route,
        usb: usbAudioStatus.value,
        processing: musicPlayerRuntime.handler?.processing,
        settings: musicPlayerRuntime.settings,
      );
      final sections = facts.sections();
      final path = widget.metadata.filePath;
      final analyzable =
          path != null &&
          path.isNotEmpty &&
          !const {'http', 'https'}.contains(Uri.tryParse(path)?.scheme);
      final format = widget.metadata.metadata?['format']?.toString();
      return SingleChildScrollView(
        controller: _controller,
        padding: EdgeInsets.only(bottom: context.tokens.gapLg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final section in sections) ...[
              SettingsSectionHeader(title: section.title),
              AppAudioInfoFactGroup(
                children: [
                  for (final (index, fact) in section.facts.indexed)
                    AppAudioInfoFactRow(
                      fact: fact,
                      last: index == section.facts.length - 1,
                    ),
                ],
              ),
            ],
            if (analyzable) ...[
              SettingsSectionHeader(title: context.l10n.audioInfoAnalysis),
              Padding(
                padding: EdgeInsets.symmetric(horizontal: context.tokens.gapLg),
                child: Column(
                  children: [
                    AudioAnalysisCard(filePath: path, codecHint: format),
                  ],
                ),
              ),
            ],
            SizedBox(height: context.tokens.gapLg),
            AppAudioInfoFactGroup(
              children: [
                CupertinoButton(
                  minimumSize: Size.square(context.tokens.minTouchTarget),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  onPressed: () => _copy(context, sections),
                  child: Text(context.l10n.audioInfoCopy),
                ),
              ],
            ),
          ],
        ),
      );
    },
  );

  Future<void> _copy(
    BuildContext context,
    List<AudioInfoSection> sections,
  ) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final copied = context.l10n.audioInfoCopied;
    final report = StringBuffer(widget.metadata.qualityLabel ?? '');
    for (final section in sections) {
      report
        ..writeln()
        ..writeln()
        ..writeln(section.title);
      for (final fact in section.facts) {
        report.writeln('${fact.label}: ${fact.value}');
      }
    }
    await Clipboard.setData(ClipboardData(text: report.toString().trim()));
    messenger?.showSnackBar(SnackBar(content: Text(copied)));
  }
}
