import 'dart:async';
import 'dart:developer' show TimelineTask;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/quantize/quantizer_celebi.dart';
import 'package:sistrum/services/library/covers/cover_analysis_store.dart';
import 'package:sistrum/services/native/native_data_jobs.dart';
import 'package:sistrum/utils/cover/cover_colors.dart';
import 'package:sistrum/utils/cover/cover_file_image.dart';

export 'package:sistrum/utils/cover/cover_colors.dart'
    show
        CoverAnalysis,
        CoverColors,
        analyzeCover,
        appCoverColors,
        paletteSeedFromColorCounts;

Future<List<List<int>>> _quantizePaletteInIsolate(Uint8List bytes) async {
  final result = await QuantizerCelebi().quantize(
    bytes.buffer.asUint32List(bytes.offsetInBytes, bytes.lengthInBytes ~/ 4),
    128,
  );
  return [
    for (final entry in result.colorToCount.entries) [entry.key, entry.value],
  ];
}

typedef _Sample = ({
  Uint8List rgba,
  int width,
  int height,
  List<List<int>> colors,
});

Map<String, Object> _analyzeInIsolate(_Sample sample) => analyzeCover(
  sample.rgba,
  sample.width,
  sample.height,
  sample.colors,
).toJson();

/// Cover colours: one analysis per cover version, from one small decode.
///
/// Screens read colours only through [colors] (see [appCoverColors]);
/// [resolve] and [peek] keep supplying generated schemes for headers.
class CoverPaletteCache {
  CoverPaletteCache({CoverAnalysisStore? store}) : _store = store;

  /// Analyses survive the app in the library database; this bounded map
  /// keeps the recent ones in memory.
  final Map<String, CoverAnalysis?> _analyses = {};
  final Map<String, ColorScheme> _schemes = {};
  final Map<String, Future<CoverAnalysis?>> _pending = {};
  final Map<String, String> _sourceKeys = {};
  static const int _maxEntries = 32;
  static const sampleSize = 112;

  /// Where analyses persist; null keeps them in memory only.
  final CoverAnalysisStore? _store;

  /// Forgets analyses held in memory, as a new app session would.
  @visibleForTesting
  void debugClearMemory() {
    _analyses.clear();
    _schemes.clear();
    _sourceKeys.clear();
  }

  bool _isNetworkSource(String source) =>
      source.startsWith('http://') || source.startsWith('https://');

  Future<String> _versionKey(String source) async {
    if (_isNetworkSource(source)) return source;
    try {
      final stat = await File(source).stat();
      if (stat.type != FileSystemEntityType.notFound) {
        return '$source|${stat.modified.microsecondsSinceEpoch}|${stat.size}';
      }
    } catch (_) {
      // Resolution below will return null for inaccessible local files.
    }
    return source;
  }

  /// The last analysis for [source], possibly of a previous file version;
  /// null before the first resolution or when the cover is unreadable.
  CoverAnalysis? peekAnalysis(String source) => _analyses[_sourceKeys[source]];

  /// Sistrum's colours for [source]; neutral gray while unknown or without a
  /// cover.
  CoverColors colors(String? source) =>
      appCoverColors(source == null ? null : peekAnalysis(source));

  /// Cached scheme for [source], or null when it has not been resolved yet.
  ColorScheme? peek(String source, Brightness brightness) {
    final key = _sourceKeys[source];
    final analysis = _analyses[key];
    if (key == null || analysis == null) return null;
    return _schemeFor(key, analysis, brightness);
  }

  ColorScheme _schemeFor(
    String key,
    CoverAnalysis analysis,
    Brightness brightness,
  ) {
    final schemeKey = '$key|${brightness.name}';
    final scheme = _schemes[schemeKey] ??= appCoverColors(
      analysis,
    ).scheme(brightness);
    while (_schemes.length > _maxEntries * 2) {
      _schemes.remove(_schemes.keys.first);
    }
    return scheme;
  }

  /// Resolves the scheme for [source] (a network URL or a local file path).
  /// Returns null when the image cannot be decoded.
  Future<ColorScheme?> resolve(String source, Brightness brightness) async {
    final analysis = await resolveAnalysis(source);
    final key = _sourceKeys[source];
    if (analysis == null || key == null) return null;
    return _schemeFor(key, analysis, brightness);
  }

  /// Resolves [source]'s colours; neutral when it cannot be read.
  Future<CoverColors> resolveColors(String? source) async =>
      appCoverColors(source == null ? null : await resolveAnalysis(source));

  /// Mean perceptual lightness (CIE L*, 0..1) of the artwork's top quarter:
  /// what a transparent header floats over. Null when unreadable.
  Future<double?> topLightness(String source) async =>
      (await resolveAnalysis(source))?.topLightness;

  /// Last known [topLightness] for [source], possibly from a previous file
  /// version; null before the first resolution.
  double? peekTopLightness(String source) => peekAnalysis(source)?.topLightness;

  /// One analysis per cover version, shared by every caller.
  Future<CoverAnalysis?> resolveAnalysis(String source) {
    return _pending.putIfAbsent(
      source,
      () =>
          (() async {
            final key = await _versionKey(source);
            final previous = _sourceKeys.remove(source);
            // FileImage keys contain the path, not its modification time. A
            // new version also needs a fresh decode after an in-place edit.
            if ((!_analyses.containsKey(key) ||
                    (previous != null && previous != key)) &&
                !_isNetworkSource(source)) {
              if (previous != null && previous != key) {
                await _evictDecodedImage(FileImage(File(source)));
              }
              await _evictDecodedImage(_sampleOf(FileImage(File(source))));
            }
            _sourceKeys[source] = key;
            while (_sourceKeys.length > _maxEntries) {
              _sourceKeys.remove(_sourceKeys.keys.first);
            }
            if (_analyses.containsKey(key)) return _analyses[key];
            final analysis = await _analyze(source, key);
            _analyses[key] = analysis;
            while (_analyses.length > _maxEntries) {
              _analyses.remove(_analyses.keys.first);
            }
            return analysis;
          })().whenComplete(() {
            // A block body: returning the removed future would await itself.
            _pending.remove(source);
          }),
    );
  }

  ResizeImage _sampleOf(ImageProvider provider) => ResizeImage(
    provider,
    width: sampleSize,
    height: sampleSize,
    policy: ResizeImagePolicy.fit,
  );

  Future<void> _evictDecodedImage(ImageProvider provider) async {
    final key = await provider.obtainKey(ImageConfiguration.empty);
    // A first palette request can overlap the header's initial precache. Do
    // not cancel that pending decode while removing an older retained bitmap.
    if (!PaintingBinding.instance.imageCache.statusForKey(key).pending) {
      await provider.evict();
    }
  }

  Future<CoverAnalysis?> _analyze(String source, String key) async {
    final task = TimelineTask()..start('Sistrum cover analysis');
    try {
      return await _analyzeUntimed(source, key);
    } finally {
      task.finish();
    }
  }

  Future<CoverAnalysis?> _analyzeUntimed(String source, String key) async {
    final store = _store;
    if (store != null && !_isNetworkSource(source)) {
      final stored = await store.read(key);
      if (stored != null) return stored;
    }
    final ImageProvider provider;
    if (_isNetworkSource(source)) {
      provider = cachedCoverImageProvider(source);
    } else {
      final file = File(source);
      if (!await file.exists()) return null;
      provider = FileImage(file);
    }
    try {
      final (bytes, width, height) = await _readSample(_sampleOf(provider));
      late final List<List<int>> colors;
      try {
        final response = await NativeDataJobs.run({
          'operation': 'palette',
        }, bytes: bytes);
        colors = [
          for (final pair in response['colors'] as List)
            [for (final value in pair as List) (value as num).toInt()],
        ];
      } on MissingPluginException {
        // Desktop tests and unsupported hosts retain exact Material output,
        // with the same expensive quantizer moved off the UI isolate.
        colors = await compute(_quantizePaletteInIsolate, bytes);
      }
      final analysis = CoverAnalysis.fromJson(
        await compute(_analyzeInIsolate, (
          rgba: bytes,
          width: width,
          height: height,
          colors: colors,
        )),
      );
      if (analysis != null && store != null && !_isNetworkSource(source)) {
        unawaited(store.write(key, analysis));
      }
      return analysis;
    } catch (_) {
      // Unreachable URL, unsupported format, decode failure: callers fall back
      // to neutral colours.
      return null;
    }
  }

  /// Premultiplied RGBA of the bounded sample, read back once.
  Future<(Uint8List, int, int)> _readSample(ImageProvider provider) {
    final result = Completer<(Uint8List, int, int)>();
    final stream = provider.resolve(
      const ImageConfiguration(size: Size(112, 112)),
    );
    late ImageStreamListener listener;
    late Timer loadFailureTimeout;
    listener = ImageStreamListener(
      (info, _) async {
        loadFailureTimeout.cancel();
        stream.removeListener(listener);
        ui.Picture? picture;
        ui.Image? image;
        try {
          final source = info.image;
          // Mirror Flutter's image-to-palette canvas/readback. Decoding,
          // filtering and premultiplied alpha remain with Flutter's renderer.
          final recorder = ui.PictureRecorder();
          paintImage(
            canvas: Canvas(recorder),
            rect: Rect.fromLTWH(
              0,
              0,
              source.width.toDouble(),
              source.height.toDouble(),
            ),
            image: source,
            filterQuality: FilterQuality.none,
          );
          picture = recorder.endRecording();
          image = await picture.toImage(source.width, source.height);
          final data = await image.toByteData();
          if (data == null) throw StateError('Palette readback failed');
          result.complete((
            data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
            source.width,
            source.height,
          ));
        } catch (error, stack) {
          result.completeError(error, stack);
        } finally {
          image?.dispose();
          picture?.dispose();
          info.dispose();
        }
      },
      onError: (Object error, StackTrace? stack) {
        loadFailureTimeout.cancel();
        stream.removeListener(listener);
        result.completeError(error, stack);
      },
    );
    loadFailureTimeout = Timer(const Duration(seconds: 5), () {
      stream.removeListener(listener);
      result.completeError(TimeoutException('Palette image loading timed out'));
    });
    stream.addListener(listener);
    return result.future;
  }
}

/// Exposes the header's effective [ColorScheme] to descendants.
///
/// Header sub-widgets (meta rows, circle buttons, play actions) live in the
/// screens' own build methods, so they cannot be handed the palette directly;
/// they read it from here and fall back to the app scheme when absent.
class HeaderPalette extends InheritedWidget {
  const HeaderPalette({super.key, required this.scheme, required super.child});

  final ColorScheme scheme;

  static ColorScheme of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<HeaderPalette>()?.scheme ??
      Theme.of(context).colorScheme;

  @override
  bool updateShouldNotify(HeaderPalette oldWidget) =>
      scheme != oldWidget.scheme;
}

/// Resolves [imageSource] into a [ColorScheme] and rebuilds when it arrives.
/// The builder reads the same cover's palette colours for surfaces.
class CoverPaletteBuilder extends StatefulWidget {
  const CoverPaletteBuilder({
    super.key,
    required this.palette,
    required this.imageSource,
    required this.builder,
  });

  /// The app's shared cache; callers pass `paletteOf(context)`.
  final CoverPaletteCache palette;

  /// Cover URL or local path. Null disables palette extraction.
  final String? imageSource;

  final Widget Function(BuildContext context, ColorScheme scheme) builder;

  @override
  State<CoverPaletteBuilder> createState() => _CoverPaletteBuilderState();
}

class _CoverPaletteBuilderState extends State<CoverPaletteBuilder> {
  ColorScheme? _scheme;
  String? _resolvedSource;
  Brightness? _resolvedBrightness;
  int _resolveGeneration = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _maybeResolve();
  }

  @override
  void didUpdateWidget(CoverPaletteBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-check local file identity even when its path did not change. Metadata
    // editing can replace cover bytes in place.
    _maybeResolve();
  }

  void _maybeResolve() {
    final source = widget.imageSource;
    final brightness = Theme.of(context).brightness;
    if (source == null || source.isEmpty) {
      _resolveGeneration++;
      _resolvedSource = null;
      _resolvedBrightness = null;
      _scheme = null;
      return;
    }
    final requestGeneration = ++_resolveGeneration;
    if (_resolvedSource != source || _resolvedBrightness != brightness) {
      _resolvedSource = source;
      _resolvedBrightness = brightness;
      _scheme = widget.palette.peek(source, brightness);
    }

    widget.palette.resolve(source, brightness).then((scheme) {
      if (!mounted) return;
      if (_resolveGeneration != requestGeneration) {
        return;
      }
      if (_scheme != scheme) setState(() => _scheme = scheme);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = _scheme ?? Theme.of(context).colorScheme;
    return HeaderPalette(
      scheme: scheme,
      child: widget.builder(context, scheme),
    );
  }
}
